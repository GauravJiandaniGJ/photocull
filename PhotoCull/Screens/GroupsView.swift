import PhotoCullCore
import SwiftData
import SwiftUI

enum GroupFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case ties = "Ties"
    case overridden = "Overridden"
    case bursts = "Bursts"

    var id: String { rawValue }
}

/// Spec §6 Groups: newest first, keeper in green, losers dimmed with a reason.
struct GroupsView: View {
    @Query(sort: \ScanSession.createdAt, order: .reverse) private var sessions: [ScanSession]
    @Environment(ScanController.self) private var scan
    @State private var filter: GroupFilter = .all
    @State private var decisionsByID: [String: Decision] = [:]

    private var session: ScanSession? { sessions.first }

    private var groups: [PhotoGroup] {
        let all = (session?.groups ?? []).sorted { $0.earliestDate > $1.earliestDate }
        switch filter {
        case .all: return all
        case .ties: return all.filter(\.isTie)
        case .overridden: return all.filter { isOverridden($0) }
        case .bursts: return all.filter { $0.kind == GroupKind.burst.rawValue }
        }
    }

    private func isOverridden(_ group: PhotoGroup) -> Bool {
        group.isUserKeeper || group.memberIDs.contains { decisionsByID[$0]?.isUserDecision == true }
    }

    var body: some View {
        NavigationStack {
            Group {
                if session?.groups.isEmpty ?? true {
                    ContentUnavailableView(
                        "No groups yet",
                        systemImage: "square.stack.3d.up",
                        description: Text("Run a scan to find near-duplicate shots of the same moment.")
                    )
                } else {
                    List {
                        Section {
                            Picker("Filter", selection: $filter) {
                                ForEach(GroupFilter.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                        Section {
                            ForEach(groups, id: \.id) { group in
                                NavigationLink(value: group.id) {
                                    GroupRow(group: group, decisions: decisionsByID)
                                }
                            }
                        } header: {
                            Text("\(groups.count.formatted()) groups")
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Groups")
            .onAppear { scan.reviewOpened = true }
            .navigationDestination(for: UUID.self) { id in
                if let group = session?.groups.first(where: { $0.id == id }) {
                    GroupDetailView(group: group, decisions: decisionsByID)
                }
            }
            .task(id: session?.id) { rebuildIndex() }
            .onChange(of: session?.decisions.count ?? 0) { _, _ in rebuildIndex() }
        }
    }

    private func rebuildIndex() {
        decisionsByID = Dictionary((session?.decisions ?? []).map { ($0.assetID, $0) }, uniquingKeysWith: { a, _ in a })
    }
}

struct GroupRow: View {
    let group: PhotoGroup
    let decisions: [String: Decision]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(group.memberIDs, id: \.self) { id in
                        MemberThumbnail(id: id, isKeeper: id == group.keeperID, decision: decisions[id], side: 88)
                    }
                }
            }
            HStack(spacing: 8) {
                Text("\(group.memberIDs.count) photos · \(group.kind) · \(group.earliestDate, format: .dateTime.day().month().year())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                if group.isTie { Tag("Tie", color: .orange) }
                if group.isUserKeeper || group.memberIDs.contains(where: { decisions[$0]?.isUserDecision == true }) {
                    Tag("Edited", color: .blue)
                }
            }
            if let keeperReason = decisions[group.keeperID]?.reason {
                Text(keeperReason).font(.footnote)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Thumbnail with keeper/delete styling for group strips.
struct MemberThumbnail: View {
    let id: String
    let isKeeper: Bool
    let decision: Decision?
    var side: CGFloat = 88

    private var isDelete: Bool { decision?.isDelete ?? false }

    var body: some View {
        AssetThumbnail(id: id, side: side)
            .opacity(isDelete ? 0.45 : 1)
            .overlay(alignment: .bottomLeading) {
                if isKeeper {
                    Badge("Keep", color: .green)
                } else if isDelete {
                    Badge("Delete", color: .red)
                } else {
                    Badge("Keep", color: .gray)
                }
            }
            .overlay(alignment: .topTrailing) {
                if decision?.isProtected == true {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow).padding(4)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isKeeper ? Color.green : Color.clear, lineWidth: 3)
            }
    }
}

struct Badge: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: Capsule())
            .foregroundStyle(.white)
            .padding(4)
    }
}

struct Tag: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
