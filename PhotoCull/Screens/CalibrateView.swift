import Charts
import PhotoCullCore
import SwiftUI

/// Spec §5.3 calibration: histogram of pairwise feature-print distances inside time buckets,
/// a threshold slider, and a live preview of the groups that would form.
struct CalibrateView: View {
    @Environment(ScanController.self) private var scan
    @Environment(ThresholdsStore.self) private var store
    @State private var threshold: Float = Thresholds.default.similarityDistanceMax
    @State private var preview: [ProposedGroup] = []
    @State private var seeded = false

    private struct Bin: Identifiable {
        let id: Int
        let lower: Float
        let upper: Float
        let count: Int
    }

    var body: some View {
        Group {
            if let calibration = scan.calibration {
                content(calibration)
            } else {
                ContentUnavailableView(
                    "Run a scan first",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Calibration uses the feature prints from the most recent scan in this session.")
                )
            }
        }
        .navigationTitle("Calibrate")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ calibration: ScanController.Calibration) -> some View {
        let distances = Array(calibration.distances.values)
        let maxDistance = max(1, (distances.max() ?? 1).rounded(.up))
        let bins = Self.histogram(distances, upperBound: maxDistance, binCount: 40)
        return List {
            Section {
                Chart {
                    // Interval bars: on a numeric x axis a plain BarMark has no band width and draws nothing.
                    ForEach(bins) { bin in
                        BarMark(
                            xStart: .value("Distance", bin.lower),
                            xEnd: .value("Distance", bin.upper),
                            y: .value("Pairs", bin.count)
                        )
                        .foregroundStyle(bin.upper <= threshold ? Color.accentColor : Color.secondary.opacity(0.4))
                    }
                    RuleMark(x: .value("Threshold", threshold))
                        .foregroundStyle(.red)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartXScale(domain: 0...maxDistance)
                .chartXAxisLabel("Feature-print distance")
                .chartYAxisLabel("Pairs")
                .frame(height: 220)
                .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 4, trailing: 12))
            } header: {
                Text("\(distances.count.formatted()) pairwise distances in \(calibration.candidates.count.formatted()) groupable photos")
            } footer: {
                Text("Bars left of the red line are pairs that would be grouped. Pick a known burst and check it groups; pick a different-scene pair shot within a minute and check it does not.")
            }

            Section("Threshold") {
                HStack {
                    Slider(value: $threshold, in: 0...maxDistance, step: 0.01)
                    Text(threshold, format: .number.precision(.fractionLength(2)))
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
                LabeledContent("Pairs below threshold") {
                    let below = distances.filter { $0 <= threshold }.count
                    Text("\(below.formatted()) of \(distances.count.formatted())")
                }
                LabeledContent("Groups at this threshold", value: preview.count, format: .number)
                LabeledContent("Photos in groups", value: preview.reduce(0) { $0 + $1.memberIDs.count }, format: .number)
                LabeledContent("Current setting", value: store.thresholds.similarityDistanceMax, format: .number.precision(.fractionLength(2)))
                Button("Use \(threshold.formatted(.number.precision(.fractionLength(2)))) as similarity threshold") {
                    store.thresholds.similarityDistanceMax = threshold
                }
                .disabled(abs(threshold - store.thresholds.similarityDistanceMax) < 0.005)
            }

            Section("Groups preview (similar only, newest first)") {
                let similar = preview.filter { $0.kind == .similar }.reversed().prefix(40)
                if similar.isEmpty {
                    Text("No similarity groups at this threshold.").foregroundStyle(.secondary)
                }
                ForEach(Array(similar.enumerated()), id: \.offset) { _, group in
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(group.memberIDs, id: \.self) { id in
                                AssetThumbnail(id: id, side: 72)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
            }
        }
        .onAppear {
            if !seeded {
                threshold = store.thresholds.similarityDistanceMax
                seeded = true
            }
            recompute(calibration)
        }
        .onChange(of: threshold) { _, _ in recompute(calibration) }
    }

    private func recompute(_ calibration: ScanController.Calibration) {
        var thresholds = calibration.thresholds
        thresholds.similarityDistanceMax = threshold
        preview = Grouper(thresholds: thresholds).groups(for: calibration.candidates) { calibration.distance($0, $1) }
    }

    private static func histogram(_ values: [Float], upperBound: Float, binCount: Int) -> [Bin] {
        guard binCount > 0, upperBound > 0 else { return [] }
        let width = upperBound / Float(binCount)
        var counts = Array(repeating: 0, count: binCount)
        for v in values {
            let index = min(binCount - 1, max(0, Int(v / width)))
            counts[index] += 1
        }
        return counts.enumerated().map {
            Bin(id: $0.offset, lower: Float($0.offset) * width, upper: Float($0.offset + 1) * width, count: $0.element)
        }
    }
}
