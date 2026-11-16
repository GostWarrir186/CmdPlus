import AppKit
import Foundation
import Testing
@testable import CmdPlus

@Suite("Image loading")
struct ImageLoaderTests {
    private func makePNG(width: Int, height: Int) throws -> URL {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let url = FileManager.default.temporaryDirectory.appending(path: "img-\(UUID().uuidString).png")
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    @Test("Thumbnail scales to 120px, keeping aspect ratio")
    func thumbnailSize() async throws {
        let url = try makePNG(width: 3000, height: 1500)
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try #require(await ImageLoader.load(url, size: .thumbnail))
        #expect(image.width == 120)
        #expect(image.height == 60)
    }

    @Test("Large screenshot preview scales to 1000px on the long side")
    func previewSize() async throws {
        let url = try makePNG(width: 2940, height: 1912)
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try #require(await ImageLoader.load(url, size: .preview))
        #expect(max(image.width, image.height) == 1000)
    }

    @Test("Loaded images come from the cache instantly")
    func cachedAfterLoad() async throws {
        let url = try makePNG(width: 400, height: 300)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ImageLoader.cached(url, size: .thumbnail) == nil)
        _ = await ImageLoader.load(url, size: .thumbnail)
        #expect(ImageLoader.cached(url, size: .thumbnail) != nil)
        // Each size is cached separately.
        #expect(ImageLoader.cached(url, size: .preview) == nil)
    }

    @Test("Missing or broken file returns nil without crashing")
    func missingFile() async {
        let url = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).png")
        #expect(await ImageLoader.load(url, size: .preview) == nil)
    }
}
