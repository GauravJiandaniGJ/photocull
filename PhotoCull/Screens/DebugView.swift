import SwiftData
import SwiftUI

/// Hidden behind a long-press on the version label in Settings.
/// Milestone 1 adds the raw-metrics table and the Calibrate view (spec §5.3).
struct DebugView: View {
    @Query private var cached: [AssetRecord]

    var body: some View {
        List {
            Section("Raw metrics") {
                LabeledContent("Cached AssetRecords", value: cached.count, format: .number)
                Text("Per-asset metrics table arrives with the feature extractor (milestone 1).")
                    .foregroundStyle(.secondary)
            }
            Section("Calibrate") {
                Text("Histogram of pairwise feature-print distances inside time buckets, a threshold slider and a live group count. Built in milestone 1; sets similarityDistanceMax.")
                    .foregroundStyle(.secondary)
            }
            Section("Timing") {
                Text("Per-request Vision timings appear here after the first scan.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Debug")
    }
}
