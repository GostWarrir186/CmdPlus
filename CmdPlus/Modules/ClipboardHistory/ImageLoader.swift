import CoreGraphics
import Foundation
import ImageIO

/// Downscaled history images with an in-memory cache.
///
/// Decoding a big screenshot takes tens of milliseconds, so doing it on every
/// selection change made the list stutter. Now it happens once, off the main thread.
nonisolated enum ImageLoader {
    enum Size: Int {
        /// List rows and menu bar tile.
        case thumbnail = 120
        /// Preview pane — enough for Retina.
        case preview = 1000
    }

    /// NSCache frees itself under memory pressure.
    nonisolated(unsafe) private static let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 150 * 1024 * 1024
        return cache
    }()

    private static func key(_ url: URL, _ size: Size) -> NSString {
        "\(size.rawValue)|\(url.path)" as NSString
    }

    /// Returns immediately — used for the first frame so there's no spinner flash.
    static func cached(_ url: URL, size: Size) -> CGImage? {
        cache.object(forKey: key(url, size))
    }

    static func load(_ url: URL, size: Size) async -> CGImage? {
        if let image = cached(url, size: size) { return image }
        let image = await Task.detached(priority: .userInitiated) {
            decode(url, maxPixelSize: size.rawValue)
        }.value
        if let image {
            cache.setObject(image, forKey: key(url, size), cost: image.bytesPerRow * image.height)
        }
        return image
    }

    /// Warm the cache ahead of time (e.g. neighboring items).
    static func prefetch(_ urls: [URL], size: Size) {
        let missing = urls.filter { cached($0, size: size) == nil }
        guard !missing.isEmpty else { return }
        Task.detached(priority: .utility) {
            for url in missing {
                _ = await load(url, size: size)
            }
        }
    }

    private static func decode(_ url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Decode now, in the background, instead of on first draw on the main thread.
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
