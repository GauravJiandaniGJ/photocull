# PhotoCull — iOS app spec for Claude Code

Personal iPhone photo-culling app. Finds near-duplicate shots of the same moment, picks the best one, flags WhatsApp/screenshot clutter, lets the user review everything, then moves the losers to Recently Deleted in one tap. Built for two phones (iPhone 17 Pro Max, iPhone 15 Pro), distributed via Xcode/TestFlight under a paid Apple Developer account. No server, no iCloud dependency.

Read this whole file before writing code. Sections 3–5 are the core logic and should be built first; the UI in section 6 is deliberately simple.

---

## 1. Goals and non-goals

**Must do (v1)**
- Scan a user-chosen date range (presets: last 3 months, last 6 months, custom).
- Group photos that are near-identical shots of the same moment (bursts, "take five, keep one").
- Pick a keeper per group using on-device signals: face capture quality, eyes open, smile, overall aesthetics.
- Classify clutter: screenshots, images received via WhatsApp (forwards, chat screenshots, documents), photos of documents/receipts.
- Show every proposed decision with a reason; user can override any of them.
- Dry run by default. Nothing is deleted until the user presses Apply on the Apply screen and confirms the iOS system dialog.
- Deletion uses `PHAssetChangeRequest.deleteAssets`, so everything lands in Photos → Recently Deleted (30-day undo).
- Keep an exportable audit log of what was kept and deleted, with reasons.
- Cache analysis results so re-scans only process new or changed assets.
- Optional cloud tie-breaker via the Claude API when two candidates score within a small margin. Off by default.

**Non-goals (v1)**
- Videos, Live Photo motion analysis, iCloud shared albums, Shared Library, Mac app, background/scheduled scans, App Store release.

---

## 2. Constraints and assumptions

- iOS 18.0 minimum (needed for `CalculateImageAestheticsScoresRequest` and the Swift Vision API). Both target phones run iOS 26.
- SwiftUI, Swift 5 language mode with strict-concurrency warnings on (not Swift 6 mode — avoid fighting the compiler).
- All ML is Apple Vision / Core Image on device. Apple Intelligence (Foundation Models framework) is NOT used — it is text-only and cannot look at an image.
- Full Photos access (`.readWrite`). If the user grants Limited access, show a screen explaining full access is required and deep-link to Settings.
- Library scale: expect 2,000–8,000 photos per scan window. Per-photo analysis budget ~200–300 ms → a 5k scan is roughly 15–25 minutes on the 17 Pro Max, longer on the 15 Pro. Show progress; keep the screen awake during a scan; make the scan cancellable and resumable from cache.
- Privacy: photos never leave the device unless the Claude tie-breaker is enabled; then only downscaled JPEGs of the candidates in one group are sent, with no metadata.

---

## 3. Architecture

```
PhotoCull (app target, SwiftUI)
├── Screens: Scan, Groups, Clutter, Apply, Settings, Debug
├── PhotoLibraryService   – PhotoKit fetch, thumbnails, album lookup, EXIF probe, delete
├── AnalysisService       – runs FeatureExtractor per asset with bounded concurrency, writes cache
├── FeatureExtractor      – Vision + Core Image calls → AssetMetrics
├── ClaudeTieBreaker      – optional HTTP client to api.anthropic.com
└── Persistence (SwiftData): AssetRecord, ScanSession, PhotoGroup, Decision, AuditEntry

PhotoCullCore (local Swift package, pure Swift, no UIKit/Vision imports)
├── Classifier            – AssetMetrics → Category (+ reason)
├── Grouper               – time bucketing + similarity clustering (union-find)
├── Scorer                – per-asset score, keeper pick, tie detection
└── Thresholds            – all tunables in one Codable struct
```

`PhotoCullCore` must be unit-testable with synthetic metrics (no device needed). Everything that touches Vision or PhotoKit lives in the app target behind protocols so Core stays pure.

Data flow for one scan:

