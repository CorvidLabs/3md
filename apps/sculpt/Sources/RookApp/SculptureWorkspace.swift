import Foundation
import Observation
import RookRendering
import RookSculpture

internal enum SculptureEditingTool: String, CaseIterable, Identifiable {
    case draw = "Draw", erase = "Erase", fill = "Fill"
    var id: Self { self }
}

internal enum SculptureViewpoint: String, CaseIterable, Identifiable {
    case perspective = "Orbit", front = "Front", side = "Side", above = "Above"
    var id: Self { self }
}

@MainActor
@Observable
internal final class SculptureWorkspace {
    var sculpture = Sculpture.orb() {
        didSet {
            // Shared copy-on-write layer storage makes metadata-only changes cheap to recognize.
            if oldValue.width != sculpture.width || oldValue.height != sculpture.height
                || oldValue.layers != sculpture.layers
            {
                sculptureRevision = UUID()
                handedOverGeometry = nil
            }
        }
    }
    /// Cube geometry a gallery opening prepared away from the main actor, keyed by the revision it was made for.
    /// The canvas installs it instead of extracting the same volume again. Any voxel change drops it.
    @ObservationIgnored private var handedOverGeometry: (revision: UUID, geometry: SculpturePreparedGeometry)?
    var titleDraft = "Character orb"
    var layer = 8
    var column = 0
    var row = 0
    var brush: UInt8 = 35
    var tool = SculptureEditingTool.draw
    var brushSize = 1
    var showPreviousLayer = false
    var camera = SculptureCamera()
    var viewpoint = SculptureViewpoint.perspective
    var renderStyle = SculptureRenderStyle.cubes
    var paintsIn3D = false
    var cubeOpacity = 0.35
    private(set) var documentGeneration = UUID()
    /// Camera and selection changes never invalidate the camera-independent cube mesh.
    private(set) var sculptureRevision = UUID()
    var error: String?
    /// A reference draft is separate from the editable voxel document's saved baseline.
    var referenceDraftIsDirty = false
    /// True while a composition, world, gallery or export sheet covers this document. Menu Undo and Redo then
    /// never change this hidden sculpture.
    var hasOpenSheet = false
    var message = "Drag to orbit. Choose Paint to sculpt cubes."
    private var undoStates: [Sculpture] = []
    private var redoStates: [Sculpture] = []
    private var saved: Sculpture?
    private var strokeStart: Sculpture?
    private var previousCell: SculptureCell?

    var erase: Bool {
        get { tool == .erase }
        set { tool = newValue ? .erase : .draw }
    }
    var canUndo: Bool { !undoStates.isEmpty }
    var canRedo: Bool { !redoStates.isEmpty }
    var isDirty: Bool { titleDraft != sculpture.title || (saved.map { $0 != sculpture } ?? canUndo) }
    var frame: SculptureFrame { SculptureProjection.frame(sculpture, camera: camera) }
    var titleValidation: String? {
        guard !titleDraft.isEmpty, titleDraft.utf8.count <= 80,
            titleDraft.utf8.allSatisfy({ (32...126).contains($0) })
        else { return "Use 1–80 printable ASCII characters." }
        return nil
    }

    @discardableResult
    func commitTitle() -> Bool {
        guard titleValidation == nil else { return false }
        guard titleDraft != sculpture.title else { return true }
        let title = titleDraft
        execute(.rename(title: title))
        return sculpture.title == title
    }

    func paint(_ cell: SculptureCell, start: Bool, size: Int? = nil) {
        guard sculpture.glyph(at: cell) != nil else { return }
        if start {
            strokeStart = sculpture
            previousCell = nil
        }
        column = cell.x
        row = cell.y
        if tool == .fill {
            if start { floodFill(cell) }
            return
        }
        let points = line(from: previousCell ?? cell, to: cell)
        previousCell = cell
        let radius = max(0, min(2, (size ?? brushSize) / 2))
        let glyph = erase ? Sculpture.empty : brush
        for point in points {
            for y in (point.y - radius)...(point.y + radius) {
                for x in (point.x - radius)...(point.x + radius) {
                    let target = SculptureCell(x: x, y: y, z: point.z)
                    guard let current = sculpture.glyph(at: target), current != glyph else { continue }
                    rememberStroke()
                    sculpture.paint(target, glyph: glyph)
                }
            }
        }
    }

    func endStroke() {
        strokeStart = nil
        previousCell = nil
    }

    /// Surface gestures keep their original hit frame throughout a stroke, preventing
    /// a freshly added cube from pushing the next event into another depth slice.
    @discardableResult
    func paintVoxel(_ hit: SculptureVoxelHit, start: Bool) -> Bool {
        let target = tool == .draw ? hit.paintCell : hit.cell
        guard let target, sculpture.glyph(at: target) != nil else { return false }
        if tool == .erase && hit.isEmpty { return false }
        layer = target.z
        paint(target, start: start, size: 1)
        message = "\(tool.rawValue) cube at \(target.x + 1), \(target.y + 1), \(target.z + 1)."
        return true
    }

    func clearLayer() {
        execute(.clearSlice(z: layer))
    }

