#!/usr/bin/env python3
"""Prepares Ski Apex on App Store Connect for TestFlight. Safe to run again: what is there is kept.

1. Registers the bundle ID (the App ID) if it is missing.
2. If the app exists on App Store Connect (it is created by hand there: the API cannot), makes the
   internal group and the external group with a public link, writes the TestFlight description in
   Italian and English, and copies the beta review contact, the feedback address and the internal
   testers from another app of the same account (COPY_FROM, a bundle ID).

Nothing personal is printed: only names of groups and what was done.

Environment: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (the .p8 text), BUNDLE, NAME, COPY_FROM
(optional). Needs PyJWT and cryptography.
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
INTERNAL = "Test interni"
EXTERNAL = "Amici"
DESCRIPTIONS = {
    "it": "Ski Apex registra le tue giornate sugli sci: premi Inizia, metti l'iPhone in tasca e scia. "
          "Riconosce da sola discese e risalite, con velocità, dislivello, chilometri, quota e la mappa "
          "della giornata. Tutto resta sul tuo iPhone. Senza neve puoi creare una giornata di prova "
          "dalle Impostazioni.",
    "en-US": "Ski Apex records your days on skis: tap Start, put your iPhone in your pocket and ski. It "
             "recognizes runs and lifts on its own, with speed, vertical, distance, altitude and the map "
             "of the day. Everything stays on your iPhone. Without snow you can make a sample day in "
             "Settings.",
}


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


def soft(status, data, what):
    """A step that may fail without stopping the rest."""
    if status >= 300:
        details = "; ".join(e.get("detail") or e.get("title", "") for e in data.get("errors", []))
        print(f"!! {what}: {status} {details}")
        return None
    return data


def app_with(bundle):
    found = need(*call("GET", "apps?" + urllib.parse.urlencode({"filter[bundleId]": bundle})), "app")["data"]
    return next((a for a in found if a["attributes"]["bundleId"] == bundle), None)


def main():
    bundle, name = os.environ["BUNDLE"], os.environ["NAME"]
    source_bundle = os.environ.get("COPY_FROM") or ""

    # 1. The App ID.
    query = urllib.parse.urlencode({"filter[identifier]": bundle, "limit": 200})
    ids = need(*call("GET", "bundleIds?" + query), "bundle IDs")["data"]
    if any(b["attributes"]["identifier"] == bundle for b in ids):
        print(f"App ID {bundle}: already registered")
    else:
        need(*call("POST", "bundleIds", {"data": {"type": "bundleIds", "attributes": {
            "identifier": bundle, "name": name, "platform": "IOS"}}}), "register the App ID")
        print(f"App ID {bundle}: registered")

    # 2. The app.
    app = app_with(bundle)
    if not app:
        print("The app is not on App Store Connect yet: create it there (My Apps, +), then run this again.")
        return
    app_id = app["id"]
    print(f"App: {app['attributes']['name']} ({app_id})")
    source = app_with(source_bundle) if source_bundle else None
    if source_bundle and not source:
        print(f"!! no app with bundle {source_bundle} to copy from")

    # Groups.
    groups = need(*call("GET", f"apps/{app_id}/betaGroups?limit=50"), "groups")["data"]
    by_name = {g["attributes"]["name"]: g for g in groups}
    relation = {"app": {"data": {"type": "apps", "id": app_id}}}
    if INTERNAL not in by_name:
        made = soft(*call("POST", "betaGroups", {"data": {"type": "betaGroups", "attributes": {
            "name": INTERNAL, "isInternalGroup": True, "hasAccessToAllBuilds": True},
            "relationships": relation}}), "internal group")
        if made:
            by_name[INTERNAL] = made["data"]
            print(f"Group {INTERNAL}: made")
    else:
        print(f"Group {INTERNAL}: already there")
    if EXTERNAL not in by_name:
        made = soft(*call("POST", "betaGroups", {"data": {"type": "betaGroups", "attributes": {
            "name": EXTERNAL, "publicLinkEnabled": True, "publicLinkLimitEnabled": False,
            "feedbackEnabled": True}, "relationships": relation}}), "external group")
        if made:
            by_name[EXTERNAL] = made["data"]
            print(f"Group {EXTERNAL}: made")
    else:
        print(f"Group {EXTERNAL}: already there")
    link = (by_name.get(EXTERNAL) or {}).get("attributes", {}).get("publicLink")
    if link:
        print("Public link:", link)

    # The internal testers of the other app, here too.
    if source and INTERNAL in by_name:
        theirs = need(*call("GET", f"apps/{source['id']}/betaGroups?limit=50"), "source groups")["data"]
        internal = next((g for g in theirs if g["attributes"].get("isInternalGroup")), None)
        if internal:
            testers = need(*call("GET", f"betaGroups/{internal['id']}/betaTesters?limit=50"), "testers")["data"]
            if testers:
                done = soft(*call("POST", f"betaGroups/{by_name[INTERNAL]['id']}/relationships/betaTesters",
                                  {"data": [{"type": "betaTesters", "id": t["id"]} for t in testers]}),
                            "internal testers")
                if done is not None:
                    print(f"Internal testers: {len(testers)} added")

    # The TestFlight description, and the feedback address of the other app.
    feedback = None
    if source:
        theirs = need(*call("GET", f"apps/{source['id']}/betaAppLocalizations"), "source texts")["data"]
        feedback = next((l["attributes"].get("feedbackEmail") for l in theirs if l["attributes"].get("feedbackEmail")), None)
    mine = need(*call("GET", f"apps/{app_id}/betaAppLocalizations"), "texts")["data"]
    for locale, text in DESCRIPTIONS.items():
        attributes = {"description": text}
        if feedback:
            attributes["feedbackEmail"] = feedback
        current = next((l for l in mine if l["attributes"]["locale"] == locale), None)
        if current:
            done = soft(*call("PATCH", f"betaAppLocalizations/{current['id']}", {"data": {
                "type": "betaAppLocalizations", "id": current["id"], "attributes": attributes}}), locale)
        else:
            done = soft(*call("POST", "betaAppLocalizations", {"data": {
                "type": "betaAppLocalizations", "attributes": {"locale": locale, **attributes},
                "relationships": relation}}), locale)
        if done is not None:
            print(f"Description ({locale}): written")

    # Who the beta review can reach: the same as the other app.
    if source:
        theirs = need(*call("GET", f"apps/{source['id']}/betaAppReviewDetail"), "source contact")["data"]
        fields = ("contactFirstName", "contactLastName", "contactPhone", "contactEmail")
        contact = {k: theirs["attributes"].get(k) for k in fields if theirs["attributes"].get(k)}
        if contact:
            contact["demoAccountRequired"] = False
            done = soft(*call("PATCH", f"betaAppReviewDetails/{app_id}", {"data": {
                "type": "betaAppReviewDetails", "id": app_id, "attributes": contact}}), "review contact")
            if done is not None:
                print("Review contact: copied")


if __name__ == "__main__":
    main()
