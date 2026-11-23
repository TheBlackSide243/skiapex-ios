#!/usr/bin/env bash
# Screenshots for the README, taken in the iOS Simulator with made-up ski days.
# Needs the Xcode project generated (xcodegen generate).
# Usage: scripts/screenshots.sh <out dir>
set -euo pipefail

OUT="${1:-screenshots}"
BUNDLE=com.local.skiapex
mkdir -p "$OUT"

xcodebuild -project SkiApex.xcodeproj -scheme SkiApex -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/sim CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
APP="build/sim/Build/Products/Debug-iphonesimulator/SkiApex.app"
test -d "$APP"

# The newest iOS runtime's device whose name matches the first pattern that finds one.
pick() {
  xcrun simctl list devices available -j | python3 -c '
import json, re, sys
pats = sys.argv[1:]
data = json.load(sys.stdin)["devices"]
def ver(rt):
    m = re.search(r"iOS-(\d+)-(\d+)", rt)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)
runtimes = sorted((rt for rt in data if "iOS" in rt), key=ver, reverse=True)
for p in pats:
    for rt in runtimes:
        for d in data[rt]:
            if re.search(p, d["name"]):
                print(d["udid"], d["name"], sep="|")
                sys.exit(0)
sys.exit(1)
' "$@"
}

found="$(pick '^iPhone \d+ Pro$' '^iPhone \d+$' 'iPhone')"
udid="${found%%|*}"
echo "== ${found#*|} ($udid)"
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl ui "$udid" appearance dark || true
xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$udid" "$APP"

for s in ${SCREENS:-ready live days day timeline run replay share stats settings empty}; do
  xcrun simctl terminate "$udid" "$BUNDLE" 2>/dev/null || true
  tries=0
  until xcrun simctl launch "$udid" "$BUNDLE" -demo -screen "$s" ${ARGS:-} -AppleLanguages "(${LANG_CODE:-it})" -AppleLocale "${LOCALE_CODE:-it_IT}" >/dev/null; do
    tries=$((tries + 1)); [ $tries -ge 4 ] && { echo "   $s: the app did not open"; continue 2; }
    sleep 15
  done
  # The map needs a moment to download its tiles.
  sleep 14
  xcrun simctl io "$udid" screenshot --type=png "$OUT/iphone-$s.png" >/dev/null
  echo "   iphone-$s.png"
done
xcrun simctl shutdown "$udid" || true

# Crash reports of the app from the simulator, if any.
mkdir -p "$OUT/crashes"
find "$HOME/Library/Logs/DiagnosticReports" -iname 'SkiApex*' -newer "$APP" -exec cp {} "$OUT/crashes/" \; 2>/dev/null || true
ls -la "$OUT" "$OUT/crashes"