    func rotateLayer() {
        execute(.rotateSlice(z: layer, quarterTurns: 1))
    }

    func execute(_ command: SculptureCommand) {
        change { $0 = try SculptureCommandEngine.apply(command, to: $0) }
        if case .rename = command { titleDraft = sculpture.title }
    }

    func execute(_ batch: SculptureCommandBatch) {
        let previousTitle = sculpture.title
        change { $0 = try SculptureCommandEngine.apply(batch, to: $0) }
        if sculpture.title != previousTitle { titleDraft = sculpture.title }
    }

    func select(_ cell: SculptureCell) {
        guard sculpture.glyph(at: cell) != nil else { return }
        endStroke()
        layer = cell.z
        column = cell.x
        row = cell.y
        message = "Selected cell \(cell.x + 1), \(cell.y + 1) in slice \(cell.z + 1)."
    }

    func setViewpoint(_ viewpoint: SculptureViewpoint) {
        self.viewpoint = viewpoint
        switch viewpoint {
        case .perspective: camera = SculptureCamera()
        case .front: camera = SculptureCamera(yaw: 0, pitch: 0, zoom: camera.zoom)
        case .side: camera = SculptureCamera(yaw: .pi / 2, pitch: 0, zoom: camera.zoom)
        case .above: camera = SculptureCamera(yaw: 0, pitch: 1.4, zoom: camera.zoom)
        }
    }

    func change(_ action: (inout Sculpture) throws -> Void) {
        endStroke()
        do {
            var next = sculpture
            try action(&next)
            guard next != sculpture else { return }
            remember()
            sculpture = next
            clampSelection()
        } catch { self.error = error.localizedDescription }
    }

    func undo() {
        endStroke()
        guard let state = undoStates.popLast() else { return }
        redoStates.append(sculpture)
        sculpture = state
        titleDraft = state.title
        clampSelection()
    }

    func redo() {
        endStroke()
        guard let state = redoStates.popLast() else { return }
        undoStates.append(sculpture)
        sculpture = state
        titleDraft = state.title
        clampSelection()
    }

    /// Geometry handed over for `revision`, or nil when none was prepared for exactly that volume.
    func preparedGeometry(for revision: UUID) -> SculpturePreparedGeometry? {
        handedOverGeometry?.revision == revision ? handedOverGeometry?.geometry : nil
    }

    func replace(
        with sculpture: Sculpture,
        opened: Bool = false,
        preparedGeometry: SculpturePreparedGeometry? = nil
    ) {
        endStroke()
        documentGeneration = UUID()
        self.sculpture = sculpture
        handedOverGeometry = preparedGeometry.flatMap { geometry in
            geometry.matches(sculpture) ? (sculptureRevision, geometry) : nil
        }
        titleDraft = sculpture.title
        layer = sculpture.depth / 2
        column = 0
        row = 0
        undoStates = []
        redoStates = []
        saved = opened ? sculpture : nil
        camera = SculptureCamera()
        viewpoint = .perspective
        message = opened ? "Opened \(sculpture.title)." : "Drag to orbit. Choose Paint to sculpt cubes."
    }

    func markSaved(_ snapshot: Sculpture) {
        saved = snapshot
        message = "Saved \(snapshot.title) as 3md."
    }

    func markSaved(_ prepared: SculpturePreparedSave) {
        guard prepared.documentGeneration == documentGeneration else { return }
        saved = prepared.sculpture
        message = "Saved \(prepared.sculpture.title) as .\(prepared.format.fileExtension)."
    }

    private func floodFill(_ seed: SculptureCell) {
        do {
            let next = try SculptureCommandEngine.apply(
                .fill(x: seed.x, y: seed.y, z: seed.z, glyph: String(UnicodeScalar(brush))),
                to: sculpture
            )
            guard next != sculpture else { return }
            rememberStroke()
            sculpture = next
        } catch { self.error = error.localizedDescription }
    }

    private func line(from start: SculptureCell, to end: SculptureCell) -> [SculptureCell] {
        guard start.z == end.z else { return [end] }
        var x = start.x
        var y = start.y
        let dx = abs(end.x - x)
        let dy = -abs(end.y - y)
        let sx = x < end.x ? 1 : -1
        let sy = y < end.y ? 1 : -1
        var error = dx + dy
        var result: [SculptureCell] = []
        while true {
            result.append(SculptureCell(x: x, y: y, z: end.z))
            if x == end.x && y == end.y { break }
            let doubled = 2 * error
            if doubled >= dy { error += dy; x += sx }
            if doubled <= dx { error += dx; y += sy }
        }
        return result
    }

    private func rememberStroke() {
        guard let strokeStart else { return }
        remember(strokeStart)
        self.strokeStart = nil
    }

    private func clampSelection() {
        layer = min(max(0, layer), sculpture.depth - 1)
        column = min(max(0, column), sculpture.width - 1)
        row = min(max(0, row), sculpture.height - 1)
    }

    private func remember(_ snapshot: Sculpture? = nil) {
        undoStates.append(snapshot ?? sculpture)
        if undoStates.count > 100 { undoStates.removeFirst() }
        redoStates = []
    }
}
