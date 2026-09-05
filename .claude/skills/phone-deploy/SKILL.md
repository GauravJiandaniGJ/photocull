---
name: phone-deploy
description: Build, install and launch PhotoCull on a physical iPhone from the CLI (xcodebuild + devicectl), including first-time pairing, signing and Developer Mode gotchas. Use when the user says "put it on my phone", "install on the 17 Pro Max / 15 Pro", "device build", or when a change touches Vision, PhotoKit or performance and must be judged on hardware.
---

# Deploy to a phone

Vision results (aesthetics, face capture quality, feature-print distances) are only meaningful
on a real device, and every milestone ends with a build on the primary phone. This is the
main dev loop; the simulator is for Core tests and layout only (see `sim-qa`).

## 1. Preconditions (once per Mac / phone)
- Xcode is signed in to the paid team `D4U39723T4` (Xcode → Settings → Accounts). Automatic
  signing + `-allowProvisioningUpdates` then registers the device and makes the profile.
- The phone is paired and trusted: plug in, unlock, tap Trust, then Xcode → Window → Devices
  shows it. Enable Settings → Privacy & Security → Developer Mode (iOS 16+; phone reboots).
- After the first install, the phone may ask to trust the developer:
  Settings → General → VPN & Device Management → the team → Trust.
- Wi-Fi pairing works after the first USB pair; `xcrun devicectl list devices` shows
  `tunnelState = connected` when the device is reachable.

## 2. Run it
```bash
scripts/deploy-phone.sh              # detects the one connected iPhone
scripts/deploy-phone.sh --list       # paired devices with UDIDs
DEVICE_UDID=<udid> scripts/deploy-phone.sh
```
The script regenerates the Xcode project if it is missing, builds Debug for that device
into `build/DerivedData`, installs with `devicectl`, and launches
`com.vandnajiandani.photocull`. Incremental builds are fine here.

## 3. After it launches
- First launch asks for Photos access; choose **Allow Full Access**. "Limited" shows the
  explanation screen with a link to Settings — that is designed, not a bug.
- Scans are long (spec §2: ~15–25 min for 5k photos on the 17 Pro Max). Keep the phone
  plugged in; the app keeps the screen awake during a scan.
- Logs: `xcrun devicectl device process launch --console --device <udid> <bundle id>`
  streams stdout, or use Console.app filtered on "PhotoCull".

## 4. When it fails
- `No connected iPhone` → unlock the phone, check the cable, or re-pair in Xcode.
- Signing errors → open `PhotoCull.xcodeproj` once in Xcode so it can resolve the team
  interactively, then re-run the script.
- "Untrusted Developer" on launch → step 1's trust setting.
- Two phones connected → pass `DEVICE_UDID` explicitly.

## 5. Hard rules
- Never work around a delete-related bug by testing on a library you care about: the only
  delete path is Apply (spec §8), and Recently Deleted is the safety net, not a test fixture.
- Do not commit `build/` or the generated `.xcodeproj` (both git-ignored).
