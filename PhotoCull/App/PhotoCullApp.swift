import SwiftData
import SwiftUI

@main
struct PhotoCullApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer.photoCull()
        } catch {
            fatalError("Could not open the PhotoCull database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
