import PhotoCullCore
import SwiftData
import SwiftUI

enum RangePreset: String, CaseIterable, Identifiable {
    case threeMonths = "3 months"
    case sixMonths = "6 months"
    case custom = "Custom"

    var id: String { rawValue }
}

struct ScanView: View {
    @Environment(ScanController.self) private var scan
    @Environment(ThresholdsStore.self) private var thresholds
    @Environment(ClaudeSettings.self) private var claude
    @Query(sort: \ScanSession.createdAt, order: .reverse) private var sessions: [ScanSession]
    @AppStorage("scan.preset") private var presetRaw = RangePreset.threeMonths.rawValue
    @AppStorage("scan.includeWhatsApp") private var includeWhatsApp = true
    @AppStorage("scan.includeScreenshots") private var includeScreenshots = true
    @AppStorage("scan.includeVideos") private var includeVideos = true
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -3, to: .now) ?? .now
    @State private var customEnd = Date.now
    @State private var assetCount: Int?
    @State private var videoCount: Int?

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
        "\(presetRaw)|\(Int(range.start.timeIntervalSince1970))|\(Int(range.end.timeIntervalSince1970))"
    }

    var body: some View {
        NavigationStack {
            Form {
                if let session = sessions.first {
                    JourneyCard(session: session)
                }
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
                    LabeledContent("Videos in range") {
                        if let videoCount {
                            Text(videoCount, format: .number)
                        } else {
                            ProgressView()
                        }
                    }
                }
                .disabled(scan.isRunning)

                Section {
                    Toggle("WhatsApp album", isOn: $includeWhatsApp)
                    Toggle("Screenshots", isOn: $includeScreenshots)
                    Toggle("Videos", isOn: $includeVideos)
                    if claude.hasKey {
                        @Bindable var claude = claude
                        Toggle("Claude tie-breaker", isOn: $claude.isEnabled)
                    }
                } header: {
                    Text("Include")
                } footer: {
                    if !claude.hasKey {
                        Text("To offer the Claude tie-breaker after a scan, add an API key in Settings.")
                    } else if claude.isEnabled {
                        Text("Claude is only asked after the scan, and only after you confirm which tied groups to send.")
                    }
                }
                .disabled(scan.isRunning)

                if scan.isRunning {
                    progressSection
                } else {
                    Section {
                        Button {
                            startScan()
                        } label: {
                            Label("Scan", systemImage: "magnifyingglass")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled((assetCount ?? 0) + (includeVideos ? (videoCount ?? 0) : 0) == 0)
                    } footer: {
                        Text("Dry run: every decision is stored for review. Nothing is deleted until you press Apply.")
                    }
                }

                if let summary = scan.summary, scan.stage == .completed {
                    summarySection(summary)
                } else if scan.stage == .cancelled {
                    Section { Label("Scan cancelled. Analysed photos stay cached, so the next scan resumes from here.", systemImage: "stop.circle") }
                } else if scan.stage == .failed, let message = scan.errorMessage {
                    Section { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
            }
            .navigationTitle("Scan")
            .task(id: rangeKey) {
                let (start, end) = range
                assetCount = nil
                videoCount = nil
                let counts = await Task.detached(priority: .userInitiated) {
                    (PhotoLibraryService.assetCount(start: start, end: end, mediaType: .image),
                     PhotoLibraryService.assetCount(start: start, end: end, mediaType: .video))
                }.value
                assetCount = counts.0
                videoCount = counts.1
            }
        }
    }

    private func startScan() {
        let (start, end) = range
        scan.start(ScanController.Options(
            start: start,
            end: end,
            includeWhatsApp: includeWhatsApp,
            includeScreenshots: includeScreenshots,
            includeVideos: includeVideos,
            thresholds: thresholds.thresholds
        ))
    }

    // MARK: Progress

    private var progressSection: some View {
        Section("Scanning") {
            let p = scan.progress
            VStack(alignment: .leading, spacing: 8) {
                if scan.stage == .analysing || scan.stage == .analysingVideos, p.total > 0 {
                    ProgressView(value: Double(p.done), total: Double(p.total))
                    Text("\(scan.stage.label) \(p.done.formatted()) / \(p.total.formatted())")
                } else {
                    ProgressView()
                    Text(scan.stage.label)
                }
                HStack {
                    if let startedAt = scan.startedAt {
                        TimelineView(.periodic(from: startedAt, by: 1)) { context in
                            Text(Self.elapsed(from: startedAt, to: context.date))
                        }
                    }
                    Spacer()
                    Text("\(p.reusedFromCache.formatted()) from cache · \(p.failed.formatted()) failed")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Button("Cancel", role: .destructive) { scan.cancel() }
        }
    }

    private static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = Int(max(0, now.timeIntervalSince(start)))
        return String(format: "%d:%02d elapsed", seconds / 60, seconds % 60)
    }

    // MARK: Summary

    private func summarySection(_ s: ScanController.Summary) -> some View {
        Section {
            LabeledContent("Groups found", value: s.groups, format: .number)
            LabeledContent("Photos in groups", value: s.photosInGroups, format: .number)
            LabeledContent("Keepers", value: s.keepers, format: .number)
            LabeledContent("Screenshots", value: s.clutter[.screenshot, default: 0], format: .number)
            LabeledContent("Received (text/documents)", value: s.clutter[.receivedUtility, default: 0], format: .number)
            LabeledContent("Received photos", value: s.clutter[.receivedPhoto, default: 0], format: .number)
            LabeledContent("Documents/receipts", value: s.clutter[.utility, default: 0], format: .number)
            LabeledContent("Favorites protected", value: s.favoritesProtected, format: .number)
            if s.videos > 0 {
                LabeledContent("Videos scanned", value: s.videos, format: .number)
                LabeledContent("Video duplicates/takes", value: s.videoGroups, format: .number)
                LabeledContent("Received videos", value: s.clutter[.receivedVideo, default: 0], format: .number)
                LabeledContent("Screen recordings", value: s.clutter[.screenRecording, default: 0], format: .number)
                LabeledContent("Video space to free", value: MediaFormat.bytes(s.bytesToFree))
            }
            LabeledContent("Delete candidates") {
                Text(s.deleteCandidates, format: .number).bold()
            }
            if let session = sessions.first, session.id == s.sessionID {
                TieBreakButton(session: session)
            }
        } header: {
            Text("Last scan")
        } footer: {
            let p = scan.progress
            Text("\(s.scanned.formatted()) photos and \(s.videos.formatted()) videos in \(Self.elapsed(from: .now.addingTimeInterval(-s.duration), to: .now).replacingOccurrences(of: " elapsed", with: "")) · \(p.fullAnalyses.formatted()) analysed, \(p.printOnly.formatted()) re-fingerprinted, \(p.reusedFromCache.formatted()) reused. Nothing has been deleted.")
        }
    }
}
