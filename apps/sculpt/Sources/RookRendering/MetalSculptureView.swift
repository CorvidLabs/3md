import CoreImage
import MetalKit
import RookSculpture
import SwiftUI

/// Core Image encodes its built-in rendering onto Metal. No shader source is authored by the app.
@MainActor
public struct MetalSculptureView: NSViewRepresentable {
    public let image: CGImage

    public init(image: CGImage) { self.image = image }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.delegate = context.coordinator
        context.coordinator.image = image
        return view
    }

    public func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.image = image
        view.needsDisplay = true
    }

    public static let isAvailable = MTLCreateSystemDefaultDevice() != nil

    public final class Coordinator: NSObject, MTKViewDelegate {
        let device = MTLCreateSystemDefaultDevice()
        var image: CGImage?
        private var queue: (any MTLCommandQueue)?
        private var renderer: CIContext?

        override init() {
            super.init()
            if let device {
                queue = device.makeCommandQueue()
                renderer = CIContext(mtlDevice: device)
            }
        }

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        public func draw(in view: MTKView) {
            guard let image, let drawable = view.currentDrawable,
                let command = queue?.makeCommandBuffer(), let renderer
            else { return }
            let size = view.drawableSize
            guard size.width > 0, size.height > 0 else { return }
            let scale = min(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
            let bounds = CGRect(origin: .zero, size: size)
            let background = CIImage(color: CIColor(red: 0.065, green: 0.085, blue: 0.10)).cropped(to: bounds)
            let content = CIImage(cgImage: image)
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(
                    by: CGAffineTransform(
                        translationX: (size.width - CGFloat(image.width) * scale) / 2,
                        y: (size.height - CGFloat(image.height) * scale) / 2
                    )
                )
                .composited(over: background)
            renderer.render(
                content,
                to: drawable.texture,
                commandBuffer: command,
                bounds: bounds,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            command.present(drawable)
            command.commit()
        }
    }
}
