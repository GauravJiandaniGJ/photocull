import PhotoCullCore
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(ThresholdsStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query private var cached: [AssetRecord]
    @Query(sort: \ScanSession.createdAt, order: .reverse) private var sessions: [ScanSession]
    @Environment(ClaudeSettings.self) private var claude
    @State private var apiKeyDraft = ""
    @State private var keyError: String?
    @State private var connectionResult: String?
    @State private var testing = false
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

                Section {
                    @Bindable var claude = claude
                    SecureField(claude.hasKey ? "Key stored — enter a new one to replace" : "API key (sk-ant-…)", text: $apiKeyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Button("Save key") { saveKey() }
                            .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        Spacer()
                        if claude.hasKey {
                            Button("Remove key", role: .destructive) { removeKey() }
                        }
                    }
                    if claude.hasKey {
                        Toggle("Offer Claude for ties", isOn: $claude.isEnabled)
                        Picker("Model", selection: $claude.model) {
                            ForEach(ClaudeModel.allCases) { Text($0.label).tag($0) }
                        }
                        Button {
                            testConnection()
                        } label: {
                            HStack {
                                Text("Test connection")
                                if testing { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(testing)
                        if let connectionResult {
                            Text(connectionResult).font(.footnote)
                        }
                    }
                    if let keyError {
                        Text(keyError).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Claude tie-breaker")
                } footer: {
                    Text(claude.hasKey
                         ? "Only tied groups are sent, only after you confirm, with downscaled copies and no metadata. Never favorites."
                         : "Optional. Without a key the tie-breaker is not offered anywhere in the app.")
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
                            let row = VStack(alignment: .leading) {
                                Text(s.startDate, format: .dateTime.day().month()) + Text(" – ") + Text(s.endDate, format: .dateTime.day().month().year())
                                Text("\(s.status.capitalized) · \(s.groups.count) groups · \(s.decisions.count) decisions")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            if s.status == ScanStatus.applied {
                                NavigationLink { AuditDetailView(session: s) } label: { row }
                            } else {
                                row
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
            try claude.saveKey(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
            apiKeyDraft = ""
            keyError = nil
            connectionResult = nil
        } catch {
            keyError = "Could not store the key: \(error.localizedDescription)"
        }
    }

    private func removeKey() {
        claude.removeKey()
        connectionResult = nil
    }

    private func testConnection() {
        guard let key = claude.apiKey() else { return }
        testing = true
        connectionResult = nil
        let model = claude.model.rawValue
        Task {
            let result = await ClaudeTieBreaker.checkModel(model, apiKey: key)
            switch result {
            case .success(let name): connectionResult = "OK: key accepted, model \(name) available."
            case .failure(let error): connectionResult = "Failed: \(error.localizedDescription)"
            }
            testing = false
        }
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

    /// "120" rather than "120.0" for whole-number doubles; everything else as-is.
    private static func display(_ v: V) -> String {
        let text = String(v)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                Text("Default \(Self.display(defaultValue))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField(title, text: Binding(
                get: { Self.display(value) },
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
