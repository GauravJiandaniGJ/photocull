import SwiftData
import SwiftUI

/// What was applied for one session, with the exportable log. Used from Apply and Settings history.
struct AuditDetailView: View {
    let session: ScanSession
    @Query private var audits: [AuditEntry]
    @State private var files: AuditExport.Files?
    @State private var exportError: String?

    private var audit: AuditEntry? {
        audits.filter { $0.sessionID == session.id }.max { $0.appliedAt < $1.appliedAt }
    }

    private var summary: AuditSummary? {
        audit.flatMap { try? JSONDecoder().decode(AuditSummary.self, from: $0.summaryJSON) }
    }

    var body: some View {
        List {
            if let audit {
                Section("Applied") {
                    LabeledContent("When", value: audit.appliedAt, format: .dateTime.day().month().year().hour().minute())
                    LabeledContent("Moved to Recently Deleted", value: audit.deletedIDs.count, format: .number)
                    LabeledContent("Kept", value: audit.keptIDs.count, format: .number)
                    if let s = summary {
                        ForEach(s.deletedByCategory.sorted(by: { $0.key < $1.key }), id: \.key) { category, count in
                            LabeledContent("  \(category)", value: count, format: .number)
                        }
                        if s.skippedMissing + s.skippedModified + s.skippedFavorite > 0 {
                            LabeledContent("Skipped (missing / changed / favorited)", value: "\(s.skippedMissing) / \(s.skippedModified) / \(s.skippedFavorite)")
                        }
                        LabeledContent("Your overrides", value: s.userOverrides, format: .number)
                    }
                }
                Section {
                    Label("Undo within 30 days: Photos → Albums → Recently Deleted", systemImage: "arrow.uturn.backward.circle")
                }
                Section("Export log") {
                    if let files {
                        ShareLink("Share JSON", item: files.json)
                        ShareLink("Share CSV", item: files.csv)
                    } else if let exportError {
                        Text(exportError).foregroundStyle(.red)
                    } else {
                        ProgressView()
                    }
                }
            } else {
                ContentUnavailableView("Not applied", systemImage: "trash.slash", description: Text("This session has no audit entry."))
            }
        }
        .navigationTitle("Audit log")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: audit?.id) {
            guard let audit else { return }
            do { files = try AuditExport.write(session: session, audit: audit) } catch { exportError = error.localizedDescription }
        }
    }
}
