# Stop Paying $12 a Week to Delete Your Own Photos

*Every week your iPhone fills up with bursts, WhatsApp forwards and screenshots you will never open again. I built a free app that runs on the phone, groups the near-duplicates, picks the best shot by face quality and open eyes, and shows a reason next to every deletion. Here is how it works, and the one number Apple never documents.*

---

Open your camera roll and scroll back seven days. Mine looks like this every single week: eleven nearly identical photos of the baby on the play mat, taken in a burst because one of them had to have open eyes. Nine forwards from the family WhatsApp group, good-morning images and a poster for someone's event. Six screenshots of a delivery status, a payment confirmation, a tweet. A photo of a receipt I needed for exactly one day.

Nobody looks at those again. They also never leave. Three months of this added up to 993 photos on my phone, and the ones I actually wanted, the twenty or so that would go in an album, were buried in the rest.

## The apps that promise to fix this

I tried the App Store first. The top "cleaner" apps have hundreds of thousands of reviews and a business model built on the fact that you are annoyed right now: Cleanup charges between $5.95 and $11.99 **per week**, Clever Cleaner $6.99 a week, Smart Cleaner up to $9.99 a week. The free tiers let you delete five photos a day. The swipe apps show you an ad every fifth swipe.

The bigger problem is not the price. It is that none of them tell you how they decide. Every one of them has a "Best" badge on one photo in a group, and not one of them documents what "best" means. The one-star reviews are the same story over and over: "similar" turned out to mean "same room", and years of photos went in one tap.

Apple's own Duplicates album only finds exact copies, needs the phone locked and charging for days, and does nothing about bursts, forwards or screenshots. Google Photos has similar-photo cleanup, but on iPhone it unlocks only once you have run out of storage.

