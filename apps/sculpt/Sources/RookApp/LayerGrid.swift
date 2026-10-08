import AppKit
import RookSculpture
import SwiftUI

internal struct LayerGrid: View {
    let sculpture: Sculpture
    let layer: Int
    let column: Int
    let row: Int
    let showPreviousLayer: Bool
    let stroke: (SculptureCell, Bool) -> Void
    let finishStroke: () -> Void
    @State private var painting = false
    @State private var zoom = SliceGridZoom.fit
    @State private var canvasFrame = CGRect.zero

    init(
        sculpture: Sculpture,
        layer: Int,
        column: Int,
        row: Int,
        showPreviousLayer: Bool,
        zoom: SliceGridZoom = .fit,
        stroke: @escaping (SculptureCell, Bool) -> Void,
        finishStroke: @escaping () -> Void
    ) {
        self.sculpture = sculpture
        self.layer = layer
        self.column = column
        self.row = row
        self.showPreviousLayer = showPreviousLayer
        _zoom = State(initialValue: zoom)
        self.stroke = stroke
        self.finishStroke = finishStroke
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Grid zoom").font(.caption).foregroundStyle(Brand.secondary)
                ForEach(SliceGridZoom.allCases, id: \.self) { option in
                    Button(option.label) { zoom = option }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(zoom == option ? Brand.accent : Brand.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(zoom == option ? Brand.accent.opacity(0.12) : Brand.secondary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel("Grid zoom \(option.label)")
                        .accessibilityIdentifier("editor.slice.zoom.\(option.rawValue)")
                        .accessibilityAddTraits(zoom == option ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            GeometryReader { viewport in
                let geometry = SliceGridGeometry(
                    width: sculpture.width,
                    height: sculpture.height,
                    viewport: viewport.size,
                    zoom: zoom.scale
                )
                ScrollViewReader { scroll in
                    ScrollView([.horizontal, .vertical]) {
                        grid(geometry, viewport: viewport.size)
                            .background {
                                SliceClipBounds { frame in
                                    if canvasFrame != frame { canvasFrame = frame }
                                }.allowsHitTesting(false).accessibilityHidden(true)
                            }
                            .overlay(alignment: .topLeading) {
                                Color.clear.frame(width: 1, height: 1)
                                    .id("editor.slice.selected-anchor")
                                    .position(
                                        x: (CGFloat(column) + 0.5) * geometry.cellSize,
                                        y: (CGFloat(row) + 0.5) * geometry.cellSize
                                    )
                                    .allowsHitTesting(false).accessibilityHidden(true)
                            }
                            .frame(minWidth: viewport.size.width, minHeight: viewport.size.height)
                    }
                    .accessibilityIdentifier("editor.slice.scroll")
                    .onChange(of: zoom) { _, _ in
                        endPainting()
                        scroll.scrollTo("editor.slice.selected-anchor", anchor: .center)
                    }
                    .onChange(of: column) { _, _ in
                        if !painting, zoom != .fit { scroll.scrollTo("editor.slice.selected-anchor", anchor: .center) }
                    }
                    .onChange(of: row) { _, _ in
                        if !painting, zoom != .fit { scroll.scrollTo("editor.slice.selected-anchor", anchor: .center) }
                    }
                }
            }
        }
        .onChange(of: layer) { _, _ in endPainting() }
        .onDisappear(perform: endPainting)
    }

    private func grid(_ geometry: SliceGridGeometry, viewport: CGSize) -> some View {
        let region = SliceGridVisibleRegion(geometry: geometry, viewport: viewport, canvasOrigin: canvasFrame.origin)
        let drawingBounds = region.drawingBounds(geometry: geometry)
        return Color.clear
            .frame(width: geometry.gridSize.width, height: geometry.gridSize.height)
            .overlay(alignment: .topLeading) {
                Canvas { context, _ in
                    guard geometry.cellSize > 0 else { return }
                    context.translateBy(x: -drawingBounds.minX, y: -drawingBounds.minY)
                    let slice = sculpture.layers[layer]
                    let previous = showPreviousLayer && layer > 0 ? sculpture.layers[layer - 1] : nil
                    var emptyBackground = Path()
                    var occupiedBackground = Path()
                    for y in region.rows {
                        for x in region.columns {
                            let rect = CGRect(
                                x: CGFloat(x) * geometry.cellSize,
                                y: CGFloat(y) * geometry.cellSize,
                                width: geometry.cellSize,
                                height: geometry.cellSize
                            )
                            let glyph = slice[y * sculpture.width + x]
                            if glyph == Sculpture.empty {
                                emptyBackground.addRect(rect.insetBy(dx: 0.65, dy: 0.65))
                            } else {
                                occupiedBackground.addRect(rect.insetBy(dx: 0.65, dy: 0.65))
                            }
                        }
                    }
                    context.fill(emptyBackground, with: .color(Brand.secondary.opacity(0.06)))
                    context.fill(occupiedBackground, with: .color(Brand.accent.opacity(0.15)))
                    var glyphs = SliceGridGlyphCache()
                    for y in region.rows {
                        for x in region.columns {
                            let rect = CGRect(
                                x: CGFloat(x) * geometry.cellSize,
                                y: CGFloat(y) * geometry.cellSize,
                                width: geometry.cellSize,
                                height: geometry.cellSize
                            )
                            let glyph = slice[y * sculpture.width + x]
                            if glyph != Sculpture.empty {
                                context.draw(
                                    glyphs.text(for: glyph, previous: false, size: geometry.cellSize, context: context),
                                    at: CGPoint(x: rect.midX, y: rect.midY)
                                )
                            } else if let previous, previous[y * sculpture.width + x] != Sculpture.empty {
                                context.draw(
                                    glyphs.text(
                                        for: previous[y * sculpture.width + x],
                                        previous: true,
                                        size: geometry.cellSize,
                                        context: context
                                    ),
                                    at: CGPoint(x: rect.midX, y: rect.midY)
                                )
                            }
                            if x == column && y == row {
                                context.stroke(
                                    Path(rect.insetBy(dx: 1, dy: 1)),
                                    with: .color(Brand.accent),
                                    lineWidth: 2
                                )
                            }
                        }
                    }
                }
                .frame(width: drawingBounds.width, height: drawingBounds.height)
                // Place the bounded drawing in layout coordinates. A render-only offset leaves its layout
                // rectangle at the document origin, where ScrollView may cull it after the user scrolls away.
                .padding(.leading, drawingBounds.minX)
                .padding(.top, drawingBounds.minY)
                .frame(width: geometry.gridSize.width, height: geometry.gridSize.height, alignment: .topLeading)
                .allowsHitTesting(false).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard let cell = geometry.cell(at: value.location, layer: layer) else { return }
                        let beginsStroke = !painting
                        painting = true
                        stroke(cell, beginsStroke)
                    }
                    .onEnded { _ in endPainting() }
            )
            .onHover { hovering in
                if hovering { NSCursor.crosshair.set() } else { NSCursor.arrow.set() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Editable slice \(layer + 1). Selected cell \(column + 1), \(row + 1).")
            .accessibilityIdentifier("editor.slice.grid")
            .accessibilityHint(
                "Drag to draw or erase. Zoom and scroll to reach other cells. Use the selected-cell controls for keyboard editing."
            )
    }

    private func endPainting() {
        painting = false
        finishStroke()
    }

}

/// Read the actual native clip bounds: SwiftUI preferences do not cross every macOS scroll hosting boundary.
@MainActor
internal struct SliceClipBounds: NSViewRepresentable {
    let changed: @MainActor (CGRect) -> Void

    func makeNSView(context: Context) -> SliceClipBoundsView {
        let view = SliceClipBoundsView(frame: .zero)
        view.changed = changed
        return view
    }

    func updateNSView(_ view: SliceClipBoundsView, context: Context) {
        view.changed = changed
        view.scheduleMeasurement()
    }

    static func dismantleNSView(_ view: SliceClipBoundsView, coordinator: ()) {
        NotificationCenter.default.removeObserver(view)
        view.changed = { _ in }
    }
}

@MainActor
internal final class SliceClipBoundsView: NSView {
    var changed: @MainActor (CGRect) -> Void = { _ in }
    private weak var clip: NSClipView?
    private var pendingMeasurement = false

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        connectClip()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        connectClip()
    }

    override func layout() {
        super.layout()
        connectClip()
        scheduleMeasurement()
    }

    func scheduleMeasurement() {
        guard !pendingMeasurement else { return }
        pendingMeasurement = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            pendingMeasurement = false
            guard let clip, window != nil else { return }
            let frame = convert(bounds, to: clip)
            changed(frame.offsetBy(dx: -clip.bounds.minX, dy: -clip.bounds.minY))
        }
    }

    private func connectClip() {
        var ancestor = superview
        while let candidate = ancestor, !(candidate is NSClipView) { ancestor = candidate.superview }
        let next = ancestor as? NSClipView
        guard next !== clip else { return }
        NotificationCenter.default.removeObserver(self)
        clip = next
        if let next {
            next.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipBoundsChanged),
                name: NSView.boundsDidChangeNotification,
                object: next
            )
        }
        scheduleMeasurement()
    }

