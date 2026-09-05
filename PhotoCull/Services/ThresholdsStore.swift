import Foundation
import Observation
import PhotoCullCore

/// The live Thresholds, persisted as JSON in UserDefaults. Each scan snapshots a copy onto
/// its ScanSession so old decisions stay explainable after the user tunes a value.
@MainActor
@Observable
final class ThresholdsStore {
    private static let key = "thresholds.v1"

    var thresholds: Thresholds {
        didSet { save() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode(Thresholds.self, from: data) {
            thresholds = stored
        } else {
            thresholds = .default
        }
    }

    func reset() {
        thresholds = .default
    }

    private let defaults: UserDefaults

    private func save() {
        if let data = try? JSONEncoder().encode(thresholds) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