```
date range → fetch PHAssets (sorted by creationDate)
  → for each asset not in cache: load 1024px image → FeatureExtractor → AssetMetrics → cache
  → Classifier: personal | screenshot | receivedPhoto | receivedUtility | utility
  → Grouper (personal + receivedPhoto only): time buckets → similarity clusters → PhotoGroups
  → Scorer: score each member, pick keeper, flag ties → (optional) ClaudeTieBreaker
  → Decisions (auto) → user reviews/overrides → Apply → PHAssetChangeRequest.deleteAssets → AuditEntry
```

---

## 4. Feature extraction (per asset)

API names below are the iOS 18 Swift Vision API. If a name does not compile, use the `VN`-prefixed legacy equivalent (`VNGenerateImageFeaturePrintRequest`, `VNDetectFaceCaptureQualityRequest`, etc.) — same semantics.

### 4.1 PhotoKit metadata (cheap, always collected)
- `localIdentifier`, `creationDate`, `modificationDate` (cache invalidation key), `pixelWidth`, `pixelHeight`, `isFavorite`, `location != nil`
- `mediaSubtypes.contains(.photoScreenshot)` → `isScreenshot`
- `burstIdentifier`, `representsBurst` (fetch with `PHFetchOptions.includeAllBurstAssets = true` so all burst frames are considered)
- `PHAssetResource.assetResources(for:).first` → `uniformTypeIdentifier` (`public.heic`, `public.jpeg`, `public.png`), `originalFilename`
- Membership in the WhatsApp album: at scan start, fetch `PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)`, find `localizedTitle == thresholds.whatsAppAlbumName` ("WhatsApp"), fetch its assets into a `Set<String>` of localIdentifiers. Verify the exact album title on the device; make it editable in Settings.
- Fetch predicate: `mediaType == image AND creationDate >= start AND creationDate < end`; only `PHAssetSourceType.typeUserLibrary`; hidden assets excluded (default).

### 4.2 Camera EXIF probe (only for JPEG/PNG assets — HEIC is assumed camera-originated)
- `PHImageManager.requestImageDataAndOrientation` → `CGImageSourceCreateWithData` → `CGImageSourceCopyPropertiesAtIndex(src, 0, nil)`
- `hasCameraExif = (TIFF Make or Model present) OR (Exif dictionary contains LensModel/FNumber)`
- WhatsApp, Telegram, Safari and most apps strip EXIF; camera, AirDrop and DSLR imports keep it. Cache the result; never re-probe unless `modificationDate` changed.

### 4.3 Image for analysis
- `PHCachingImageManager.requestImage(for:targetSize:contentMode:options:)`, long edge = `thresholds.visionLongEdge` (1024), `deliveryMode = .highQualityFormat`, `isNetworkAccessAllowed = true`, `contentMode = .aspectFit`.
- Convert to `CGImage` once; run all Vision requests on it; release immediately (wrap per-asset work in `autoreleasepool`).
- UI thumbnails: separate 256px requests via the same caching manager.

### 4.4 Vision / Core Image requests (one `ImageRequestHandler` per image)
| Signal | Request | Output stored in `AssetMetrics` |
|---|---|---|
| Similarity | `GenerateImageFeaturePrintRequest` | `FeaturePrintObservation` — keep in memory for the scan session only (not persisted); `distance(to:)` gives a Float |
| Aesthetics | `CalculateImageAestheticsScoresRequest` | `aestheticsScore` (−1…1), `isUtility` (true for screenshots, receipts, documents, whiteboards) |
| Faces + quality | `DetectFaceCaptureQualityRequest` | per face: `bbox` (normalized), `captureQuality` (0…1). Faces with area < `thresholds.minFaceAreaRatio` are ignored for eyes/smile |
| Eyes / smile | `CIDetector(ofType: CIDetectorTypeFace, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])` → `features(in:options: [CIDetectorSmile: true, CIDetectorEyeBlink: true])` | per face: `leftEyeOpen = !leftEyeClosed`, `rightEyeOpen`, `smiling = hasSmile`. Match CIDetector faces to Vision faces by bbox IoU > 0.3. Fallback if CIDetector is unavailable: eye-aspect-ratio from `DetectFaceLandmarksRequest` `leftEye`/`rightEye` points (open if EAR > 0.2) |
| Text density | `RecognizeTextRequest` with `recognitionLevel = .fast` | `textCharCount` — sum of top-candidate string lengths. Only run when `isUtility == true` OR no faces OR asset is a received/PNG image (gating keeps scan time down) |

