---
name: testflight-build
description: Produce and verify a store-distributable PhotoCull build (archive → export → .ipa) and upload it through Xcode Organizer for TestFlight — build-number rules, fresh DerivedData, entitlement checks. Use when the user says "TestFlight build", "archive", "upload to App Store Connect", or wants the app on the second phone without a cable.
---

# TestFlight build

## 0. Do you need this?
For the two target phones, `phone-deploy` over USB/Wi-Fi is faster and needs no upload.
TestFlight is for installing on a phone that is not paired with this Mac, or for a build
that should keep working past the 7-day free-team limit (not an issue on the paid team).

## 1. Preconditions
- Xcode signed in to the paid team `D4U39723T4`.
- App record exists in App Store Connect for `com.vandnajiandani.photocull` (create it once
  in ASC → Apps → + with that bundle id; the id must first exist under Identifiers).
- `CURRENT_PROJECT_VERSION` in `project.yml` is higher than any build already uploaded —
  ASC rejects a reused `CFBundleVersion`. `MARKETING_VERSION` stays `1.0` until a real release.

## 2. Archive → export
```bash
xcodegen generate
rm -rf build/PhotoCull.xcarchive build/ipa build/ArchiveDerivedData
xcodebuild -project PhotoCull.xcodeproj -scheme PhotoCull -configuration Release \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates \
  -derivedDataPath build/ArchiveDerivedData \
  -archivePath build/PhotoCull.xcarchive archive
xcodebuild -exportArchive -archivePath build/PhotoCull.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/ipa \
  -allowProvisioningUpdates
```
The fresh `-derivedDataPath` is deliberate: in the Coach JI project a stale DerivedData once
silently dropped a package from an archive that still "succeeded". Keep it.

## 3. Verify the .ipa before handing it over
```bash
rm -rf /tmp/ipa-verify && unzip -oq build/ipa/*.ipa -d /tmp/ipa-verify
plutil -p /tmp/ipa-verify/Payload/PhotoCull.app/Info.plist | grep -E 'CFBundleVersion|CFBundleShortVersionString|NSPhotoLibraryUsageDescription'
codesign -d --entitlements :- /tmp/ipa-verify/Payload/PhotoCull.app 2>/dev/null
```
Expect the intended build number, the Photos usage string, `get-task-allow` false/absent,
and no entitlements beyond the application identifier and team (the app declares none).
Entitlements read off the `.xcarchive` show development values; always check the exported ipa.
Copy it to `~/Desktop/PhotoCull-<marketing>-build<N>.ipa` and give the user that path.

## 4. Upload — Xcode Organizer
`open build/PhotoCull.xcarchive` → Organizer → Distribute App → App Store Connect → Upload →
defaults. Transporter.app got stuck in an app-specific-password loop (error -22910) in
July 2026 in the Coach JI project; do not spend time on it. Processing takes 5–15 minutes,
then the build appears under TestFlight; add both phones' Apple IDs as internal testers.
Export compliance is pre-answered by `ITSAppUsesNonExemptEncryption = false` in project.yml.

## 5. After it is live
Bump `CURRENT_PROJECT_VERSION` in `project.yml` right away so the next archive cannot reuse
the number. A stale icon on a phone that ran an old dev build is a springboard cache:
delete the app, reboot, reinstall.
