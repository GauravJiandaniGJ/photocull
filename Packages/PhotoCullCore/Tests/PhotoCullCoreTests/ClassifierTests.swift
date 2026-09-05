import XCTest
@testable import PhotoCullCore

final class ClassifierTests: XCTestCase {
    let classifier = Classifier()

    func testFavoriteIsPersonalAndProtectedEvenIfScreenshot() {
        let c = classifier.classify(asset("a", screenshot: true, favorite: true))
        XCTAssertEqual(c.category, .personal)
        XCTAssertTrue(c.isProtected)
        XCTAssertEqual(c.defaultAction, .keep)
    }

    func testScreenshotIsDeleteCandidate() {
        let c = classifier.classify(asset("a", screenshot: true))
        XCTAssertEqual(c.category, .screenshot)
        XCTAssertEqual(c.defaultAction, .delete)
        XCTAssertEqual(c.reason, "Screenshot")
    }

    func testWhatsAppUtilityImageIsReceivedUtility() {
        let c = classifier.classify(asset("a", whatsApp: true, uti: "public.jpeg", exif: false, utility: true))
        XCTAssertEqual(c.category, .receivedUtility)
        XCTAssertEqual(c.defaultAction, .delete)
    }

    func testWhatsAppTextHeavyImageIsReceivedUtility() {
        let c = classifier.classify(asset("a", whatsApp: true, uti: "public.jpeg", exif: false, text: 80))
        XCTAssertEqual(c.category, .receivedUtility)
    }

    func testWhatsAppTextBelowThresholdIsReceivedPhoto() {
        let c = classifier.classify(asset("a", whatsApp: true, uti: "public.jpeg", exif: false, text: 79))
        XCTAssertEqual(c.category, .receivedPhoto)
        XCTAssertEqual(c.defaultAction, .keep)
        XCTAssertTrue(c.isGroupable)
    }

    func testJPEGWithoutCameraExifIsReceivedPhoto() {
        let c = classifier.classify(asset("a", uti: "public.jpeg", exif: false))
        XCTAssertEqual(c.category, .receivedPhoto)
        XCTAssertEqual(c.reason, "Received photo (no camera data)")
    }

    func testPNGWithoutCameraExifIsReceived() {
        XCTAssertEqual(classifier.classify(asset("a", uti: "public.png", exif: false)).category, .receivedPhoto)
    }

    func testJPEGWithCameraExifIsPersonal() {
        XCTAssertEqual(classifier.classify(asset("a", uti: "public.jpeg", exif: true)).category, .personal)
    }

    func testHEICWithUnprobedExifIsPersonal() {
        let c = classifier.classify(asset("a", uti: "public.heic", exif: nil))
        XCTAssertEqual(c.category, .personal)
        XCTAssertEqual(c.defaultAction, .keep)
    }

    func testCameraUtilityShotIsUtility() {
        let c = classifier.classify(asset("a", utility: true))
        XCTAssertEqual(c.category, .utility)
        XCTAssertEqual(c.defaultAction, .delete)
        XCTAssertFalse(c.isGroupable)
    }

    func testCustomTextThresholdIsHonoured() {
        let strict = Classifier(thresholds: Thresholds(textHeavyCharCount: 10))
        XCTAssertEqual(strict.classify(asset("a", whatsApp: true, text: 10)).category, .receivedUtility)
    }

    func testEveryClassificationHasAReason() {
        let samples = [
            asset("1", favorite: true), asset("2", screenshot: true),
            asset("3", whatsApp: true, utility: true), asset("4", whatsApp: true),
            asset("5", utility: true), asset("6"),
        ]
        for s in samples {
            XCTAssertFalse(classifier.classify(s).reason.isEmpty, "no reason for \(s.id)")
        }
    }
}
