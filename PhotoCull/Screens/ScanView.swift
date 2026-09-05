import SwiftUI

enum RangePreset: String, CaseIterable, Identifiable {
    case threeMonths = "3 months"
    case sixMonths = "6 months"
    case custom = "Custom"

    var id: String { rawValue }
}

struct ScanView: View {
    @AppStorage("scan.preset") private var presetRaw = RangePreset.threeMonths.rawValue
    @AppStorage("scan.includeWhatsApp") private var includeWhatsApp = true
    @AppStorage("scan.includeScreenshots") private var includeScreenshots = true
    @AppStorage("claude.enabled") private var claudeEnabled = false
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -3, to: .now) ?? .now
    @State private var customEnd = Date.now
    @State private var assetCount: Int?

    private var preset: RangePreset { RangePreset(rawValue: presetRaw) ?? .threeMonths }

    /// Half-open [start, end) to match the PhotoKit predicate.
    private var range: (start: Date, end: Date) {
        let cal = Calendar.current
        switch preset {
        case .threeMonths:
            return (cal.date(byAdding: .month, value: -3, to: .now) ?? .now, .now)
        case .sixMonths:
            return (cal.date(byAdding: .month, value: -6, to: .now) ?? .now, .now)
        case .custom:
            let start = cal.startOfDay(for: customStart)
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: customEnd)) ?? customEnd
            return (start, end)
        }
    }

    private var rangeKey: String {
        "\(presetRaw)|\(range.start.timeIntervalSince1970)|\(range.end.timeIntervalSince1970)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date range") {
                    Picker("Range", selection: $presetRaw) {
                        ForEach(RangePreset.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    if preset == .custom {
                        DatePicker("From", selection: $customStart, in: ...customEnd, displayedComponents: .date)
                        DatePicker("To", selection: $customEnd, in: customStart..., displayedComponents: .date)
                    }
                    LabeledContent("Photos in range") {
                        if let assetCount {
                            Text(assetCount, format: .number)
                        } else {
                            ProgressView()
                        }
                    }
                }

                Section("Include") {
                    Toggle("WhatsApp album", isOn: $includeWhatsApp)
                    Toggle("Screenshots", isOn: $includeScreenshots)
                    Toggle("Claude tie-breaker", isOn: $claudeEnabled)
                }

                Section {
                    // Milestone 1 wires this to AnalysisService. Nothing is ever deleted from here (safety rule 1).
                    Button {
                    } label: {
                        Label("Scan", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(true)
                } footer: {
                    Text("The analysis pipeline is not built yet (milestone 1). Scanning is a dry run: nothing is deleted until you press Apply.")
                }
            }
            .navigationTitle("Scan")
            .task(id: rangeKey) {
                let (start, end) = range
                assetCount = nil
                assetCount = await Task.detached(priority: .userInitiated) {
                    PhotoLibraryService.assetCount(start: start, end: end)
                }.value
            }
        }
    }
}
