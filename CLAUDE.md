# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What it is

Personal iOS photo-culling app for two phones (iPhone 17 Pro Max primary, iPhone 15 Pro). Scans a date range, groups near-duplicate shots, picks a keeper per group with on-device Vision signals, flags screenshots and WhatsApp/document clutter, lets the user review every decision, then moves losers to Recently Deleted in one tap. No server, no iCloud. Optional Claude API tie-breaker, off by default.

`PHOTOCULL_SPEC.md` is the source of truth; section numbers below refer to it. Section 12 lists owner decisions to ask about, not assume (exact WhatsApp album title, defaults for received photos and documents, when to ship the tie-breaker). `photocull-technical-flow.mermaid` and `photocull-user-flow.mermaid` are the pipeline and user-journey diagrams.

## Current state

Milestones 1–5 and 7 (§11 + videos) are built; build 4 is installed on both phones (17 Pro Max on iOS 27.0, 15 Pro on iOS 26.6). Milestone 6 remaining: 6-month scans on both and any performance fixes.

- `Packages/PhotoCullCore` is complete against §5: Thresholds, AssetMetrics, Classifier, Grouper, Scorer, Planner, TieBreakVerdict, with 55 passing tests covering §10.
- Milestone 1 in the app target: `VisionFeatureExtractor` (feature print, aesthetics, face capture quality, CIDetector eyes/smile, EXIF probe, gated OCR), `ScanController` (fetch → cache lookup → 3-wide TaskGroup → Planner → SwiftData session), scan progress and summary on the Scan tab, Debug → raw metrics table, Calibrate histogram with threshold slider and group preview, CSV export, per-request timings.
- Milestones 2–3: `GroupsView` (filters, strips, keeper/delete badges) → `GroupDetailView` (pager, score breakdown, Make keeper, toggle, Keep all, Delete all but keeper); `ClutterView` sectioned grid with Select/Deselect all and a detail sheet. All overrides go through `Review` (Services/Review.swift) and are marked `source = user`; `PersistenceActor.saveSession` carries user decisions and user-chosen keepers into the next scan.
- Milestone 4: `ApplyController.apply` is the single `deleteAssets` call site; it re-fetches candidates, skips missing/changed/favorited assets, writes an `AuditEntry`, marks the session `applied`. `AuditDetailView` + `AuditExport` produce the JSON/CSV log (from Apply and from Settings → scan history). Apply is gated on `Journey.canApply`.
- Journey: `ScanSession` carries `groupsVisitedAt/groupsReviewedAt/clutterVisitedAt/clutterReviewedAt`; `Journey` derives the current step, `JourneyCard` (top of Scan) shows progress with Continue, `NextStepBar` on Groups/Clutter marks a step reviewed and switches tabs via `AppNavigation`. Apply's gate is `Journey.canApply` (persisted), so leaving the app for days keeps the place.
- Activity log: `AppLog.info/warning/error(category, message)` writes `LogEntry` rows (pruned to 3000 at launch); Settings → Activity log lists, filters, exports, clears. Log at every user-visible action; never log the API key.
- App icon is generated: `swift scripts/make-icon.swift PhotoCull/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (no alpha, as App Store Connect requires).
- Also in place: Photos permission gate, five-tab shell, SwiftData models (§7), Settings (thresholds, Keychain-backed Claude key, cache clear, scan history).
- Milestone 5: the tie-breaker is a post-scan, user-confirmed action, not part of the scan. `ClaudeSettings` (toggle, model, key presence) → `TieBreakButton` (renders only when `isAvailable`, shows a confirmation with photo count and estimated cost) → `TieBreakRunner.run` → `ClaudeTieBreaker.resolve` (the only `URLSession` use in the app). Candidates = `Scorer.tieCandidates` minus favorites, capped by `claudeMaxImagesPerGroup`; a verdict can only move the keeper within the tie; errors land on `PhotoGroup.claudeError`. Settings has "Test connection" (GET /v1/models/{id}, no tokens). Model ids: `claude-sonnet-5`, `claude-haiku-4-5`.
- Milestone 7 (videos): `VideoMetrics`/`VideoClassifier`/`VideoGrouper`/`VideoScorer`/`VideoPlanner` in Core (exact duplicates by duration+size+dimensions across any time, then same-take similarity inside time buckets using mean sampled-frame distance gated by duration). `VideoFeatureExtractor` samples frames at 10/50/90 % with `AVAssetImageGenerator`, reads make/model metadata, flags screen recordings by exact iPhone screen dimensions, and never downloads from iCloud (`isNetworkAccessAllowed = false`; non-local videos get size 0 and no frames). `ScanController` runs photos then videos and saves `[PlanBundle]`; `PhotoGroup`/`Decision`/`AssetRecord` carry `mediaType`, decisions carry `fileSize`/`duration`. Clutter shows Screen recordings, Received videos and Videos-largest-first with sizes; group detail plays via `VideoPlayerSheet`.
- Remaining from milestone 6: 6-month scans on both phones and any performance fixes.
- Public repo (MIT): `README.md` is the front door, `docs/ARTICLE.md` is the Medium story (short, non-technical first; three phone screenshots `phone-groups/phone-group-detail/phone-clutter.png` are supplied by the owner), `docs/DEEP-DIVE.md` the technical write-up and `docs/images/` holds its figures (rendered from HTML/mermaid sources kept out of the repo; phone screenshots are cropped above any photo thumbnails). Keep phone names and UDIDs out of committed files.

## Commands

```sh
xcodegen generate                          # regenerate PhotoCull.xcodeproj (git-ignored) from project.yml

