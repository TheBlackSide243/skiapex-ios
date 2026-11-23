#!/usr/bin/env python3
"""Puts a TestFlight build in the external group "Amici" (public link) and sends it to beta review.

Waits until App Store Connect has processed the build, writes "What to test" in Italian and
English from testflight/whats-new.it.txt and testflight/whats-new.en.txt, adds the build to the
group and submits it. Safe to run twice: each step is skipped when already done.

Environment: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (the .p8 text), BUNDLE, BUILD (build number,
e.g. 5.12), GROUP (default Amici). Needs PyJWT and cryptography.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1/"


def token():
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1000, "aud": "appstoreconnect-v1"},
        os.environ["ASC_KEY_P8"],
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def call(method, path, body=None):
    request = urllib.request.Request(
        API + path,
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            text = response.read()
            return response.status, (json.loads(text) if text else {})
    except urllib.error.HTTPError as error:
        text = error.read()
        try:
            return error.code, json.loads(text)
        except ValueError:
            return error.code, {"errors": [{"detail": text[:300].decode(errors="replace")}]}


def need(status, data, what):
    if status >= 300:
        details = "; ".join(e.get("detail") or e.get("title", "") for e in data.get("errors", []))
        sys.exit(f"{what}: {status} {details}")
    return data


def main():
    bundle, build_number = os.environ["BUNDLE"], os.environ["BUILD"]
    group_name = os.environ.get("GROUP") or "Amici"

    app = need(*call("GET", "apps?" + urllib.parse.urlencode({"filter[bundleId]": bundle})), "app")["data"]
    if not app:
        sys.exit(f"No app with bundle {bundle}")
    app_id = app[0]["id"]

    # Processing takes a few minutes after the upload.
    build = None
    for attempt in range(60):
        query = urllib.parse.urlencode({"filter[app]": app_id, "filter[version]": build_number, "limit": 1})
        found = need(*call("GET", "builds?" + query), "build")["data"]
        if found and found[0]["attributes"]["processingState"] == "VALID":
            build = found[0]
            break
        state = found[0]["attributes"]["processingState"] if found else "not uploaded yet"
        print(f"Build {build_number}: {state}, waiting…", flush=True)
        time.sleep(30)
    if not build:
        sys.exit(f"Build {build_number} was not processed in 30 minutes")
    build_id = build["id"]
    print(f"Build {build_number} ready ({build_id})")

    # What to test, in both languages.
    existing = need(*call("GET", f"builds/{build_id}/betaBuildLocalizations"), "notes")["data"]
    for locale, name in (("it", "testflight/whats-new.it.txt"), ("en-US", "testflight/whats-new.en.txt")):
        with open(name, encoding="utf-8") as file:
            text = file.read().strip()
        current = next((l for l in existing if l["attributes"]["locale"] == locale), None)
        if current:
            need(*call("PATCH", f"betaBuildLocalizations/{current['id']}", {"data": {
                "type": "betaBuildLocalizations", "id": current["id"], "attributes": {"whatsNew": text}}}), locale)
        else:
            need(*call("POST", "betaBuildLocalizations", {"data": {
                "type": "betaBuildLocalizations", "attributes": {"locale": locale, "whatsNew": text},
                "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}}), locale)
        print(f"What to test ({locale}) written")

    groups = need(*call("GET", f"apps/{app_id}/betaGroups?limit=50"), "groups")["data"]
    group = next((g for g in groups if g["attributes"]["name"] == group_name), None)
    if not group:
        sys.exit(f"No group named {group_name}")
    need(*call("POST", f"betaGroups/{group['id']}/relationships/builds",
               {"data": [{"type": "builds", "id": build_id}]}), "add to group")
    print(f"Added to {group_name}")

    status, data = call("POST", "betaAppReviewSubmissions", {"data": {
        "type": "betaAppReviewSubmissions", "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
    if status < 300:
        print("Sent to beta review:", data["data"]["attributes"].get("betaReviewState"))
    elif status == 409:
        print("Already submitted to beta review")
    else:
        need(status, data, "beta review")
    link = group["attributes"].get("publicLink")
    if link:
        print("Public link:", link)


if __name__ == "__main__":
    main()
