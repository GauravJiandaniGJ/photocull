import Foundation
import SwiftData

enum LogLevel: String { case info, warning, error }
enum LogCategory: String, CaseIterable { case app, scan, review, claude, apply, settings }

/// Append-only activity log stored in SwiftData; readable in Settings → Activity log.
/// Never logs secrets (the API key is only ever reported as present/absent).
@MainActor
enum AppLog {
    static var container: ModelContainer?
    private static let keep = 3000

    static func info(_ category: LogCategory, _ message: String) { record(.info, category, message) }
    static func warning(_ category: LogCategory, _ message: String) { record(.warning, category, message) }
    static func error(_ category: LogCategory, _ message: String) { record(.error, category, message) }

    private static func record(_ level: LogLevel, _ category: LogCategory, _ message: String) {
        guard let container else { return }
        let context = container.mainContext
        context.insert(LogEntry(level: level.rawValue, category: category.rawValue, message: message))
        try? context.save()
    }

    /// Drops the oldest entries beyond `keep`. Called at launch.
    static func prune() {
        guard let container else { return }
        let context = container.mainContext
        guard let count = try? context.fetchCount(FetchDescriptor<LogEntry>()), count > keep else { return }
        // Sorted in memory: a SortDescriptor key path trips a Sendable warning here.
        if let all = try? context.fetch(FetchDescriptor<LogEntry>()) {
            for entry in all.sorted(by: { $0.at < $1.at }).prefix(count - keep) { context.delete(entry) }
            try? context.save()
        }
    }

    static func clear() {
        guard let container else { return }
        try? container.mainContext.delete(model: LogEntry.self)
        try? container.mainContext.save()
    }
}
