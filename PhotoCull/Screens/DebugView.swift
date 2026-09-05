import PhotoCullCore
import SwiftData
import SwiftUI

/// Hidden behind a long-press on the version label in Settings.
struct DebugView: View {
    @Environment(ScanController.self) private var scan
    @Query private var cached: [AssetRecord]
    @State private var metricsCSV: URL?
    @State private var distancesCSV: URL?
    @State private var exportError: String?

    var body: some View {
        List {
            Section("Raw metrics") {
                NavigationLink {
                    MetricsTableView()
                } label: {
                    LabeledContent("Cached photos", value: cached.count, format: .number)
                }
            }

            Section("Calibrate") {
                NavigationLink("Distance histogram + threshold") { CalibrateView() }
                    .disabled(scan.calibration == nil)
                if scan.calibration == nil {
                    Text("Run a scan first; feature prints only exist for the current session.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Timing per request (last scan)") {
                let stats = scan.extractor.timingStats.sorted { $0.value.totalMs > $1.value.totalMs }
                if stats.isEmpty {
                    Text("No timings yet.").foregroundStyle(.secondary)
                }
                ForEach(stats, id: \.key) { name, stat in
                    LabeledContent(name) {
                        Text("\(stat.averageMs, format: .number.precision(.fractionLength(0))) ms avg · \(stat.count.formatted())×")
                            .monospacedDigit()
                    }
                }
            }

            Section("Export") {
                Button("Prepare CSV files") { prepareExports() }
                    .disabled(cached.isEmpty && scan.calibration == nil)
                if let metricsCSV {
                    ShareLink("Share metrics.csv", item: metricsCSV)
                }
                if let distancesCSV {
                    ShareLink("Share distances.csv", item: distancesCSV)
                }
                if let exportError {
                    Text(exportError).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Debug")
    }

    private func prepareExports() {
        let dir = FileManager.default.temporaryDirectory
        do {
            var metrics = "id,creationDate,category,reason,uti,aesthetics,isUtility,faces,eyesOpenFaces,smilingFaces,textChars,hasCameraExif,inWhatsApp,screenshot,favorite,burst\n"
            let decoder = JSONDecoder()
            for r in cached {
                guard let m = try? decoder.decode(AssetMetrics.self, from: r.metricsJSON) else { continue }
                let fields: [String] = [
                    m.id, ISO8601DateFormatter().string(from: m.creationDate), r.category, r.categoryReason, m.fileUTI,
                    m.aestheticsScore.map { String(format: "%.3f", $0) } ?? "", m.isUtility.map(String.init) ?? "",
                    String(m.faces.count), String(m.faces.filter(\.bothEyesOpen).count), String(m.faces.filter(\.smiling).count),
                    m.textCharCount.map(String.init) ?? "", m.hasCameraExif.map(String.init) ?? "",
                    String(m.inWhatsAppAlbum), String(m.isScreenshot), String(m.isFavorite), m.burstIdentifier ?? "",
                ]
                metrics += fields.map(Self.csvEscape).joined(separator: ",") + "\n"
            }
            let metricsURL = dir.appendingPathComponent("photocull-metrics.csv")
            try metrics.write(to: metricsURL, atomically: true, encoding: .utf8)
            metricsCSV = metricsURL

            if let calibration = scan.calibration {
                var distances = "idA,idB,distance\n"
                for (pair, d) in calibration.distances.sorted(by: { $0.value < $1.value }) {
                    distances += "\(Self.csvEscape(pair.a)),\(Self.csvEscape(pair.b)),\(String(format: "%.4f", d))\n"
                }
                let distancesURL = dir.appendingPathComponent("photocull-distances.csv")
                try distances.write(to: distancesURL, atomically: true, encoding: .utf8)
                distancesCSV = distancesURL
            }
            exportError = nil
        } catch {
            exportError = error.localizedDescription
        }
    }

    private static func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}
