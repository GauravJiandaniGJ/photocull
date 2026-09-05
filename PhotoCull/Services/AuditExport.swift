import Foundation
import PhotoCullCore

/// Writes the audit log for one applied session as JSON and CSV files in the temp directory.
enum AuditExport {
    struct Files {
        let json: URL
        let csv: URL
    }

    private struct Document: Encodable {
        struct Row: Encodable {
            let assetID: String
            let action: String
            let applied: Bool
            let category: String
            let reason: String
            let source: String
            let groupID: UUID?
            let creationDate: Date
        }
        let sessionID: UUID
        let rangeStart: Date
        let rangeEnd: Date
        let appliedAt: Date
        let thresholds: Thresholds?
        let summary: AuditSummary?
        let decisions: [Row]
    }

    static func write(session: ScanSession, audit: AuditEntry) throws -> Files {
        let deleted = Set(audit.deletedIDs)
        let rows = session.decisions
            .sorted { $0.creationDate < $1.creationDate }
            .map { d in
                Document.Row(
                    assetID: d.assetID, action: d.action, applied: deleted.contains(d.assetID),
                    category: d.category, reason: d.reason, source: d.source, groupID: d.groupID, creationDate: d.creationDate
                )
            }
        let document = Document(
            sessionID: session.id,
            rangeStart: session.startDate,
            rangeEnd: session.endDate,
            appliedAt: audit.appliedAt,
            thresholds: try? JSONDecoder().decode(Thresholds.self, from: session.thresholdsJSON),
            summary: try? JSONDecoder().decode(AuditSummary.self, from: audit.summaryJSON),
            decisions: rows
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let stamp = ISO8601DateFormatter().string(from: audit.appliedAt).replacingOccurrences(of: ":", with: "-")
        let dir = FileManager.default.temporaryDirectory
        let jsonURL = dir.appendingPathComponent("photocull-log-\(stamp).json")
        try encoder.encode(document).write(to: jsonURL, options: .atomic)

        var csv = "assetID,action,applied,category,reason,source,groupID,creationDate\n"
        let iso = ISO8601DateFormatter()
        for r in rows {
            let fields = [r.assetID, r.action, String(r.applied), r.category, r.reason, r.source, r.groupID?.uuidString ?? "", iso.string(from: r.creationDate)]
            csv += fields.map(escape).joined(separator: ",") + "\n"
        }
        let csvURL = dir.appendingPathComponent("photocull-log-\(stamp).csv")
        try csv.write(to: csvURL, atomically: true, encoding: .utf8)
        return Files(json: jsonURL, csv: csvURL)
    }

    private static func escape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}
