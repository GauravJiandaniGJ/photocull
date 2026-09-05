import PhotoCullCore
import SwiftData
import SwiftUI

/// Debug: every cached AssetRecord with its raw metrics, newest analysis first.
struct MetricsTableView: View {
    @Query(sort: \AssetRecord.analyzedAt, order: .reverse) private var records: [AssetRecord]

    var body: some View {
        List(records, id: \.localIdentifier) { record in
            HStack(alignment: .top, spacing: 12) {
                AssetThumbnail(id: record.localIdentifier, side: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.category).font(.headline)
                    Text(record.categoryReason).font(.footnote).foregroundStyle(.secondary)
                    if let m = try? JSONDecoder().decode(AssetMetrics.self, from: record.metricsJSON) {
                        Text(Self.line(m)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Raw metrics (\(records.count.formatted()))")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func line(_ m: AssetMetrics) -> String {
        var parts: [String] = []
        parts.append(m.fileUTI.replacingOccurrences(of: "public.", with: ""))
        if let a = m.aestheticsScore { parts.append(String(format: "aes %.2f", a)) }
        if m.isUtility == true { parts.append("utility") }
        if !m.faces.isEmpty {
            let open = m.faces.filter(\.bothEyesOpen).count
            let smiling = m.faces.filter(\.smiling).count
            parts.append("faces \(m.faces.count) · eyes \(open)/\(m.faces.count) · smile \(smiling)")
        }
        if let t = m.textCharCount { parts.append("text \(t)") }
        if let exif = m.hasCameraExif { parts.append(exif ? "exif" : "no exif") }
        if m.inWhatsAppAlbum { parts.append("whatsapp") }
        if m.isScreenshot { parts.append("screenshot") }
        if m.isFavorite { parts.append("★") }
        return parts.joined(separator: " · ")
    }
}