`AssetMetrics` (Codable, lives in Core):
```swift
struct FaceMetrics: Codable { var bbox: CGRect; var captureQuality: Float; var leftEyeOpen: Bool; var rightEyeOpen: Bool; var smiling: Bool }
struct AssetMetrics: Codable {
  var id: String; var creationDate: Date; var pixelCount: Int
  var isScreenshot: Bool; var isFavorite: Bool; var inWhatsAppAlbum: Bool
  var fileUTI: String; var hasCameraExif: Bool?        // nil = not probed (HEIC)
  var burstIdentifier: String?
  var aestheticsScore: Float?; var isUtility: Bool?
  var faces: [FaceMetrics]; var textCharCount: Int?
}
```

---

## 5. Core logic (PhotoCullCore)

### 5.1 Thresholds (single Codable struct, editable in Settings, snapshot stored on each ScanSession)
| Key | Default | Meaning |
|---|---|---|
| `groupTimeGapSeconds` | 120 | New time bucket when gap to previous photo exceeds this |
| `similarityDistanceMax` | 0.6 | Feature-print distance at or below which two photos are "the same shot". Calibrate on day 1 (see 5.3) |
| `tieBreakMargin` | 0.05 | Top-two score gap below which the group is a tie |
| `minFaceAreaRatio` | 0.01 | Ignore faces smaller than 1% of the frame for eyes/smile |
| `textHeavyCharCount` | 80 | Received image with this much text is treated as a forward/chat screenshot |
| `whatsAppAlbumName` | "WhatsApp" | Album title created by WhatsApp's "Save to Camera Roll" |
| `visionLongEdge` | 1024 | Analysis image size |
| `claudeImageLongEdge` | 768 | Size of images sent to the tie-breaker |
| `claudeMaxImagesPerGroup` | 6 | Cap per tie-breaker call |

### 5.2 Classifier (rules in order; first match wins; every result carries a human-readable `reason`)
1. `isFavorite` → `personal`, and the asset is **never** a delete candidate (it can still be a group keeper).
2. `isScreenshot` → `screenshot`. Default: delete. Reason: "Screenshot".
3. `inWhatsAppAlbum` OR (`fileUTI` is jpeg/png AND `hasCameraExif == false`) → received:
   - `isUtility == true` OR `textCharCount >= textHeavyCharCount` → `receivedUtility`. Default: delete. Reason: "Received image with text/document content".
   - else → `receivedPhoto`. Default: keep, but listed in its own review section so relatives' photos can be bulk-kept or bulk-deleted. Reason: "Received photo (no camera data)". These also go through grouping.
4. `isUtility == true` (camera-originated) → `utility`. Default: delete, own review section. Reason: "Photo of document/receipt/whiteboard". Users often keep some of these — never bury them among bursts.
5. else → `personal`.

### 5.3 Grouper (input: `personal` + `receivedPhoto` assets, sorted by creationDate)
1. Any assets sharing a `burstIdentifier` form a group of kind `burst` immediately.
2. Remaining assets: walk in time order; start a new bucket when `creationDate - previous.creationDate > groupTimeGapSeconds`.
3. Within a bucket (typically 2–30 photos), compute pairwise feature-print distances; union-find any pair with `distance <= similarityDistanceMax`. Each component with ≥ 2 members is a group of kind `similar`. Singletons are kept and never shown as groups.
4. Cap a bucket at 60 assets for pairwise work; split larger buckets by time.

