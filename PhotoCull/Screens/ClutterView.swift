import PhotoCullCore
import SwiftData
import SwiftUI

/// Spec §6 Clutter: sectioned grid with checkmarks (checked = delete), select-all per section.
struct ClutterView: View {
    @Query(sort: \ScanSession.createdAt, order: .reverse) private var sessions: [ScanSession]
    @Environment(ScanController.self) private var scan
    @Environment(\.modelContext) private var context
    @State private var selected: Decision?

    private static let sections: [(AssetCategory, String)] = [
        (.screenshot, "Screenshots"),
        (.receivedUtility, "Received (text/documents)"),
        (.receivedPhoto, "Received photos"),
        (.utility, "Documents/receipts"),
    ]

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]

    private var session: ScanSession? { sessions.first }

    /// Clutter decisions only: not in a group, not personal. Newest first.
    private var rowsByCategory: [AssetCategory: [Decision]] {
        var out: [AssetCategory: [Decision]] = [:]
        for d in session?.decisions ?? [] where d.groupID == nil {
            guard let category = AssetCategory(rawValue: d.category), category != .personal else { continue }
            out[category, default: []].append(d)
        }
        for key in out.keys { out[key]?.sort { $0.creationDate > $1.creationDate } }
        return out
    }

    var body: some View {
        NavigationStack {
            let rows = rowsByCategory
            Group {
                if rows.isEmpty {
                    ContentUnavailableView(
                        "No clutter found yet",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Screenshots, WhatsApp forwards and documents show up here after a scan.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12, pinnedViews: .sectionHeaders) {
                            ForEach(Self.sections, id: \.0) { category, title in
                                if let items = rows[category], !items.isEmpty {
                                    Section {
                                        LazyVGrid(columns: columns, spacing: 4) {
                                            ForEach(items, id: \.id) { decision in
                                                ClutterCell(decision: decision) {
                                                    selected = decision
                                                } toggle: {
                                                    Review.set(decision, to: decision.isDelete ? .keep : .delete, context: context)
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 4)
                                    } header: {
                                        sectionHeader(title: title, items: items)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Clutter")
            .onAppear { scan.reviewOpened = true }
            .sheet(item: $selected) { decision in
                ClutterDetailSheet(decision: decision)
            }
        }
    }

    private func sectionHeader(title: String, items: [Decision]) -> some View {
        let deleting = items.filter(\.isDelete).count
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(title) · \(items.count.formatted())").font(.headline)
                Text("\(deleting.formatted()) to delete").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Select all") { Review.setAll(items, to: .delete, context: context) }
                .disabled(deleting == items.count)
            Button("Deselect all") { Review.setAll(items, to: .keep, context: context) }
                .disabled(deleting == 0)
        }
        .font(.subheadline)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct ClutterCell: View {
    let decision: Decision
    let open: () -> Void
    let toggle: () -> Void

    var body: some View {
        AssetThumbnail(id: decision.assetID, side: 110)
            .opacity(decision.isDelete ? 0.55 : 1)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            .overlay(alignment: .topTrailing) {
                Button(action: toggle) {
                    Image(systemName: decision.isDelete ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, decision.isDelete ? Color.red : Color.black.opacity(0.35))
                        .shadow(radius: 1)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .disabled(decision.isProtected)
            }
            .overlay(alignment: .bottomLeading) {
                if decision.isProtected {
                    Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow).padding(6)
                }
            }
    }
}

struct ClutterDetailSheet: View {
    let decision: Decision
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AssetImage(id: decision.assetID)
                    .frame(maxHeight: .infinity)
                    .background(Color.black)
                Form {
                    LabeledContent("Category", value: decision.category)
                    LabeledContent("Reason", value: decision.reason)
                    LabeledContent("Taken", value: decision.creationDate, format: .dateTime.day().month().year().hour().minute())
                    Picker("Decision", selection: Binding(
                        get: { decision.isDelete ? CullAction.delete : CullAction.keep },
                        set: { Review.set(decision, to: $0, context: context) }
                    )) {
                        Text("Keep").tag(CullAction.keep)
                        Text("Delete").tag(CullAction.delete)
                    }
                    .pickerStyle(.segmented)
                    .disabled(decision.isProtected)
                    if decision.isProtected {
                        Text("Favorites are never deleted.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 260)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
