import PhotoCullCore
import SwiftData
import SwiftUI

/// "Resolve N ties with Claude" with the confirmation that gates every network call.
/// Renders nothing unless the tie-breaker is switched on and a key is stored.
struct TieBreakButton: View {
    let session: ScanSession
    @Environment(ClaudeSettings.self) private var claude
    @Environment(ThresholdsStore.self) private var store
    @Environment(TieBreakRunner.self) private var runner
    @Environment(\.modelContext) private var context
    @State private var confirming = false

    private var jobs: [TieBreakRunner.Job] { runner.jobs(in: session, thresholds: store.thresholds) }
    private var photoCount: Int { jobs.reduce(0) { $0 + $1.candidateIDs.count } }

    var body: some View {
        if claude.isAvailable {
            Group {
                switch runner.state {
                case .running(let done, let total):
                    HStack {
                        ProgressView().padding(.trailing, 6)
                        Text("Asking Claude \(done) / \(total)…")
                    }
                case .finished(let changed, let confirmed, let failed):
                    Label("Claude changed \(changed) keeper\(changed == 1 ? "" : "s"), agreed on \(confirmed), \(failed) failed.", systemImage: "sparkles")
                        .font(.footnote)
                    if !jobs.isEmpty { button }
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    if !jobs.isEmpty { button }
                case .idle:
                    if jobs.isEmpty {
                        Label("No unresolved ties for Claude.", systemImage: "sparkles").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        button
                    }
                }
            }
            .confirmationDialog(
                "Send \(photoCount) photos from \(jobs.count) tied groups to Claude?",
                isPresented: $confirming,
                titleVisibility: .visible
            ) {
                Button("Send \(photoCount) photos") { start() }
            } message: {
                Text("Downscaled copies go to Anthropic's API with your key, no names or dates. Favorites are never sent. Estimated cost about \(claude.estimatedCost(photos: photoCount, calls: jobs.count), format: .currency(code: "USD").precision(.fractionLength(2...3))) on \(claude.model.label).")
            }
        }
    }

    private var button: some View {
        Button {
            confirming = true
        } label: {
            Label("Resolve \(jobs.count) tie\(jobs.count == 1 ? "" : "s") with Claude", systemImage: "sparkles")
                .frame(maxWidth: .infinity)
        }
    }

    private func start() {
        guard let key = claude.apiKey() else { return }
        let decisions = Dictionary(session.decisions.map { ($0.assetID, $0) }, uniquingKeysWith: { a, _ in a })
        let pending = jobs
        Task {
            await runner.run(pending, apiKey: key, model: claude.model, thresholds: store.thresholds, decisions: decisions, context: context)
        }
    }
}