So I built the thing I wanted: an app that runs entirely on the phone, sends nothing anywhere, and puts a one-line reason next to every photo it wants to remove. It is free and open source: **[github.com/GauravJiandaniGJ/photocull](https://github.com/GauravJiandaniGJ/photocull)**.

## What a week looks like now

Scan the last three months, or a custom range. The app groups bursts and re-takes, picks a keeper for each group, and sorts the clutter into sections: screenshots, received text and documents, received photos, receipts and whiteboards, screen recordings, and your largest videos. Then it stops and waits.

![User flow](images/user-flow.png)

You review the groups: the keeper is marked, every other photo has its reason, and one tap makes a different photo the keeper or keeps the whole group. You review the clutter with Select all per section. You press Apply once. iOS shows its own confirmation, and the photos move to Recently Deleted, where you have 30 days to change your mind.

The second scan only analyses photos it has not seen before, so a weekly pass takes a couple of minutes: scan on Sunday, glance at ten new groups, tick the screenshots, Apply. The journey card on the first tab remembers where you stopped, so if you review the groups on Tuesday and the clutter the following weekend, nothing is lost in between.

The reasons are the part I care about most. "Lower face quality (0.61 vs 0.84)". "1 face with eyes closed". "Screenshot". "Received image with text/document content". "Near-identical; keeper was taken first". Every one of them is written from the same numbers the app used to decide, and every override you make is stored as your decision and never re-scored.

## What is inside

![Six stages, two layers](images/stages.png)

The app has one hard boundary. Everything that touches the phone, PhotoKit, Vision, Core Image, SwiftData, the UI, lives in the app target. Everything that *decides* lives in a pure-Swift package with no device imports and 70 unit tests that run on a Mac in seconds with synthetic data.

The whole decision pipeline is one call:

```swift
let plan = Planner(thresholds: thresholds).plan(
    metrics: metrics,                                 // one AssetMetrics per photo
    distance: { a, b in extractor.distance(a, b) }    // feature-print distance, or nil
)
// plan.classifications, plan.groups (each with a keeper and reasons), plan.decisions
```

The grouper never sees an image or a feature vector. It asks a closure for the distance between two ids and the app answers from prints it holds in memory for one scan. That is what makes the grouping logic testable with fake distances, and it keeps 2,000-float vectors out of the database.

## What Apple gives you for free

Per photo, the analysis is four Vision requests, one Core Image detector and an EXIF probe. All of it ships in iOS 18 and later. No model downloads, no server, no per-photo cost.

```swift
let handler = ImageRequestHandler(cgImage)

let print      = try await handler.perform(GenerateImageFeaturePrintRequest())
let aesthetics = try await handler.perform(CalculateImageAestheticsScoresRequest())
let faces      = try await handler.perform(DetectFaceCaptureQualityRequest())

var text = RecognizeTextRequest()
text.recognitionLevel = .fast
let lines = try await handler.perform(text)      // only when it can change a decision
```

- **`GenerateImageFeaturePrintRequest`** returns a vector you compare with `distance(to:)`. Two shots of the same moment are close, two scenes are far. What "close" means numerically is the subject of the next section.
- **`CalculateImageAestheticsScoresRequest`** returns an overall score and an `isUtility` flag. The flag is the useful part: it fires on receipts, documents, whiteboards and memes, which is most of what I wanted gone.
- **`DetectFaceCaptureQualityRequest`** scores each face for how good a photo of that face it is. It is the single strongest input to the keeper choice.
- **`CIDetector`** with `CIDetectorEyeBlink` and `CIDetectorSmile` says whether each eye is open and whether the person is smiling. Vision has no eye-state request, so the app runs both and matches faces by bounding-box overlap. One redraw of the image upright puts both APIs in the same coordinate system.
- **EXIF** says where a JPEG came from. WhatsApp strips the camera make and model when it re-encodes an image, so "JPEG or PNG with no camera EXIF" is a reliable received-photo signal even when the WhatsApp album is missing. HEIC is assumed to be from the camera, because WhatsApp never delivers HEIC.

Here is what that costs on an iPhone 17 Pro Max, averaged over the 993-photo scan:

![Timing per request](images/timing.png)

![The Debug screen on the phone, timings per request](images/debug-timings.png)

Decoding and resizing to 1,024 pixels is the expensive step. The Vision requests are cheap: feature print 6 ms, aesthetics 4 ms. OCR runs only when it can change a decision, which is why it ran on 340 photos rather than 993. Three photos are analysed at a time and everything scalar is cached per asset, keyed by identifier and modification date.

## The threshold nobody documents

Grouping is simple on paper. Photos with the same burst identifier are a burst. Everything else is sorted by time and split into buckets wherever the gap exceeds 120 seconds. Inside a bucket, every pair is compared by feature-print distance, pairs under the threshold are joined, and singletons are never groups.

The first version of the spec said the threshold was 0.6. That number floats around older write-ups of the feature-print API. Apple does not document the scale of the distance at all, and it has changed between API generations.

On iOS 26, 0.6 was a disaster. Of 3,761 compared pairs, 3,053 fell under it. Whole afternoons collapsed into single groups. The preview showed a baby on a mat next to a baby on a bed next to a birthday cake, all "duplicates". This is exactly the failure the one-star reviews describe, and now I knew how easy it was to ship.

![0.60 versus 0.05 on the same library](images/calibrate-060-vs-005.png)

The fix was not a better number from a better blog post. It was a screen. The Calibrate view draws a histogram of every compared pair's distance, puts a slider on it, and shows the groups that would form at that value, newest first. Drag, look, drag again. On my library the histogram had a tall spike near zero and a long flat tail, and 0.05 was the value that kept the spike and dropped the tail: 127 pairs, 84 groups, 193 photos, every one of them a burst or a re-take of the same frame.

![Calibration summary](images/calibration.png)

The lesson generalises past this app. A similarity threshold copied from anywhere is a hypothesis about someone else's phone, someone else's iOS version and someone else's photos. Build the instrument first, then read the number off it. The histogram stays behind a debug menu so I can re-check after every iOS update.

## How the keeper is chosen

Inside a group, each photo gets a score from the signals above.

![How the keeper is chosen](images/scoring.png)

Face quality is a blend of the mean and the worst face in the frame, so a group photo where one person blinked loses to the one where everyone is sharp. With no faces in the group, aesthetics takes 90 percent of the weight and resolution the rest. A favorite gets a bonus of 1.0 and simply wins.

If the top two are within 0.05 of each other, it is a tie. The local rule is higher aesthetics, then the earlier shot. The scorer then looks at which term cost the loser the most and writes that down as the reason. The group detail screen shows the full breakdown per photo, so when the app is wrong you can see why and fix it in one tap.

## The rules that keep it safe

Deleting photos is the one thing this app must never get wrong, so the rules are enforced by structure, not by care.

![Safety rules](images/safety.png)

Two of them are literally greps that must return one line each:

```sh
grep -rn deleteAssets PhotoCull    # exactly one call site: ApplyController.apply
grep -rn URLSession PhotoCull      # exactly one file: the optional tie-breaker client
```

Apply re-fetches every candidate by identifier right before the call and skips anything missing, modified since analysis, or favorited in the meantime. Then it makes a single `performChanges` call, iOS shows its own dialog, and the photos land in Recently Deleted. An audit entry records what moved and why, exportable as JSON or CSV.

## An optional second opinion

Sometimes two photos really are equally good. The app can send a tied pair to Claude and ask which one to keep, with a reason. Three things had to be true before I was comfortable shipping that:

1. It is off by default, and the button does not appear unless the toggle is on **and** you have stored your own API key.
2. Before any call you see the number of photos and an estimated cost, and you confirm that batch.
3. The answer can only move the keeper *inside the tie*. A failed call or a low-confidence answer changes nothing.

![Settings: thresholds, the API key, activity log, cache and scan history](images/settings.png)

Images go as 768-pixel JPEGs, at most six per group, so a two-photo tie costs well under a cent. In practice the local scoring was right often enough that I have barely used it.

## Videos too

Videos get the same treatment with different signals. Exact duplicates are found by duration, file size and dimensions across any time span. Same-take similarity samples three frames at 10, 50 and 90 percent and compares their feature prints inside a time bucket. Screen recordings are recognised by exact iPhone screen dimensions. The app never downloads a video from iCloud to analyse it; a non-local video gets no frames and shows up only in the largest-first list, with its size.

## What I would tell you to build first

The app is about 5,500 lines of Swift. The parts that made it work were not the parts I expected.

- **The spec before the code.** One document with the pipeline, every threshold, the safety rules, the data model, and a list of decisions that had to be made by a person rather than assumed: the WhatsApp album title, what to do with received photos, whether the second opinion ships at all.
- **Instruments before answers.** The calibration histogram, the per-request timings, the raw metrics table and a CSV export existed before the review screens did. They turned "0.6 feels wrong" into "0.05, and here is why".
- **Two loops.** The decision logic has a fast loop: pure Swift, 70 tests, seconds on the Mac. Vision quality has a slow one: a script that builds, installs and launches on the phone, because the simulator on Xcode 26.6 cannot run the Vision requests at all.
- **Reasons as a feature, not a log line.** Writing a reason for every decision forced the scoring to be explainable, and explainable scoring is what makes wrong decisions cheap to catch.

## Where it sits

![Market comparison](images/market.png)

I do not think this is a business. The category belongs to apps with ad budgets and 700,000 reviews. What it is: a photo cleaner that shows its work, costs nothing, sends nothing anywhere, treats a photo of your child differently from a photo of a wall, and can be read end to end in an afternoon.

Missing, if you want to pick it up: blur detection, video and Live Photo compression, a swipe mode for people who prefer deciding by hand, and an App Store build.

## Try it

Clone the repo, change the team and bundle id in `project.yml`, run `xcodegen generate`, deploy to your phone. Then, before you trust a single group, open Settings, long-press the version number, and calibrate. Your number will not be my number. That is the point.

**[github.com/GauravJiandaniGJ/photocull](https://github.com/GauravJiandaniGJ/photocull)**, MIT.
