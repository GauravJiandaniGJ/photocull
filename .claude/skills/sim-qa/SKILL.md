---
name: sim-qa
description: Build and run PhotoCull in the iOS Simulator and run PhotoCullCore tests from the CLI or via XcodeBuildMCP — what the simulator is good for (tests, layout, permission flow) and what it is not (Vision quality, performance). Use when testing without a phone, checking a screen's layout, or when the user asks for a simulator screenshot.
---

# Simulator QA

## 0. What the simulator can and cannot tell you
- Good for: PhotoCullCore tests, SwiftUI layout in light/dark mode, the Photos permission
  flow, SwiftData persistence, navigation.
- Not trustworthy for: aesthetics scores, face capture quality, feature-print distances,
  scan timing. Vision requests run but the numbers differ from hardware; judge those with
  `phone-deploy`. The simulator library also lacks bursts, HEIC and WhatsApp albums.
- On this Mac (Xcode 26.6, iOS 26.5 simruntime, arm64 build) every Vision request fails with
  `Failed to create espresso context`, so a scan analyses 0 photos. Pinning requests to the
  CPU compute device does not help. Scan results, Groups and Clutter screenshots need a phone.

## 1. Tests without a simulator
```bash
cd Packages/PhotoCullCore && swift test                      # whole package, seconds
cd Packages/PhotoCullCore && swift test --filter GrouperTests # one class
```
Do not use `xcodebuild test` for these: with Xcode 26.6 on this Mac the simulator test runner
fails with "The test runner timed out while preparing to run tests" (both the `PhotoCull`
scheme with the package test target and a warm simulator), and the auto-created
`PhotoCullCore` scheme has no test action. `swift test` covers everything in Core.

## 2. Build and run the app
Simulator names on this Mac are the iPhone 17 family (there is no "iPhone 16"); list with
`xcrun simctl list devices available`.
```bash
xcodegen generate
xcodebuild -project PhotoCull.xcodeproj -scheme PhotoCull \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData build
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/PhotoCull.app
xcrun simctl launch booted com.vandnajiandani.photocull
xcrun simctl io booted screenshot /tmp/photocull.png
```
Seed test photos: `xcrun simctl addmedia booted <files…>` (JPEG/PNG/HEIC). Reset Photos
permission between runs: `xcrun simctl privacy booted reset photos com.vandnajiandani.photocull`.

**Permission gate on the simulator:** `simctl privacy grant photos …` writes the TCC row but
PhotoKit still reports `.notDetermined` (seen on iOS 26 sims), so the app stays on the access
screen and nothing can tap "Allow" from the CLI. Debug builds accept a launch argument that
shows the tab shell anyway:
```bash
xcrun simctl launch booted com.vandnajiandani.photocull -skipPhotosGate
```
It only bypasses the gate view; PhotoKit fetches still return nothing until access is real.
Tapping the button by hand in Simulator.app is the honest path when the flow itself is under test.

Expected non-bugs: a burst of `CoreData: error: Failed to stat path …/default.store` lines on the
very first launch is SwiftData creating the store; the file exists afterwards and the app runs.

## 3. XcodeBuildMCP (optional)
`.mcp.json` registers `XcodeBuildMCP` (build / boot / install / launch / screenshot / logs)
and Apple's `xcrun mcpbridge` (needs Xcode.app running). `.xcodebuildmcp/config.yaml`
enables the `simulator`, `device` and `swift-package` workflows. If the `mcp__…` tools are
missing, the session started before `.mcp.json` existed — restart or approve via `/mcp`.
UI-automation (tap/type) tools are not enabled: on Xcode 26.6 the bundled AXe helper failed
with an arm64e SimulatorKit error in the Coach JI project; drive the app by hand or via
screenshots, and only retry `ui-automation` on a newer `xcodebuildmcp` release.

## 4. Evidence
Screenshots named by screen and state; light and dark where layout changed. Say which
simulator and which build produced them.
