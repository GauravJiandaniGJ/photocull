import Foundation
import Observation

enum ClaudeModel: String, CaseIterable, Identifiable {
    case sonnet = "claude-sonnet-5"
    case haiku = "claude-haiku-4-5"

    var id: String { rawValue }
    var label: String { self == .sonnet ? "Sonnet 5 (default)" : "Haiku 4.5 (cheaper)" }

    /// USD per million tokens (input, output), from the current price list.
    var pricePerMillion: (input: Double, output: Double) {
        switch self {
        case .sonnet: return (2.0, 10.0)
        case .haiku: return (1.0, 5.0)
        }
    }
}

/// Toggle, model and key presence for the tie-breaker. The key itself stays in the Keychain
/// and is only read at the moment a confirmed request is built.
@MainActor
@Observable
final class ClaudeSettings {
    private static let enabledKey = "claude.enabled"
    private static let modelKey = "claude.model"

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled != oldValue { AppLog.info(.settings, "Claude tie-breaker \(isEnabled ? "enabled" : "disabled")") }
        }
    }

    var model: ClaudeModel {
        didSet {
            UserDefaults.standard.set(model.rawValue, forKey: Self.modelKey)
            if model != oldValue { AppLog.info(.settings, "Claude model set to \(model.rawValue)") }
        }
    }

    private(set) var hasKey: Bool

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        model = ClaudeModel(rawValue: defaults.string(forKey: Self.modelKey) ?? "") ?? .sonnet
        hasKey = KeychainStore.read(KeychainStore.claudeAPIKey) != nil
    }

    /// The tie-breaker is offered only when switched on AND a key exists.
    var isAvailable: Bool { isEnabled && hasKey }

    func refreshKey() {
        hasKey = KeychainStore.read(KeychainStore.claudeAPIKey) != nil
    }

    func saveKey(_ key: String) throws {
        try KeychainStore.write(key, account: KeychainStore.claudeAPIKey)
        refreshKey()
        AppLog.info(.settings, "Claude API key stored in Keychain")
    }

    func removeKey() {
        KeychainStore.delete(KeychainStore.claudeAPIKey)
        refreshKey()
        AppLog.info(.settings, "Claude API key removed")
    }

    func apiKey() -> String? {
        KeychainStore.read(KeychainStore.claudeAPIKey)
    }

    /// Rough spend for `photos` images across `calls` requests: ~590 visual tokens per 768px
    /// photo, ~150 prompt tokens and ~80 output tokens per call.
    func estimatedCost(photos: Int, calls: Int) -> Double {
        let price = model.pricePerMillion
        let inputTokens = Double(photos * 590 + calls * 150)
        let outputTokens = Double(calls * 80)
        return inputTokens / 1_000_000 * price.input + outputTokens / 1_000_000 * price.output
    }
}
