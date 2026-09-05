import SwiftUI

struct PhotosAccessView: View {
    @Environment(PhotoLibraryService.self) private var library
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("PhotoCull needs full access to your photos")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            actionButton
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(32)
    }

    private var message: String {
        switch library.access {
        case .notDetermined:
            return "Everything runs on this phone. Photos never leave the device unless you turn on the Claude tie-breaker in Settings."
        case .limited:
            return "Limited access is not enough: PhotoCull has to see every photo in a date range to find duplicates. Switch to Full Access in Settings."
        case .denied, .restricted:
            return "Photo access is off. Turn on Full Access for PhotoCull in Settings → Privacy & Security → Photos."
        case .full:
            return ""
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if library.access == .notDetermined {
            Button("Allow Full Access") {
                Task { await library.requestAccess() }
            }
        } else {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        }
    }
}