# Core tests: pure Swift, run on the Mac in seconds — the default way to test
cd Packages/PhotoCullCore && swift test
cd Packages/PhotoCullCore && swift test --filter GrouperTests                       # one class
cd Packages/PhotoCullCore && swift test --filter ScorerTests/testFavoriteWinsWithLowerScore  # one test

# App build for the simulator (no signing needed; simulator names here are the iPhone 17 family)
xcodebuild -project PhotoCull.xcodeproj -scheme PhotoCull \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData build

# Do not run the Core tests through xcodebuild: on Xcode 26.6 here the simulator test runner
# times out "while preparing to run tests" (twice, warm simulator). `swift test` is the route.

# Install and launch on a connected iPhone (the real dev loop — Vision must be judged on hardware)
scripts/deploy-phone.sh                    # auto-detects the one connected iPhone; --list shows UDIDs
```

Skills in `.claude/skills/`: `phone-deploy` (device loop, pairing, signing), `sim-qa` (simulator limits, `-skipPhotosGate` launch argument, screenshots), `testflight-build` (archive → export → Organizer upload). `.mcp.json` registers XcodeBuildMCP for simulator/device/package workflows.

Toolchain: Xcode 26.6, XcodeGen via Homebrew. Swift 5 language mode with strict-concurrency warnings on, not Swift 6 mode. Deployment target iOS 18.0.

## Architecture

Two layers with a hard boundary:

- **`Packages/PhotoCullCore`**: pure Swift (Foundation + CoreGraphics for `CGRect` only). No UIKit, Vision, PhotoKit or SwiftData. Everything is unit-tested with synthetic metrics; `Tests/PhotoCullCoreTests/Fixtures.swift` has the `asset(...)`, `face(...)` and `distances(...)` helpers.
- **`PhotoCull`** app target (SwiftUI): everything that touches the device. `Services/` (PhotoKit, thresholds store, Keychain), `Vision/` (feature extraction), `Persistence/Models.swift` (SwiftData), `Screens/`, `App/`.

Core API the app drives: `Planner(thresholds:).plan(metrics:distance:)` runs classify → group → score → decide and returns a `ScanPlan` (classifications, `[ScoredGroup]`, one `ProposedDecision` per asset). `Grouper` never sees feature prints; it takes a `(id, id) -> Float?` distance closure that the app's extractor answers from its in-memory prints. `Scorer.replacingKeeper(in:with:keeperReason:)` is how a Claude or user override re-derives reasons. `TieBreakVerdict.parse(_:candidateCount:)` parses the model's JSON, fences and prose tolerated.

Names: Core uses `AssetCategory` and `CullAction` (not `Category`/`Action`, which collide with system types in the app target). SwiftData models store their raw values as `String`.

Things that are easy to get wrong across files:

- Feature prints live in memory for one scan only (`VisionFeatureExtractor`). Everything scalar is cached in `AssetRecord.metricsJSON` keyed by `localIdentifier` and invalidated by `modificationDate`. A cached groupable asset still gets a `featurePrintOnly` pass on re-scan so it can be grouped; clutter is reused without touching the image.
- `ScanController.Calibration` (candidates, every compared pair's distance, metrics) is what the Calibrate view reads; it exists only after a scan in the current app session.
- Vision coordinates: the extractor redraws the image upright once, so Vision `NormalizedRect.cgRect` and CIDetector bounds (normalised by image size) share a bottom-left origin and can be matched by IoU.
- `similarityDistanceMax`: the spec default 0.6 over-groups badly on iOS 26 Vision (81% of same-bucket pairs fell under it). Calibrated on the 17 Pro Max on 2026-09-05 to **0.05**, which keeps only near-identical frames, and that is now the app default (`Thresholds.default`); a phone that had already stored 0.6 keeps it until Settings → Reset or a manual edit. Re-calibrate with Debug → Calibrate after any iOS/Vision update.
- `Thresholds` is one Codable struct; `ThresholdsStore` persists it, and each scan snapshots it onto `ScanSession.thresholdsJSON`. Decoding tolerates missing keys, so adding a threshold never breaks stored sessions.
- Tie detection is strict: a top-two gap exactly equal to `tieBreakMargin` is not a tie. Local tie-break order is higher aesthetics, then earlier creation date.
- Grouper output is deterministic regardless of input order; a bucket is capped at 60 assets and split by time. Singletons are never groups.
- All SwiftData writes go through one `@ModelActor`; analysis runs in a `TaskGroup` with at most 3 in flight; Vision and CIDetector calls are synchronous inside detached tasks, wrapped in `autoreleasepool` (§9).
- If an iOS 18 Swift Vision request name does not compile, use the `VN`-prefixed legacy request with the same semantics (§4).

## Signing and devices

- Team `D4U39723T4` (the paid team), bundle id `com.vandnajiandani.photocull`, automatic signing. Both live in `project.yml`; change them there, not in the generated project.
- Both target phones are paired and registered; `scripts/deploy-phone.sh --list` prints their UDIDs. With both connected, pass `DEVICE_UDID` to the script; the phones run different iOS versions, so calibrate each separately.
- `CURRENT_PROJECT_VERSION` in `project.yml` must be bumped before every TestFlight upload.

## Safety rules (§8, non-negotiable)

- `PHAssetChangeRequest.deleteAssets` is called from exactly one place: `ApplyController.apply`, reached only from the Apply screen's confirmed action, as a single `performChanges` call. `grep -rn deleteAssets PhotoCull` must return that one line.
- Favorites are never delete candidates, regardless of group overrides. `Classification.isProtected` carries this; `Planner` already keeps a favorite that loses inside a group.
- Only assets with a delete `Decision` in the current session are deleted; re-fetch by `localIdentifier` right before deletion and skip anything missing or modified since analysis.
- Groups never have size 1 and never have zero keepers (`ProposedGroup` preconditions this).
- Decisions with `source == user` are never re-scored on a later scan.
- The Claude client makes zero network calls unless the toggle is on, a key exists in Keychain, and the user confirmed the specific batch in the dialog; a failed or low-confidence call never flips a decision to delete. `grep -rn URLSession PhotoCull` must only hit `ClaudeTieBreaker.swift`.
