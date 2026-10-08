import CoreGraphics
import Foundation
import ImageIO
import RookSculpture
import UniformTypeIdentifiers

/// A session presentation of the same glyph volume; it adds no document metadata.
public enum SculptureRenderStyle: String, CaseIterable, Identifiable, Sendable {
    case cubes = "Cubes"
    case ascii = "ASCII"
    public var id: Self { self }
}

public enum SculptureImageRenderer {
    public static func image(
        sculpture: Sculpture,
        camera: SculptureCamera,
        style: SculptureRenderStyle,
        opacity: Double = 0.35,
        width: Int = 576,
        height: Int = 648
    ) -> CGImage? {
        switch style {
        case .ascii:
            SculptureRasterizer.image(
                SculptureProjection.frame(
                    sculpture,
                    camera: camera,
                    columns: max(8, width / 9),
                    rows: max(8, height / 18)
                )
            )
        case .cubes:
            SculptureVoxelRasterizer.image(
                SculptureVoxelProjection.frame(sculpture, camera: camera, width: width, height: height),
                opacity: opacity
            )
        }
    }

    public static func png(
        sculpture: Sculpture,
        camera: SculptureCamera,
        style: SculptureRenderStyle,
        opacity: Double = 0.35
    ) -> Data? {
        guard let image = image(sculpture: sculpture, camera: camera, style: style, opacity: opacity) else {
            return nil
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