    @objc private func clipBoundsChanged(_ notification: Notification) { scheduleMeasurement() }
}

internal enum SliceGridZoom: String, CaseIterable {
    case fit
    case twice = "2x"
    case fourTimes = "4x"
    case eightTimes = "8x"
    case sixteenTimes = "16x"

    var label: String {
        switch self {
        case .fit: "Fit"
        case .twice: "2×"
        case .fourTimes: "4×"
        case .eightTimes: "8×"
        case .sixteenTimes: "16×"
        }
    }

    var scale: CGFloat {
        switch self {
        case .fit: 1
        case .twice: 2
        case .fourTimes: 4
        case .eightTimes: 8
        case .sixteenTimes: 16
        }
    }
}

/// Geometry is local to the canvas. Scroll offsets never enter document-coordinate hit testing.
internal struct SliceGridGeometry {
    let width: Int
    let height: Int
    let cellSize: CGFloat
    let gridSize: CGSize

    init(width: Int, height: Int, viewport: CGSize, zoom: CGFloat) {
        self.width = width
        self.height = height
        guard (1...Sculpture.maximumDimension).contains(width), (1...Sculpture.maximumDimension).contains(height),
            viewport.width.isFinite, viewport.height.isFinite, zoom.isFinite,
            viewport.width > 0, viewport.height > 0, zoom > 0
        else {
            cellSize = 0
            gridSize = .zero
            return
        }
        let scaled = min(viewport.width / CGFloat(width), viewport.height / CGFloat(height)) * zoom
        let size = CGSize(width: CGFloat(width) * scaled, height: CGFloat(height) * scaled)
        guard scaled.isFinite, size.width.isFinite, size.height.isFinite else {
            cellSize = 0
            gridSize = .zero
            return
        }
        cellSize = scaled
        gridSize = size
    }