Calibration (do this once before trusting the threshold): Apple does not document what a feature-print distance value means, and the scale changes between Vision revisions, so 0.6 is only a starting point. Build a **Debug → Calibrate** view: a histogram of all pairwise distances inside time buckets, a threshold slider, and a live count of groups that would form. The user picks a known burst and checks it groups, then a known "different scene, same minute" pair and checks it does not; the slider value between those becomes `similarityDistanceMax`. A CSV export of `(idA, idB, distance)` is optional, for deeper analysis on a Mac.

### 5.4 Scorer
For each group member:
```
aesthetics = (aestheticsScore + 1) / 2                      // 0…1
faces      = faces with area >= minFaceAreaRatio
faceQ      = faces.isEmpty ? nil : 0.6 * mean(captureQuality) + 0.4 * min(captureQuality)
eyesOpen   = faces.isEmpty ? nil : fraction of faces with both eyes open
smile      = faces.isEmpty ? nil : fraction of faces smiling
resolution = pixelCount == max(pixelCount in group) ? 1 : 0

with faces:    score = 0.40*faceQ + 0.25*aesthetics + 0.20*eyesOpen + 0.10*smile + 0.05*resolution
without faces: score = 0.90*aesthetics + 0.10*resolution
isFavorite:    score += 1.0   (favorites always win)
```
- Keeper = highest score. Tie-break order when `|top1 - top2| < tieBreakMargin`: Claude tie-breaker if enabled, else higher `aesthetics`, else earlier `creationDate`.
- Each non-keeper gets a reason built from the biggest losing term, e.g. "1 face with eyes closed", "lower face quality (0.41 vs 0.78)", "lower overall quality". Keepers get "Best of 5: all eyes open, sharpest faces".
- A group with a user override (`source == .user`) is never re-scored on re-scan.

### 5.5 Claude tie-breaker (optional, off by default)
- Endpoint: `POST https://api.anthropic.com/v1/messages`. Headers: `x-api-key: <key from Keychain>`, `anthropic-version: 2023-06-01`, `content-type: application/json`.
- Model: `claude-sonnet-5` (default). Cheaper option in Settings: `claude-haiku-4-5-20251001`. Verify current model IDs and the image content-block format at https://docs.claude.com/en/docs/build-with-claude/vision before wiring it up.
- Body: one user message whose `content` is N image blocks (`{"type":"image","source":{"type":"base64","media_type":"image/jpeg","data":"…"}}`, each ≤ 768px long edge, JPEG q≈0.7, numbered in the accompanying text as Photo 1…N) followed by a text block:
  > These are N near-identical photos of the same moment. Choose the single best one to keep, judged by: everyone's eyes open, looking at the camera or naturally engaged, natural expression, sharp faces, then overall composition. Respond with JSON only: {"winner": <1-based index>, "reason": "<one sentence>", "confidence": <0-1>}
- `max_tokens: 200`. Parse JSON from `content[0].text` (strip code fences if present). On any error or `confidence < 0.5`, fall back to the local tie-break and record `claudeError` on the group.
- Store `claudeReason` on the group and show it in the review UI. Never send favorites, never send more than `claudeMaxImagesPerGroup` images, never send metadata or filenames.
- Key entry: `SecureField` in Settings, stored with the Keychain Services API; never in UserDefaults, never in source.

---

## 6. Screens (SwiftUI, TabView: Scan · Groups · Clutter · Apply · Settings)

**Scan** — date range presets (3 months / 6 months / custom), asset count for the range, toggles (include WhatsApp album, include screenshots, use Claude tie-breaker), Scan button. Progress view with stage + counts ("Analysing 1,240 / 4,310", "Grouping…"), cancel, and elapsed time. On completion show a summary card: groups found, photos in groups, keepers, clutter by category, total delete candidates.

