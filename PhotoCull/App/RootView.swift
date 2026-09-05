import SwiftUI

/// Gate on Photos access first: the app is useless with anything less than full read/write
/// (spec §2). Re-checks whenever the app comes back from Settings.
struct RootView: View {
    @State private var library = PhotoLibraryService()
    @State private var thresholds = ThresholdsStore()
    @State private var claude = ClaudeSettings()
    @State private var tieBreaker = TieBreakRunner()
    @Environment(\.scenePhase) private var scenePhase

    /// DEBUG-only: `-skipPhotosGate` as a launch argument shows the tab shell without Photos
    /// access, because `simctl privacy grant photos` does not reach PhotoKit on the simulator.
    private var gateBypassed: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-skipPhotosGate")
        #else
        return false
        #endif
    }

    var body: some View {
        Group {
            if library.access == .full || gateBypassed {
                MainTabView()
            } else {
                PhotosAccessView()
            }
        }
        .environment(library)
        .environment(thresholds)
        .environment(claude)
        .environment(tieBreaker)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { library.refreshAccess() }
        }
    }
}
