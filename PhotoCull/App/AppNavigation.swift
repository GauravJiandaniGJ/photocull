import Foundation
import Observation

enum AppTab: Hashable {
    case scan, groups, clutter, apply, settings
}

/// Selected tab, so the journey card and "Next" buttons can move the user along.
@MainActor
@Observable
final class AppNavigation {
    var tab: AppTab = .scan
}