**Groups** — list of `PhotoGroup`s, newest first. Each row: horizontal strip of thumbnails; keeper has a green border and "Keep" badge; others are dimmed with a red "Delete" badge and a one-line reason. Tapping a row opens the group: full-width pager to compare photos at 1024px, score breakdown and face indicators (eyes open/closed, smile) per photo, tie-breaker reason if present. Actions: tap a photo → "Make keeper"; long-press → toggle keep/delete; "Keep all"; "Delete all but keeper". Filter chips: All · Ties · Overridden · Bursts.

**Clutter** — grouped sections: Screenshots · Received (text/documents) · Received photos · Documents/receipts. Grid with checkmarks; per-section "Select all / Deselect all"; tap for full view with reason. Counts in section headers.

**Apply** — read-only summary: N to delete (by category + from groups), M kept, favorites protected count. Button "Move N photos to Recently Deleted". Flow: in-app confirmation sheet → single `PHPhotoLibrary.performChanges { PHAssetChangeRequest.deleteAssets(assets) }` (one call, so iOS shows one confirmation dialog) → success screen with "Undo within 30 days: Photos → Albums → Recently Deleted" → audit entry written → "Export log" ShareLink (JSON + CSV). Apply is disabled until at least one review tab has been opened in this session.

**Settings** — thresholds (each with default and reset), WhatsApp album name, Claude toggle/model/key, "Clear analysis cache", scan history (past sessions with counts and export), Debug entry point.

**Debug** (hidden behind a long-press on the version label) — per-asset raw metrics table, Calibrate view (distance histogram + threshold slider with live group count, see 5.3), optional CSV export of metrics and distances, timing stats per Vision request.

Design: system fonts, SF Symbols, dark-mode aware, large tap targets — this is a couple's utility, not a product. No onboarding beyond the permission screen.

---

## 7. Persistence (SwiftData)

```swift
@Model final class AssetRecord {          // analysis cache, survives sessions
  @Attribute(.unique) var localIdentifier: String
  var modificationDate: Date?             // recompute if PHAsset.modificationDate differs
  var metricsJSON: Data                   // AssetMetrics
  var category: String; var categoryReason: String
  var analyzedAt: Date
}
@Model final class ScanSession { var id: UUID; var startDate: Date; var endDate: Date; var createdAt: Date; var status: String; var thresholdsJSON: Data; var groups: [PhotoGroup]; var decisions: [Decision] }
@Model final class PhotoGroup  { var id: UUID; var kind: String /* burst | similar */; var memberIDs: [String]; var keeperID: String; var scoresJSON: Data; var isTie: Bool; var claudeReason: String?; var claudeError: String? }
@Model final class Decision    { var id: UUID; var assetID: String; var action: String /* keep | delete */; var source: String /* auto | user | claude */; var reason: String; var groupID: UUID?; var category: String }
@Model final class AuditEntry  { var id: UUID; var sessionID: UUID; var appliedAt: Date; var deletedIDs: [String]; var keptIDs: [String]; var summaryJSON: Data }
```
Feature prints are held in memory for the duration of a scan only. Everything else scalar is cached, so a 6-month scan after a 3-month pilot only analyses the extra 3 months.

---

## 8. Safety rules (non-negotiable)

1. The only code path that calls `deleteAssets` is the Apply screen's confirmed action. No deletes during scan, review, or on background events.
2. Favorites are never delete candidates, even if the user toggles a group to "delete all".
3. Only assets with a `Decision(action: delete)` in the **current** session are passed to `deleteAssets`; re-fetch them by `localIdentifier` immediately before deletion and skip any that no longer exist or whose `modificationDate` changed since analysis.
4. A group of size 1 is never created; a group never has zero keepers.
5. Every delete decision has a non-empty reason string visible in the UI and in the audit log.
6. Scan is idempotent: running it twice on the same range with no library changes produces identical groups and decisions, except where the user overrode.
7. The Claude client is dormant unless the toggle is on and a key exists; a failed call never changes a decision to delete.

---

## 9. Project setup

