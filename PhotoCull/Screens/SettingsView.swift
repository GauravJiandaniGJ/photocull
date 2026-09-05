import PhotoCullCore
import SwiftData
import SwiftUI

enum ClaudeModel: String, CaseIterable, Identifiable {
    case sonnet = "claude-sonnet-5"
    case haiku = "claude-haiku-4-5-20251001"

    var id: String { rawValue }
    var label: String { self == .sonnet ? "Sonnet 5 (default)" : "Haiku 4.5 (cheaper)" }
}

struct SettingsView: View {
    @Environment(ThresholdsStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query private var cached: [AssetRecord]
    @Query(sort: \ScanSession.createdAt, order: .reverse) private var sessions: [ScanSession]
    @AppStorage("claude.enabled") private var claudeEnabled = false
    @AppStorage("claude.model") private var claudeModel = ClaudeModel.sonnet.rawValue
    @State private var apiKeyDraft = ""
    @State private var hasStoredKey = KeychainStore.read(KeychainStore.claudeAPIKey) != nil
    @State private var confirmClearCache = false
    @State private var showDebug = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("Thresholds") {
                    ThresholdRow("Time gap (s)", value: $store.thresholds.groupTimeGapSeconds, default: Thresholds.default.groupTimeGapSeconds)
                    ThresholdRow("Similarity distance max", value: $store.thresholds.similarityDistanceMax, default: Thresholds.default.similarityDistanceMax)
                    ThresholdRow("Tie-break margin", value: $store.thresholds.tieBreakMargin, default: Thresholds.default.tieBreakMargin)
                    ThresholdRow("Min face area", value: $store.thresholds.minFaceAreaRatio, default: Thresholds.default.minFaceAreaRatio)
                    ThresholdRow("Text-heavy chars", value: $store.thresholds.textHeavyCharCount, default: Thresholds.default.textHeavyCharCount)
                    ThresholdRow("Vision long edge", value: $store.thresholds.visionLongEdge, default: Thresholds.default.visionLongEdge)
                    ThresholdRow("Claude image long edge", value: $store.thresholds.claudeImageLongEdge, default: Thresholds.default.claudeImageLongEdge)
                    ThresholdRow("Claude max images", value: $store.thresholds.claudeMaxImagesPerGroup, default: Thresholds.default.claudeMaxImagesPerGroup)
                    Button("Reset all to defaults", role: .destructive) { store.reset() }
                }

                Section {
                    TextField("Album title", text: $store.thresholds.whatsAppAlbumName)
                        .autocorrectionDisabled()
                } header: {
                    Text("WhatsApp album")
                } footer: {
                    Text("The album WhatsApp creates with “Save to Camera Roll”. Check the exact title in Photos on this phone.")
                }

                Section("Claude tie-breaker") {
                    Toggle("Use Claude for ties", isOn: $claudeEnabled)
                    Picker("Model", selection: $claudeModel) {
                        ForEach(ClaudeModel.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    SecureField(hasStoredKey ? "Key stored — enter a new one to replace" : "API key", text: $apiKeyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Button("Save key") { saveKey() }
                            .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        Spacer()
                        if hasStoredKey {
                            Button("Remove key", role: .destructive) { removeKey() }
                        }
                    }
                }

                Section("Analysis cache") {
                    LabeledContent("Cached photos", value: cached.count, format: .number)
                    Button("Clear analysis cache", role: .destructive) { confirmClearCache = true }
                        .disabled(cached.isEmpty)
                }

                Section("Scan history") {
                    if sessions.isEmpty {
                        Text("No scans yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(sessions, id: \.id) { s in
                            VStack(alignment: .leading) {
                                Text(s.startDate, format: .dateTime.day().month()) + Text(" – ") + Text(s.endDate, format: .dateTime.day().month().year())
                                Text("\(s.status.capitalized) · \(s.groups.count) groups · \(s.decisions.count) decisions")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    LabeledContent("Version", value: Self.versionString)
                        .onLongPressGesture(minimumDuration: 1) { showDebug = true }
                } footer: {
                    Text("Long-press the version for debug tools.")
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(isPresented: $showDebug) { DebugView() }
            .confirmationDialog("Clear the analysis cache?", isPresented: $confirmClearCache, titleVisibility: .visible) {
                Button("Clear \(cached.count) cached results", role: .destructive) { clearCache() }
            } message: {
                Text("The next scan will re-analyse every photo in its range. No photos are affected.")
            }
        }
    }

    private static var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    private func saveKey() {
        do {
            try KeychainStore.write(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines), account: KeychainStore.claudeAPIKey)
            apiKeyDraft = ""
            hasStoredKey = true
        } catch {
            // Surfaced in milestone 5 with the rest of the Claude UI.
        }
    }

    private func removeKey() {
        KeychainStore.delete(KeychainStore.claudeAPIKey)
        hasStoredKey = false
    }

    private func clearCache() {
        for record in cached { context.delete(record) }
        try? context.save()
    }
}

/// One editable threshold with its default shown and a per-row reset.
private struct ThresholdRow<V: Equatable & LosslessStringConvertible>: View {
    let title: String
    @Binding var value: V
    let defaultValue: V

    init(_ title: String, value: Binding<V>, default defaultValue: V) {
        self.title = title
        self._value = value
        self.defaultValue = defaultValue
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                Text("Default \(String(defaultValue))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField(title, text: Binding(
                get: { String(value) },
                set: { if let v = V($0) { value = v } }
            ))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 110)
            if value != defaultValue {
                Button {
                    value = defaultValue
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Reset \(title) to default")
            }
        }
    }
}
