import SwiftUI

/// Large (default 1024px long edge) image for the review pager.
struct AssetImage: View {
    let id: String
    var longEdge: CGFloat = 1024
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Rectangle().fill(.quaternary)
                ProgressView()
            }
        }
        .task(id: id) {
            image = await PhotoImageLoader.image(id: id, longEdge: longEdge)
        }
    }
}
