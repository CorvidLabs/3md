import CoreGraphics
import CoreText
import ImageIO
import RookSculpture
import UniformTypeIdentifiers

public enum SculptureRasterizer {
    public static func image(_ frame: SculptureFrame, selectedLayer: Int? = nil) -> CGImage? {
        let cellWidth = 9
        let cellHeight = 18
        let width = frame.columns * cellWidth
        let height = frame.rows * cellHeight
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        context.setFillColor(CGColor(red: 0.065, green: 0.085, blue: 0.10, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, 15, nil)
        context.setShouldAntialias(true)
        context.textMatrix = .identity

        for row in 0..<frame.rows {
            for column in 0..<frame.columns {
                guard let pixel = frame.pixels[row * frame.columns + column] else { continue }
                var character = UniChar(pixel.glyph)
                var glyph = CGGlyph()
                guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) else { continue }
                let level = CGFloat(pixel.brightness)
                let selected = pixel.cell.z == selectedLayer
                context.setFillColor(
                    selected
                        ? CGColor(red: 1 * level, green: 0.79 * level, blue: 0.44 * level, alpha: 1)
                        : CGColor(red: 0.38 * level, green: 0.96 * level, blue: 0.83 * level, alpha: 1)
                )
                var position = CGPoint(x: column * cellWidth, y: height - (row + 1) * cellHeight + 4)
                CTFontDrawGlyphs(font, &glyph, &position, 1, context)
            }
        }
        return context.makeImage()
    }

    public static func png(_ frame: SculptureFrame) -> Data? {
        guard let image = image(frame) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
