import PhotoCullCore
import SwiftData
import SwiftUI

/// Spec §6 Clutter: sectioned grid with checkmarks (checked = delete), select-all per section.
struct ClutterView: View {
    @Query(sort: \ScanSession.createdAt, order: .reverse) private var sessions: [ScanSession]
    @Environment(AppNavigation.self) private var nav
    @Environment(\.modelContext) private var context
    @State private var selected: Decision?

    private static let sections: [(AssetCategory, String)] = [
        (.screenshot, "Screenshots"),
        (.receivedUtility, "Received (text/documents)"),
        (.receivedPhoto, "Received photos"),
        (.utility, "Documents/receipts"),
        (.screenRecording, "Screen recordings"),
        (.receivedVideo, "Received videos"),
        (.personalVideo, "Videos, largest first"),
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
        for key in out.keys {
            if key == .personalVideo {
                out[key]?.sort { $0.fileSize != $1.fileSize ? $0.fileSize > $1.fileSize : $0.creationDate > $1.creationDate }
            } else {
                out[key]?.sort { $0.creationDate > $1.creationDate }
            }
        }
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
            .onAppear {
                if let session, session.clutterVisitedAt == nil {
                    session.clutterVisitedAt = .now
                    try? context.save()
                    AppLog.info(.review, "Opened Clutter for the first time (\(Journey(session: session).clutterCount) items)")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let session, session.status != ScanStatus.applied, !rows.isEmpty {
                    NextStepBar(title: session.clutterReviewedAt == nil ? "Done with clutter · Next: Apply" : "Next: Apply") {
                        session.clutterReviewedAt = .now
                        try? context.save()
                        AppLog.info(.review, "Clutter marked reviewed (\(Journey(session: session).clutterToDelete) to delete)")
                        nav.tab = .apply
                    }
                }
            }
            .sheet(item: $selected) { decision in
                ClutterDetailSheet(decision: decision)
            }
        }
    }

    private func sectionHeader(title: String, items: [Decision]) -> some View {
        let deleting = items.filter(\.isDelete)
        let bytes = deleting.reduce(Int64(0)) { $0 + $1.fileSize }
        let total = items.reduce(Int64(0)) { $0 + $1.fileSize }
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(title) · \(items.count.formatted())").font(.headline)
                if items.first?.isVideo == true {
                    Text("\(deleting.count.formatted()) to delete · \(MediaFormat.bytes(bytes)) of \(MediaFormat.bytes(total))").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(deleting.count.formatted()) to delete").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Select all") { Review.setAll(items, to: .delete, context: context) }
                .disabled(deleting.count == items.count)
            Button("Deselect all") { Review.setAll(items, to: .keep, context: context) }
                .disabled(deleting.isEmpty)
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
                HStack(spacing: 4) {
                    if decision.isProtected {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                    if decision.isVideo {
                        Image(systemName: "play.fill")
                        Text("\(MediaFormat.clock(decision.duration)) · \(MediaFormat.bytes(decision.fileSize))")
                    }
                }
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(4)
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
                if decision.isVideo {
                    VideoPlayerView(id: decision.assetID)
                        .frame(maxHeight: .infinity)
                } else {
                    AssetImage(id: decision.assetID)
                        .frame(maxHeight: .infinity)
                        .background(Color.black)
                }
                Form {
                    LabeledContent("Category", value: decision.category)
                    LabeledContent("Reason", value: decision.reason)
                    if decision.isVideo {
                        LabeledContent("Length", value: MediaFormat.clock(decision.duration))
                        LabeledContent("Size", value: MediaFormat.bytes(decision.fileSize))
                    }
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
