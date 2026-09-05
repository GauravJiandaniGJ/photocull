import Foundation
import PhotoCullCore
import UIKit

enum TieBreakError: Error, LocalizedError {
    case imageUnavailable(String)
    case badResponse
    case api(status: Int, message: String?)
    case refused
    case noText
    case unparseable(String)

    var errorDescription: String? {
        switch self {
        case .imageUnavailable(let id): return "Could not load image \(id.prefix(8))…"
        case .badResponse: return "Unexpected response from the API"
        case .api(let status, let message): return "API error \(status): \(message ?? "no details")"
        case .refused: return "Claude declined to judge these photos"
        case .noText: return "The reply contained no text"
        case .unparseable(let text): return "Could not read the verdict: \(text.prefix(80))"
        }
    }
}

/// Spec §5.5. One request per tied group: numbered, downscaled JPEGs (no metadata, no
/// filenames) followed by the fixed prompt. Constructed only after the user confirms.
struct ClaudeTieBreaker: Sendable {
    let apiKey: String
    let model: String
    let imageLongEdge: Int

    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let modelsEndpoint = URL(string: "https://api.anthropic.com/v1/models")!

    func resolve(candidateIDs: [String]) async throws -> TieBreakVerdict {
        var content: [[String: Any]] = []
        for (index, id) in candidateIDs.enumerated() {
            guard let image = await PhotoImageLoader.image(id: id, longEdge: CGFloat(imageLongEdge)),
                  let upright = PhotoImageLoader.uprightCGImage(image),
                  let jpeg = UIImage(cgImage: upright).jpegData(compressionQuality: 0.7)
            else { throw TieBreakError.imageUnavailable(id) }
            content.append(["type": "text", "text": "Photo \(index + 1):"])
            content.append([
                "type": "image",
                "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()],
            ])
        }
        content.append(["type": "text", "text": TieBreakPrompt.text(candidateCount: candidateIDs.count)])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 400,
            "thinking": ["type": "disabled"],
            "messages": [["role": "user", "content": content]],
        ]
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        Self.applyHeaders(&request, apiKey: apiKey)
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TieBreakError.badResponse }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard http.statusCode == 200 else {
            let message = (json?["error"] as? [String: Any])?["message"] as? String
            throw TieBreakError.api(status: http.statusCode, message: message)
        }
        if (json?["stop_reason"] as? String) == "refusal" { throw TieBreakError.refused }
        guard let blocks = json?["content"] as? [[String: Any]],
              let text = blocks.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String
        else { throw TieBreakError.noText }
        guard let verdict = TieBreakVerdict.parse(text, candidateCount: candidateIDs.count) else {
            throw TieBreakError.unparseable(text)
        }
        return verdict
    }

    /// Settings → "Test connection": validates the key and the model id without spending tokens.
    static func checkModel(_ model: String, apiKey: String) async -> Result<String, TieBreakError> {
        var request = URLRequest(url: modelsEndpoint.appendingPathComponent(model))
        request.timeoutInterval = 20
        applyHeaders(&request, apiKey: apiKey)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failure(.badResponse) }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard http.statusCode == 200 else {
                return .failure(.api(status: http.statusCode, message: (json?["error"] as? [String: Any])?["message"] as? String))
            }
            return .success((json?["display_name"] as? String) ?? model)
        } catch {
            return .failure(.api(status: 0, message: error.localizedDescription))
        }
    }

    private static func applyHeaders(_ request: inout URLRequest, apiKey: String) {
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    }
}