    func cell(at location: CGPoint, layer: Int) -> SculptureCell? {
        guard cellSize > 0, (0..<Sculpture.maximumDimension).contains(layer), location.x.isFinite, location.y.isFinite,
            location.x >= 0, location.y >= 0, location.x < gridSize.width, location.y < gridSize.height
        else { return nil }
        return SculptureCell(x: Int(floor(location.x / cellSize)), y: Int(floor(location.y / cellSize)), z: layer)
    }
}

internal struct SliceThumbnail: View {
    let glyphs: [UInt8]
    let width: Int
    let height: Int
    let occupiedCount: Int
    @Environment(\.self) private var environment
    @State private var rendered: SliceThumbnailImage?

    var body: some View {
        let tint = Brand.accent.opacity(0.8).resolve(in: environment)
        let request = SliceThumbnailRequest(
            glyphs: glyphs,
            width: width,
            height: height,
            occupiedCount: occupiedCount,
            red: Double(tint.red),
            green: Double(tint.green),
            blue: Double(tint.blue),
            alpha: Double(tint.opacity),
            pixelSize: 64
        )
        ZStack {
            if rendered?.request == request, let image = rendered?.image {
                Image(decorative: image, scale: 2).resizable().scaledToFit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.secondary.opacity(0.06))
        .accessibilityHidden(true)
        .task(id: request) {
            let worker = Task.detached(priority: .utility) {
                SliceThumbnailImage(request: request, image: request.image())
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled else { return }
            rendered = result
        }
    }
}
