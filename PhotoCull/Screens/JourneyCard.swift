import SwiftData
import SwiftUI

/// "Where am I" for the latest session, with a Continue button that jumps to the right tab.
struct JourneyCard: View {
    let session: ScanSession
    @Environment(AppNavigation.self) private var nav

    private var journey: Journey { Journey(session: session) }

    var body: some View {
        Section {
            ForEach(JourneyStep.allCases) { step in
                let state = journey.state(of: step)
                HStack(spacing: 12) {
                    Image(systemName: icon(for: state))
                        .foregroundStyle(color(for: state))
                        .font(.title3)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .fontWeight(state == .current ? .semibold : .regular)
                            .foregroundStyle(state == .pending ? .secondary : .primary)
                        Text(journey.detail(for: step))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if state == .current && !journey.isApplied {
                        Button("Continue") { nav.tab = step.tab }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    } else if state == .done && step != .scan {
                        Button("Open") { nav.tab = step.tab }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text(journey.isApplied ? "Last session" : "Your progress")
        } footer: {
            if journey.isApplied {
                Text("Photos are in Recently Deleted for 30 days. Scan again whenever you like; only new photos are analysed.")
            } else {
                Text("Come back any time. Your keeps and deletes are saved as you go.")
            }
        }
    }

    private func icon(for state: JourneyState) -> String {
        switch state {
        case .done: return "checkmark.circle.fill"
        case .current: return "arrow.right.circle.fill"
        case .pending: return "circle.dashed"
        }
    }

    private func color(for state: JourneyState) -> Color {
        switch state {
        case .done: return .green
        case .current: return .accentColor
        case .pending: return .secondary
        }
    }
}

/// Bottom bar with the journey's next step, for Groups and Clutter.
struct NextStepBar: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "arrow.right.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
