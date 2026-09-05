import AVKit
import SwiftUI

/// Plays one PhotoKit video by local identifier.
struct VideoPlayerView: View {
    let id: String
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: id) {
            if let item = await PhotoImageLoader.playerItem(id: id) {
                player = AVPlayer(playerItem: item)
            }
        }
    }
}

/// Full-screen player with a Done button, for the review screens.
struct VideoPlayerSheet: View {
    let id: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VideoPlayerView(id: id)
                .ignoresSafeArea(edges: .bottom)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
    }
}

enum MediaFormat {
    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func bytes(_ b: Int64) -> String {
        b > 0 ? ByteCountFormatter.string(fromByteCount: b, countStyle: .file) : "size unknown"
    }
}
