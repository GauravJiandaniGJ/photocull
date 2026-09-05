import PhotoCullCore
import SwiftData
import SwiftUI

/// Read-only summary plus the one button that moves photos to Recently Deleted (spec §6, §8).
struct ApplyView: View {
    @Query(sort: \ScanSession.createdAt, order: .reverse) private var sessions: [ScanSession]
    @Environment(\.modelContext) private var context
    @State private var apply = ApplyController()
    @State private var confirming = false

    private var session: ScanSession? { sessions.first }
    private var decisions: [Decision] { session?.decisions ?? [] }
    private var toDelete: [Decision] { decisions.filter { $0.isDelete && !$0.isProtected } }
    private var fromGroups: Int { toDelete.filter { $0.groupID != nil && !$0.isVideo }.count }
    private var fromVideoGroups: Int { toDelete.filter { $0.groupID != nil && $0.isVideo }.count }
    private var bytesToFree: Int64 { toDelete.reduce(Int64(0)) { $0 + $1.fileSize } }
    private var isApplied: Bool { session?.status == ScanStatus.applied }

    private func clutterCount(_ category: AssetCategory) -> Int {
        toDelete.filter { $0.groupID == nil && $0.category == category.rawValue }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                if let session {
                    Section("Session") {
                        LabeledContent("Range") {
                            Text(session.startDate, format: .dateTime.day().month()) + Text(" – ") + Text(session.endDate, format: .dateTime.day().month().year())
                        }
                        LabeledContent("Scanned", value: session.createdAt, format: .dateTime.day().month().hour().minute())
                        LabeledContent("Status", value: session.status.capitalized)
                    }

                    Section("To delete") {
                        LabeledContent("From groups", value: fromGroups, format: .number)
                        LabeledContent("Screenshots", value: clutterCount(.screenshot), format: .number)
                        LabeledContent("Received (text/documents)", value: clutterCount(.receivedUtility), format: .number)
                        LabeledContent("Received photos", value: clutterCount(.receivedPhoto), format: .number)
                        LabeledContent("Documents/receipts", value: clutterCount(.utility), format: .number)
                        LabeledContent("From video duplicates/takes", value: fromVideoGroups, format: .number)
                        LabeledContent("Screen recordings", value: clutterCount(.screenRecording), format: .number)
                        LabeledContent("Received videos", value: clutterCount(.receivedVideo), format: .number)
                        LabeledContent("Videos", value: clutterCount(.personalVideo), format: .number)
                        LabeledContent("Total") { Text(toDelete.count, format: .number).bold() }
                        LabeledContent("Video space to free", value: MediaFormat.bytes(bytesToFree))
                    }

                    Section("Kept") {
                        LabeledContent("Kept", value: decisions.count - toDelete.count, format: .number)
                        LabeledContent("Favorites protected", value: decisions.filter(\.isProtected).count, format: .number)
                        LabeledContent("Your overrides", value: decisions.filter(\.isUserDecision).count, format: .number)
                    }

                    if isApplied {
                        Section {
                            NavigationLink("Audit log and export") { AuditDetailView(session: session) }
                        } header: {
                            Text("Applied")
                        } footer: {
                            Text("Undo within 30 days: Photos → Albums → Recently Deleted. Run a new scan to continue.")
                        }
                    } else {
                        applySection(session)
                    }
                } else {
                    ContentUnavailableView("Nothing to apply", systemImage: "trash", description: Text("Run a scan and review the results first."))
                }
            }
            .navigationTitle("Apply")
            .confirmationDialog(
                "Move \(toDelete.count.formatted()) photos to Recently Deleted?",
                isPresented: $confirming,
                titleVisibility: .visible
            ) {
                Button("Move \(toDelete.count.formatted()) photos", role: .destructive) {
                    guard let session else { return }
                    Task { await apply.apply(session: session, context: context) }
                }
            } message: {
                Text("iOS will ask once more. Photos stay in Recently Deleted for 30 days; favorites and anything changed since the scan are skipped.")
            }
        }
    }

    @ViewBuilder
    private func applySection(_ session: ScanSession) -> some View {
        Section {
            Button(role: .destructive) {
                confirming = true
            } label: {
                HStack {
                    if apply.isBusy { ProgressView().padding(.trailing, 6) }
                    Label("Move \(toDelete.count.formatted()) photos to Recently Deleted", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(!Journey(session: session).canApply || toDelete.isEmpty || apply.isBusy)
        } footer: {
            let journey = Journey(session: session)
            if !journey.canApply {
                Text("Open Groups or Clutter first to review the decisions.")
            } else if session.groupsVisitedAt == nil {
                Text("You have not opened Groups for this scan. Group losers are included in the count above.")
            } else if session.clutterVisitedAt == nil {
                Text("You have not opened Clutter for this scan. Screenshots and received documents are ticked by default.")
            } else if toDelete.isEmpty {
                Text("No delete candidates in this session.")
            } else {
                Text("One system dialog follows. Nothing is removed permanently: Recently Deleted keeps photos for 30 days.")
            }
        }
        switch apply.state {
        case .cancelled:
            Section { Label("Cancelled in the system dialog. Nothing was deleted.", systemImage: "xmark.circle") }
        case .failed(let message):
            Section { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
        case .done:
            if let r = apply.result {
                Section {
                    Label("Moved \(r.deleted.formatted()) photos to Recently Deleted", systemImage: "checkmark.circle").foregroundStyle(.green)
                    if r.skippedMissing + r.skippedModified + r.skippedFavorite > 0 {
                        Text("Skipped \(r.skippedMissing) missing, \(r.skippedModified) changed since analysis, \(r.skippedFavorite) favorited since.")
                            .font(.footnote)
                    }
                }
            }
        default:
            EmptyView()
        }
    }
}
