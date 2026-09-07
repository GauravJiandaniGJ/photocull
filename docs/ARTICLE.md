# Stop Paying $12 a Week to Delete Your Own Photos

*Every Sunday my iPhone had a hundred new photos I would never open again. Now an app I built picks the keepers, explains itself, and asks before it touches anything.*

![The Groups tab after a scan: one keeper per burst, a reason under every other photo](images/phone-groups.png)

It is Sunday night. The baby is finally asleep. I open Photos to send one picture to her grandparents and find eleven of the same one: the burst from the play mat, shot in a panic because in at least one of them her eyes had to be open. I zoom into the first. Then the second. By the sixth I cannot tell them apart any more, so I send the first one and leave all eleven where they are.

Scroll up a little. Nine good-morning forwards from the family WhatsApp group. Six screenshots: a delivery status, a payment confirmation, a tweet I meant to show someone. A photo of a receipt I needed for exactly one day. Over three months this added up to 993 photos, and the twenty I actually cared about were somewhere in the pile.

## The app that promised to fix it

I downloaded the top cleaner in the App Store. It found "similar" photos and put a **Best** badge on one in each group. It did not say why. It wanted $11.99 a week. The reviews underneath told the rest of the story: "deleted years of photos", "similar meant same room", "five deletes a day unless you pay". Apple's own Duplicates album only catches exact copies and does nothing about bursts, forwards or screenshots.

I deleted the cleaner instead, and built the thing I wanted.

## What Sunday looks like now

![A group opened: the keeper, the score breakdown, and the reason for each of the others](images/phone-group-detail.png)

The app scans the last three months, groups the bursts and re-takes, and marks one keeper in each group. Every other photo gets a sentence: "1 face with eyes closed". "Lower face quality (0.61 vs 0.84)". "Near-identical; keeper was taken first". Disagree? Tap a different photo and it becomes the keeper. Want all eleven? Keep all. The app remembers your choice and never argues with it again.

![The Clutter tab: screenshots, forwards and documents in their own sections, with Select all](images/phone-clutter.png)

Screenshots, WhatsApp forwards, receipts and screen recordings land in their own sections with a Select all button each. Then one tap on Apply. iOS shows its own "Allow PhotoCull to delete these photos?" dialog, and everything moves to Recently Deleted, where it waits thirty days in case I change my mind.

On my library that meant 84 groups and 193 photos, one keeper each, reviewed in the time it takes to drink a coffee. The next Sunday only the new photos are analysed, so the whole thing is a two-minute habit. Nothing leaves the phone. No account, no subscription, no ads, and it is free on GitHub.

## How it tells your kid from your sofa

Nothing in the app is clever. It just uses things Apple already put in your phone and nobody bothered to wire together.

- **Faces.** iOS can score how good a photo of each face is, and whether the eyes are open and the person is smiling. Those three numbers decide most groups. A photo of a person is judged on the person, not on the composition.
- **"Utility" images.** The same framework that scores photos for aesthetics also flags receipts, documents, whiteboards and memes. That flag alone finds most of the clutter.
- **WhatsApp forwards.** When WhatsApp re-encodes an image it strips the camera make and model. A JPEG with no camera information is a photo you received, not one you took. No album needed.
- **Sameness.** iOS can turn a photo into a fingerprint and measure how far apart two fingerprints are. Bursts and re-takes are close. Different scenes are far. All of it runs on the phone, about a tenth of a second per photo.

## The day it grouped my whole afternoon

The first version used the fingerprint distance everyone online seemed to use: 0.6. On my phone that put 81 percent of all compared photo pairs into groups. The baby on the mat, the baby on the bed and the birthday cake became one group with one keeper and ten deletions. It was, exactly, the failure from the one-star reviews, and I had built it in an afternoon.

![The same library at 0.60 and at 0.05](images/calibrate-060-vs-005.png)

The fix was not a better number. It was a slider. I added a screen that draws every compared pair on a chart, lets me drag the threshold, and shows the groups that would form. At 0.05 the groups were exactly the bursts and re-takes, nothing else: 127 pairs instead of 3,053. Apple does not document the scale of that distance, and it changes between iOS versions. Whatever number you read anywhere, including here, is a guess until you have measured it on your own photos.

## For the engineers

![Six stages, two layers](images/stages.png)

The app is about 5,500 lines of Swift with one hard boundary. Everything that touches the device lives in the app target. Everything that decides lives in a pure-Swift package with no UIKit, Vision, PhotoKit or SwiftData imports and 70 unit tests that run on a Mac in seconds. The whole pipeline is one call: `Planner(thresholds:).plan(metrics:distance:)` takes per-photo metrics and a distance closure and returns groups, keepers, reasons and decisions.

The per-photo analysis is four Vision requests, one Core Image detector and an EXIF probe, all in iOS 18 and later:

```swift
let handler = ImageRequestHandler(cgImage)
let print      = try await handler.perform(GenerateImageFeaturePrintRequest())
let aesthetics = try await handler.perform(CalculateImageAestheticsScoresRequest())
let faces      = try await handler.perform(DetectFaceCaptureQualityRequest())
// CIDetector adds eyes-open and smile per face, matched to Vision faces by IoU
// RecognizeTextRequest runs only when the result could change a decision
```

![How the keeper is chosen](images/scoring.png)

Deleting is the one thing the app must never get wrong, so the safety rules are structural. `PHAssetChangeRequest.deleteAssets` appears in exactly one place, behind the Apply screen's confirmed action, as a single `performChanges` call. Favorites are never candidates. Every candidate is re-fetched by identifier right before deletion and skipped if it was modified after analysis. Your own decisions are never re-scored. `URLSession` appears in one file, an optional Claude second opinion for genuine ties that is off by default, needs your own key, asks before every batch, and can only move the keeper inside the tie.

Videos get the same treatment with different signals: exact duplicates by duration, size and dimensions; same-take similarity from three sampled frames; screen recordings by exact screen dimensions. Nothing is ever downloaded from iCloud to analyse it.

The full write-up, with the timing numbers, the calibration data and the market comparison, is in the repo.

## Try it

Clone **[github.com/GauravJiandaniGJ/photocull](https://github.com/GauravJiandaniGJ/photocull)**, put your team and bundle id in `project.yml`, run `xcodegen generate`, and deploy to your phone. Then, before you trust a single group, open Settings, long-press the version number, and calibrate. Your number will not be my number. That is the point.

MIT licensed. If it saves you a Sunday, tell me what it got wrong.
