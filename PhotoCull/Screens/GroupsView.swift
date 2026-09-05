import SwiftData
import SwiftUI

struct GroupsView: View {
    @Query(sort: \ScanSession.createdAt, order: .reverse) private var sessions: [ScanSession]

    private var groups: [PhotoGroup] {
        sessions.first?.groups.sorted { $0.memberIDs.first ?? "" > $1.memberIDs.first ?? "" } ?? []
    }

    var body: some View {
        NavigationStack {
            Group {
                if groups.isEmpty {
                    ContentUnavailableView(
                        "No groups yet",
                        systemImage: "square.stack.3d.up",
                        description: Text("Run a scan to find near-duplicate shots of the same moment.")
                    )
                } else {
                    List(groups, id: \.id) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(group.kind.capitalized) · \(group.memberIDs.count) photos")
                            Text(group.isTie ? "Tie" : "Keeper chosen")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Groups")
        }
    }
}
