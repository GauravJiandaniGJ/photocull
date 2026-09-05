import SwiftUI

/// 256px cached thumbnail for a PhotoKit local identifier.
struct AssetThumbnail: View {
    let id: String
    var side: CGFloat = 72
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: id) {
            image = await PhotoImageLoader.thumbnail(id: id)
        }
    }
}
