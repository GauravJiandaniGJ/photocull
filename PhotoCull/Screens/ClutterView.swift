import PhotoCullCore
import SwiftData
import SwiftUI

struct ClutterView: View {
    @Query(sort: \ScanSession.createdAt, order: .reverse) private var sessions: [ScanSession]

    private static let sections: [(AssetCategory, String)] = [
        (.screenshot, "Screenshots"),
        (.receivedUtility, "Received (text/documents)"),
        (.receivedPhoto, "Received photos"),
        (.utility, "Documents/receipts"),
    ]

    private var decisions: [Decision] { sessions.first?.decisions ?? [] }

    var body: some View {
        NavigationStack {
            Group {
                if decisions.isEmpty {
                    ContentUnavailableView(
                        "No clutter found yet",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Screenshots, WhatsApp forwards and documents show up here after a scan.")
                    )
                } else {
                    List {
                        ForEach(Self.sections, id: \.0) { category, title in
                            let rows = decisions.filter { $0.category == category.rawValue }
                            Section("\(title) · \(rows.count)") {
                                ForEach(rows, id: \.id) { d in
                                    LabeledContent(d.reason, value: d.action.capitalized)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Clutter")
        }
    }
}
