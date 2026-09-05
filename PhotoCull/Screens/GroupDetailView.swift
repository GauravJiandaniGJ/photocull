import PhotoCullCore
import SwiftData
import SwiftUI

/// Full-width pager to compare a group's photos, with score breakdown and overrides.
struct GroupDetailView: View {
    @Bindable var group: PhotoGroup
    let decisions: [String: Decision]
    @Environment(\.modelContext) private var context
    @State private var selection: String

    init(group: PhotoGroup, decisions: [String: Decision]) {
        self.group = group
        self.decisions = decisions
        _selection = State(initialValue: group.keeperID)
    }

    private var index: Int { group.memberIDs.firstIndex(of: selection) ?? 0 }
    private var current: Decision? { decisions[selection] }
    private var isKeeper: Bool { selection == group.keeperID }
    private var score: MemberScore? { group.scores.first { $0.assetID == selection } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TabView(selection: $selection) {
                    ForEach(group.memberIDs, id: \.self) { id in
                        AssetImage(id: id)
                            .tag(id)
                            .onLongPressGesture { toggleCurrent(id) }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(height: 440)
                .background(Color.black)

                HStack(spacing: 8) {
                    ForEach(group.memberIDs, id: \.self) { id in
                        MemberThumbnail(id: id, isKeeper: id == group.keeperID, decision: decisions[id], side: 56)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(id == selection ? Color.accentColor : Color.clear, lineWidth: 2)
                            }
                            .onTapGesture { selection = id }
                    }
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if isKeeper {
                            Badge("Keep", color: .green)
                        } else if current?.isDelete == true {
                            Badge("Delete", color: .red)
                        } else {
                            Badge("Keep", color: .gray)
                        }
                        Text(current?.reason ?? "")
                        Spacer()
                    }
                    if let claudeReason = group.claudeReason {
                        Label(claudeReason, systemImage: "sparkles").font(.footnote)
                    }
                    if let score {
                        scoreBreakdown(score)
                    }
                    actions
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle("\(index + 1) of \(group.memberIDs.count)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("Keep all") { Review.keepAll(in: group, decisions: decisions, context: context) }
                Button("Delete all but keeper", role: .destructive) { Review.deleteAllButKeeper(in: group, decisions: decisions, context: context) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private func scoreBreakdown(_ s: MemberScore) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Score", value: s.score, format: .number.precision(.fractionLength(2)))
            LabeledContent("Aesthetics", value: s.aesthetics, format: .number.precision(.fractionLength(2)))
            if let fq = s.faceQuality {
                LabeledContent("Face quality", value: fq, format: .number.precision(.fractionLength(2)))
                LabeledContent("Faces") {
                    HStack(spacing: 6) {
                        Text("\(s.faceCount)")
                        Image(systemName: s.closedEyesFaceCount == 0 ? "eye" : "eye.slash")
                            .foregroundStyle(s.closedEyesFaceCount == 0 ? .green : .red)
                        Text("\(s.faceCount - s.closedEyesFaceCount)/\(s.faceCount) eyes open")
                        if let smile = s.smileFraction {
                            Image(systemName: "face.smiling").foregroundStyle(smile > 0 ? .green : .secondary)
                            Text("\(Int((smile * Float(s.faceCount)).rounded())) smiling")
                        }
                    }
                }
            } else {
                LabeledContent("Faces", value: "none")
            }
            LabeledContent("Resolution", value: s.resolution == 1 ? "highest in group" : "lower")
            if s.isFavorite { LabeledContent("Favorite", value: "protected") }
        }
        .font(.subheadline)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            if !isKeeper {
                Button {
                    Review.makeKeeper(selection, in: group, decisions: decisions, context: context)
                } label: {
                    Label("Make keeper", systemImage: "checkmark.seal").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(role: current?.isDelete == true ? nil : .destructive) {
                    toggleCurrent(selection)
                } label: {
                    Label(current?.isDelete == true ? "Keep this photo" : "Delete this photo",
                          systemImage: current?.isDelete == true ? "arrow.uturn.backward" : "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(current?.isProtected == true && current?.isDelete == false)
            } else {
                Text("This is the keeper. To delete it, make another photo the keeper first.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private func toggleCurrent(_ id: String) {
        guard let decision = decisions[id] else { return }
        Review.toggle(decision, in: group, context: context)
    }
}
