import CoreGraphics
import CoreImage
import ImageIO
import Metal
import RookRendering
import RookSculpture
import Testing

@Test func imageExportHasExpectedDimensionsAndDecodesAsPNG() throws {
    let frame = SculptureProjection.frame(.orb(), camera: SculptureCamera())
    let png = try #require(SculptureRasterizer.png(frame))
    #expect(Array(png.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
    let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == frame.columns * 9)
    #expect(image.height == frame.rows * 18)
}

@Test func glyphRasterDiffersFromEmptyVolume() throws {
    let orb = SculptureProjection.frame(.orb(), camera: SculptureCamera())
    let empty = SculptureProjection.frame(.blank(), camera: SculptureCamera())
    #expect(try #require(SculptureRasterizer.png(orb)) != #require(SculptureRasterizer.png(empty)))
}

@Test func metalBackendCompletesAndWritesVisibleGlyphs() async throws {
    let device = try #require(
        MTLCreateSystemDefaultDevice(),
        "A native Metal device is required for this rendering check."
    )
    let queue = try #require(device.makeCommandQueue())
    let command = try #require(queue.makeCommandBuffer())
    let image = try #require(SculptureRasterizer.image(SculptureProjection.frame(.orb(), camera: SculptureCamera())))
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm,
        width: image.width,
        height: image.height,
        mipmapped: false
    )
    descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
    descriptor.storageMode = .shared
    let texture = try #require(device.makeTexture(descriptor: descriptor))
    let renderer = CIContext(mtlDevice: device)
    renderer.render(
        CIImage(cgImage: image),
        to: texture,
        commandBuffer: command,
        bounds: CGRect(x: 0, y: 0, width: image.width, height: image.height),
        colorSpace: CGColorSpaceCreateDeviceRGB()
    )
    let completed = await withCheckedContinuation { continuation in
        command.addCompletedHandler { result in continuation.resume(returning: result.status == .completed) }
        command.commit()
    }
    #expect(completed)
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    pixels.withUnsafeMutableBytes { buffer in
        texture.getBytes(
            buffer.baseAddress!,
            bytesPerRow: image.width * 4,
            from: MTLRegionMake2D(0, 0, image.width, image.height),
            mipmapLevel: 0
        )
    }
    let brightGlyphs = stride(from: 0, to: pixels.count, by: 4).filter {
        Int(pixels[$0 + 1]) > Int(pixels[$0]) * 2 && pixels[$0 + 1] > 100
    }
    #expect(brightGlyphs.count > 100)
}
