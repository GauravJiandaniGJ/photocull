import SwiftData
import SwiftUI

@main
struct PhotoCullApp: App {
    private let container: ModelContainer
    private let scan: ScanController

    init() {
        do {
            container = try ModelContainer.photoCull()
        } catch {
            fatalError("Could not open the PhotoCull database: \(error)")
        }
        scan = ScanController(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(scan)
        }
        .modelContainer(container)
    }
}