- Xcode 16+ (Xcode 26 is fine). Deployment target iOS 18.0. Bundle ID `com.<her-team-name>.photocull`, Team = wife's Apple Developer team, automatic signing.
- Generate the project with XcodeGen (`brew install xcodegen`) from a `project.yml` at the repo root so it can be regenerated from the CLI; targets: `PhotoCull` (app), `PhotoCullCoreTests`, plus the local package `Packages/PhotoCullCore`.
- Info.plist: `NSPhotoLibraryUsageDescription` = "PhotoCull analyses your photos on this phone to find near-duplicates and clutter, and deletes only what you approve." No background modes, no other entitlements.
- Build check: `xcodebuild -scheme PhotoCull -destination 'generic/platform=iOS' -allowProvisioningUpdates build`. Core tests: `xcodebuild test -scheme PhotoCullCore -destination 'platform=iOS Simulator,name=iPhone 16'`.
- Vision requests (especially aesthetics and face capture quality) should be validated on a real device; the simulator is only for Core tests and UI layout.
- Concurrency: analyse assets in a `TaskGroup` with at most 3 in flight; Vision and CIDetector calls are synchronous inside a detached task; all SwiftData writes go through a single `@ModelActor`.
- Keep the screen awake during a scan (`UIApplication.shared.isIdleTimerDisabled = true`; reset on finish/cancel).

Repo layout:
```
PhotoCull/
  project.yml
  PhotoCull/            App, Screens/, Services/, Vision/, Persistence/, Resources/
  Packages/PhotoCullCore/
    Sources/PhotoCullCore/   Thresholds.swift, AssetMetrics.swift, Classifier.swift, Grouper.swift, Scorer.swift
    Tests/PhotoCullCoreTests/
  PHOTOCULL_SPEC.md     (this file)
```

---

## 10. Tests (PhotoCullCore, no device required)

- Classifier: one test per rule in 5.2, plus "favorite is never a delete candidate", plus "HEIC with `hasCameraExif == nil` is personal".
- Grouper: time bucketing at the boundary (119 s vs 121 s), union-find transitivity (A~B, B~C, A≁C → one group of 3), burst grouping wins over time bucketing, 60-asset bucket cap.
- Scorer: closed eyes loses to open eyes with equal quality; favorite wins with lower score; tie detection at exactly the margin; reason strings are non-empty; no-face group uses the aesthetics-only formula.
- Idempotence: same metrics in, same decisions out.
- ClaudeTieBreaker: JSON parsing with and without code fences; malformed response falls back locally.

---

## 11. Milestones (each ends with a build installed on the primary phone)

1. **Fetch + metrics + Calibrate** — permission flow, date-range fetch, FeatureExtractor, cache, Debug → Calibrate view. Acceptance: last 3 months analysed; `similarityDistanceMax` set with the slider so a known burst groups and a known different-scene pair does not.
2. **Grouping + scoring + Groups screen** — Core package with tests green; Groups review with overrides. Acceptance: on a real burst, the keeper matches the human pick most of the time and every loser shows a sensible reason.
3. **Clutter** — Classifier + Clutter screen + WhatsApp album detection + EXIF probe. Acceptance: screenshots and WhatsApp forwards from the last 3 months are correctly separated from relatives' photos.
4. **Apply + audit** — Apply screen, single-call delete, audit log + export, scan history. Acceptance: a 3-month dry run reviewed end to end, then applied; items visible in Recently Deleted; log exported.
5. **Claude tie-breaker** — Settings, Keychain, client, reason display. Acceptance: ties resolved with a shown reason; toggle off → zero network calls (verify with Instruments or a proxy).
6. **Second phone** — install on the 15 Pro, run a 3-month scan, then a 6-month scan on both. Fix anything performance-related before calling v1 done.

---

## 12. Open decisions for the owner (ask before assuming)

- Exact WhatsApp album title on both phones.
- Whether "Received photos" from relatives should default to keep (spec says yes).
- Whether to ship the Claude tie-breaker in the first install or add it in milestone 5 only.
- Whether documents/receipts ("utility") should default to delete or to keep-and-flag.
