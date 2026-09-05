import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Scan", systemImage: "magnifyingglass") { ScanView() }
            Tab("Groups", systemImage: "square.stack.3d.up") { GroupsView() }
            Tab("Clutter", systemImage: "doc.text.magnifyingglass") { ClutterView() }
            Tab("Apply", systemImage: "trash") { ApplyView() }
            Tab("Settings", systemImage: "gearshape") { SettingsView() }
        }
    }
}
