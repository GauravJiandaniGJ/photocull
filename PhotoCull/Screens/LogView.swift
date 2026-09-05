import SwiftData
import SwiftUI

/// Settings → Activity log: what the app did, newest first.
struct LogView: View {
    @Query(sort: \LogEntry.at, order: .reverse) private var entries: [LogEntry]
    @State private var filter: String = "all"
    @State private var confirmClear = false
    @State private var exportURL: URL?

    private var shown: [LogEntry] {
        let base = filter == "all" ? entries : entries.filter { $0.category == filter }
        return Array(base.prefix(500))
    }

    var body: some View {
        List {
            Section {
                Picker("Category", selection: $filter) {
                    Text("All").tag("all")
                    ForEach(LogCategory.allCases, id: \.rawValue) { Text($0.rawValue.capitalized).tag($0.rawValue) }
                }
                .pickerStyle(.menu)
            }
            Section("\(shown.count.formatted()) of \(entries.count.formatted()) entries") {
                if shown.isEmpty {
                    Text("Nothing logged yet.").foregroundStyle(.secondary)
                }
                ForEach(shown, id: \.id) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: symbol(entry.level))
                            .foregroundStyle(color(entry.level))
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.message)
                            Text("\(entry.category) · \(entry.at, format: .dateTime.day().month().hour().minute().second())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Activity log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let exportURL {
                    ShareLink(item: exportURL) { Image(systemName: "square.and.arrow.up") }
                } else {
                    Button { export() } label: { Image(systemName: "square.and.arrow.up") }
                        .disabled(entries.isEmpty)
                }
                Button(role: .destructive) { confirmClear = true } label: { Image(systemName: "trash") }
                    .disabled(entries.isEmpty)
            }
        }
        .confirmationDialog("Clear the activity log?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear \(entries.count.formatted()) entries", role: .destructive) { AppLog.clear() }
        }
    }

    private func export() {
        let formatter = ISO8601DateFormatter()
        let text = entries.reversed().map { "\(formatter.string(from: $0.at))\t\($0.level)\t\($0.category)\t\($0.message)" }.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("photocull-activity.tsv")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        exportURL = url
    }

    private func symbol(_ level: String) -> String {
        switch level {
        case LogLevel.error.rawValue: return "xmark.octagon.fill"
        case LogLevel.warning.rawValue: return "exclamationmark.triangle.fill"
        default: return "info.circle"
        }
    }

    private func color(_ level: String) -> Color {
        switch level {
        case LogLevel.error.rawValue: return .red
        case LogLevel.warning.rawValue: return .orange
        default: return .secondary
        }
    }
}
