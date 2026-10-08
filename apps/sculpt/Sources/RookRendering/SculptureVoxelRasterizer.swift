import CoreGraphics
import RookSculpture

public enum SculptureVoxelRasterizer {
    /// Surface opacity affects the cubes; the selected slice remains a faint editable wire grid.
    public static func image(
        _ frame: SculptureVoxelFrame,
        opacity: Double = 0.35,
        selectedLayer: Int? = nil,
        transparentBackground: Bool = false
    ) -> CGImage? {
        guard !frame.isOverBudget else { return nil }
        guard
            let context = CGContext(
                data: nil,
                width: frame.width,
                height: frame.height,
                bitsPerComponent: 8,
                bytesPerRow: frame.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        let alpha = opacity.isFinite ? max(0, min(1, opacity)) : 0.35
        context.translateBy(x: 0, y: CGFloat(frame.height))
        context.scaleBy(x: 1, y: -1)
        if !transparentBackground {
            context.setFillColor(CGColor(red: 0.065, green: 0.085, blue: 0.10, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        }
        context.setShouldAntialias(true)
        context.setLineJoin(.round)
        for (index, quad) in frame.quads.enumerated() {
            if index.isMultiple(of: 256), Task.isCancelled { return nil }
            guard let first = quad.vertices.first else { continue }
            let path = CGMutablePath()
            path.move(to: CGPoint(x: CGFloat(first.x), y: CGFloat(first.y)))
            for vertex in quad.vertices.dropFirst() {
                path.addLine(to: CGPoint(x: CGFloat(vertex.x), y: CGFloat(vertex.y)))
            }
            path.closeSubpath()
            if quad.isEmpty {
                context.setFillColor(CGColor(red: 1, green: 0.79, blue: 0.44, alpha: 0.018))
                context.addPath(path); context.fillPath()
                context.setStrokeColor(CGColor(red: 1, green: 0.79, blue: 0.44, alpha: 0.17))
                context.setLineWidth(0.6)
            } else {
                let selected = quad.cell.z == selectedLayer
                let tint = selected ? (1.0, 0.79, 0.44) : color(for: quad.glyph ?? 35)
                let level = quad.brightness
                context.setFillColor(
                    CGColor(red: tint.0 * level, green: tint.1 * level, blue: tint.2 * level, alpha: alpha)
                )
                context.addPath(path); context.fillPath()
                context.setStrokeColor(
                    CGColor(red: tint.0, green: tint.1, blue: tint.2, alpha: max(0.16, min(0.8, alpha * 0.8)))
                )
                context.setLineWidth(selected ? 1.0 : 0.7)
            }
            context.addPath(path); context.strokePath()
        }
        return Task.isCancelled ? nil : context.makeImage()
    }

    /// Display colors correspond to the document's nine printable glyph materials.
    public static func color(for glyph: UInt8) -> (red: Double, green: Double, blue: Double) {
        switch glyph {
        case 64: (0.65, 0.57, 0.94)
        case 42: (0.98, 0.76, 0.42)
        case 43: (0.46, 0.71, 0.95)
        case 111: (0.57, 0.83, 0.49)
        case 120: (0.94, 0.54, 0.58)
        case 58: (0.52, 0.67, 0.48)
        case 61: (0.87, 0.76, 0.55)
        case 45: (0.49, 0.83, 0.89)
        default: (0.38, 0.96, 0.83)
        }
    }

    public static func name(for glyph: UInt8) -> String {
        switch glyph {
        case 64: "Violet"
        case 42: "Amber"
        case 43: "Blue"
        case 111: "Green"
        case 120: "Coral"
        case 58: "Fern"
        case 61: "Sand"
        case 45: "Cyan"
        default: "Mint"
        }
    }
}
