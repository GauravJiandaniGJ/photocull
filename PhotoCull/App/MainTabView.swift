import SwiftUI

struct MainTabView: View {
    @Environment(AppNavigation.self) private var nav

    var body: some View {
        @Bindable var nav = nav
        TabView(selection: $nav.tab) {
            Tab("Scan", systemImage: "magnifyingglass", value: AppTab.scan) { ScanView() }
            Tab("Groups", systemImage: "square.stack.3d.up", value: AppTab.groups) { GroupsView() }
            Tab("Clutter", systemImage: "doc.text.magnifyingglass", value: AppTab.clutter) { ClutterView() }
            Tab("Apply", systemImage: "trash", value: AppTab.apply) { ApplyView() }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) { SettingsView() }
        }
    }
}
