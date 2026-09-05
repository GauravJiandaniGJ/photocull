import Foundation

/// The Claude tie-breaker's answer (spec §5.5). Parsing lives here so it is unit-testable;
/// the HTTP client stays in the app target.
public struct TieBreakVerdict: Codable, Equatable, Sendable {
    /// 1-based index into the images that were sent.
    public let winner: Int
    public let reason: String
    public let confidence: Double

    public static let minimumConfidence = 0.5

    public init(winner: Int, reason: String, confidence: Double) {
        self.winner = winner
        self.reason = reason
        self.confidence = confidence
    }

    /// Below the minimum the caller falls back to the local tie-break.
    public var isConfident: Bool { confidence >= Self.minimumConfidence }

    /// Parses the model's text, tolerating ``` fences and prose around the JSON object.
    /// Returns nil for anything malformed or a winner outside 1…candidateCount.
    public static func parse(_ text: String, candidateCount: Int) -> TieBreakVerdict? {
        guard let json = extractJSONObject(from: text),
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        guard let winner = intValue(object["winner"]),
              (1...max(candidateCount, 1)).contains(winner),
              candidateCount >= 1
        else { return nil }
        let reason = (object["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let confidence = doubleValue(object["confidence"]), (0...1).contains(confidence) else { return nil }
        return TieBreakVerdict(winner: winner, reason: reason.isEmpty ? "Chosen by tie-breaker" : reason, confidence: confidence)
    }

    static func extractJSONObject(from raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            // Drop the opening fence line (``` or ```json) and a closing fence if present.
            if let newline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: newline)...])
            } else {
                text = String(text.dropFirst(3))
            }
            if let close = text.range(of: "```", options: .backwards) {
                text = String(text[..<close.lowerBound])
            }
        }
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close else { return nil }
        return String(text[open...close])
    }

    private static func intValue(_ any: Any?) -> Int? {
        switch any {
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        switch any {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }
}

public enum TieBreakPrompt {
    /// The text block that follows the numbered image blocks in the tie-breaker request.
    public static func text(candidateCount n: Int) -> String {
        """
        These are \(n) near-identical photos of the same moment, numbered Photo 1 to Photo \(n) in order. \
        Choose the single best one to keep, judged by: everyone's eyes open, looking at the camera or \
        naturally engaged, natural expression, sharp faces, then overall composition. \
        Respond with JSON only: {"winner": <1-based index>, "reason": "<one sentence>", "confidence": <0-1>}
        """
    }
}
