import PhotoCullCore
import SwiftData
import SwiftUI

/// The ONLY screen that may ever call `PHAssetChangeRequest.deleteAssets` (safety rule 1).
/// The delete path itself is milestone 4; until then the button stays disabled.
struct ApplyView: View {
    @Query(sort: \ScanSession.createdAt, order: .reverse) private var sessions: [ScanSession]

    private var decisions: [Decision] { sessions.first?.decisions ?? [] }
    private var toDelete: [Decision] { decisions.filter { $0.action == CullAction.delete.rawValue } }
    private var kept: Int { decisions.count - toDelete.count }

    var body: some View {
        NavigationStack {
            Form {
                Section("This session") {
                    LabeledContent("To delete", value: toDelete.count, format: .number)
                    LabeledContent("Kept", value: kept, format: .number)
                }
                Section {
                    Button(role: .destructive) {
                    } label: {
                        Label("Move \(toDelete.count) photos to Recently Deleted", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(true)
                } footer: {
                    Text("Deleted photos go to Photos → Albums → Recently Deleted and can be restored for 30 days. Apply is built in milestone 4.")
                }
            }
            .navigationTitle("Apply")
        }
    }
}
