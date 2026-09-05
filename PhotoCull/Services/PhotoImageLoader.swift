import Photos
import UIKit

/// Image requests for analysis (1024px, high quality) and UI thumbnails (256px, cached manager).
enum PhotoImageLoader {
    private static let thumbnailManager = PHCachingImageManager()

    /// Analysis image: long edge = `longEdge`, aspect-fit, high quality, iCloud download allowed.
    static func analysisImage(for asset: PHAsset, longEdge: CGFloat) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        let longest = CGFloat(max(asset.pixelWidth, asset.pixelHeight, 1))
        let scale = min(1, longEdge / longest)
        let target = CGSize(width: CGFloat(asset.pixelWidth) * scale, height: CGFloat(asset.pixelHeight) * scale)
        return await request(asset: asset, size: target, contentMode: .aspectFit, options: options, manager: .default())
    }

    /// Square UI thumbnail through the caching manager.
    static func thumbnail(id: String, side: CGFloat = 256) async -> UIImage? {
        guard let asset = PhotoLibraryService.asset(withID: id) else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await request(asset: asset, size: CGSize(width: side, height: side), contentMode: .aspectFill, options: options, manager: thumbnailManager)
    }

    /// Full-size image data, for the EXIF probe.
    static func imageData(for asset: PHAsset) async -> Data? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .current
        let once = Locked(false)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                if once.with({ done -> Bool in defer { done = true }; return !done }) {
                    continuation.resume(returning: data)
                }
            }
        }
    }

    /// Redraws so the CGImage's pixels are upright. Vision and CIDetector then share one
    /// coordinate system (origin bottom-left, normalised) without orientation bookkeeping.
    static func uprightCGImage(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up { return image.cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }.cgImage
    }

    private static func request(asset: PHAsset, size: CGSize, contentMode: PHImageContentMode, options: PHImageRequestOptions, manager: PHImageManager) async -> UIImage? {
        let once = Locked(false)
        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            manager.requestImage(for: asset, targetSize: size, contentMode: contentMode, options: options) { image, info in
                // highQualityFormat delivers once, but never resume twice if a degraded pass sneaks in.
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                if once.with({ done -> Bool in defer { done = true }; return !done }) {
                    continuation.resume(returning: image)
                }
            }
        }
    }
}
