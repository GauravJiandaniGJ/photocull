import XCTest
@testable import PhotoCullCore

final class TieBreakVerdictTests: XCTestCase {
    func testParsesPlainJSON() {
        let v = TieBreakVerdict.parse(#"{"winner": 2, "reason": "Everyone's eyes are open.", "confidence": 0.9}"#, candidateCount: 3)
        XCTAssertEqual(v, TieBreakVerdict(winner: 2, reason: "Everyone's eyes are open.", confidence: 0.9))
        XCTAssertTrue(v!.isConfident)
    }

    func testParsesFencedJSON() {
        let text = """
        ```json
        {"winner": 1, "reason": "Sharpest faces", "confidence": 0.75}
        ```
        """
        XCTAssertEqual(TieBreakVerdict.parse(text, candidateCount: 2)?.winner, 1)
    }

    func testParsesJSONSurroundedByProse() {
        let text = "Sure! Here is my answer: {\"winner\": 3, \"reason\": \"Best composition\", \"confidence\": 0.6} Hope that helps."
        XCTAssertEqual(TieBreakVerdict.parse(text, candidateCount: 3)?.winner, 3)
    }

    func testAcceptsNumericStrings() {
        let v = TieBreakVerdict.parse(#"{"winner": "2", "reason": "ok", "confidence": "0.8"}"#, candidateCount: 2)
        XCTAssertEqual(v?.winner, 2)
        XCTAssertEqual(v?.confidence, 0.8)
    }

    func testMalformedResponseIsNil() {
        XCTAssertNil(TieBreakVerdict.parse("I cannot decide.", candidateCount: 2))
        XCTAssertNil(TieBreakVerdict.parse("{winner: 1}", candidateCount: 2))
        XCTAssertNil(TieBreakVerdict.parse("", candidateCount: 2))
        XCTAssertNil(TieBreakVerdict.parse(#"{"reason": "no winner", "confidence": 0.9}"#, candidateCount: 2))
    }

    func testWinnerOutOfRangeIsNil() {
        XCTAssertNil(TieBreakVerdict.parse(#"{"winner": 0, "reason": "x", "confidence": 0.9}"#, candidateCount: 2))
        XCTAssertNil(TieBreakVerdict.parse(#"{"winner": 3, "reason": "x", "confidence": 0.9}"#, candidateCount: 2))
    }

    func testLowConfidenceParsesButIsNotConfident() {
        let v = TieBreakVerdict.parse(#"{"winner": 1, "reason": "guess", "confidence": 0.4}"#, candidateCount: 2)
        XCTAssertNotNil(v)
        XCTAssertFalse(v!.isConfident)
    }

    func testEmptyReasonGetsAPlaceholder() {
        let v = TieBreakVerdict.parse(#"{"winner": 1, "reason": "", "confidence": 0.9}"#, candidateCount: 1)
        XCTAssertEqual(v?.reason, "Chosen by tie-breaker")
    }

    func testPromptMentionsCountAndJSONShape() {
        let p = TieBreakPrompt.text(candidateCount: 4)
        XCTAssertTrue(p.contains("4 near-identical photos"))
        XCTAssertTrue(p.contains("\"winner\""))
    }
}
