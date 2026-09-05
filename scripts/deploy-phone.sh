#!/usr/bin/env bash
# Build → install → launch PhotoCull on a connected iPhone, no Xcode GUI needed.
#   scripts/deploy-phone.sh                     auto-detects the single connected iPhone
#   DEVICE_UDID=<udid> scripts/deploy-phone.sh  pick one explicitly
#   scripts/deploy-phone.sh --list              show paired devices and exit
# First time on a new phone: pair + trust it in Xcode (Window → Devices) and enable
# Settings → Privacy & Security → Developer Mode on the phone.
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID=com.vandnajiandani.photocull

if [[ "${1:-}" == "--list" ]]; then
    xcrun devicectl list devices
    exit 0
fi

if [[ -z "${DEVICE_UDID:-}" ]]; then
    json=$(mktemp)
    xcrun devicectl list devices --json-output "$json" >/dev/null
    DEVICE_UDID=$(python3 - "$json" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
phones = [
    d for d in devices
    if d.get("hardwareProperties", {}).get("deviceType") == "iPhone"
    and d.get("connectionProperties", {}).get("tunnelState") == "connected"
]
if len(phones) == 1:
    print(phones[0]["identifier"])
elif not phones:
    sys.exit("No connected iPhone. Plug one in (or pair over Wi-Fi in Xcode), unlock it, and trust this Mac. `--list` shows paired devices.")
else:
    lines = "\n".join(f"  DEVICE_UDID={p['identifier']}   # {p['deviceProperties']['name']}" for p in phones)
    sys.exit("Several iPhones connected; pick one:\n" + lines)
PY
)
fi

[[ -d PhotoCull.xcodeproj ]] || xcodegen generate

xcodebuild -project PhotoCull.xcodeproj -scheme PhotoCull -configuration Debug \
    -destination "platform=iOS,id=$DEVICE_UDID" \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    -derivedDataPath build/DerivedData \
    build | tail -5

APP="build/DerivedData/Build/Products/Debug-iphoneos/PhotoCull.app"
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP"
xcrun devicectl device process launch --device "$DEVICE_UDID" "$BUNDLE_ID"
echo "Launched $BUNDLE_ID on $DEVICE_UDID."
