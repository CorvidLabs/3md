import RookRendering
import RookSculpture
import SwiftUI

private struct CanvasRenderRequest: Equatable, Sendable {
    let sculpture: Sculpture
    let revision: UUID
    let camera: SculptureCamera
    let style: SculptureRenderStyle
    let layer: Int
    let opacity: Double
    let width: Int
    let height: Int
    let showsEmptyCells: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.revision == rhs.revision && lhs.camera == rhs.camera && lhs.style == rhs.style
            && lhs.layer == rhs.layer && lhs.opacity == rhs.opacity && lhs.width == rhs.width
            && lhs.height == rhs.height && lhs.showsEmptyCells == rhs.showsEmptyCells
    }
}

/// Camera pose and viewport size deliberately do not participate in mesh preparation.
private struct LiveSceneRequest: Equatable, Sendable {
    let revision: UUID
    let layer: Int
    let showsEmptyCells: Bool
    let enabled: Bool
}

private struct PreparedLiveScene: Sendable {
    let request: LiveSceneRequest
    let scene: SculptureVoxelScene
    let mesh: SculptureVoxelMeshBuffers
    let ghosts: SculptureVoxelGhostBuffers
    let emptyCells: [SculptureCell]
}

private struct LiveStroke {
    let prepared: PreparedLiveScene
    let camera: SculptureCamera
    let opacity: Double
}

/// CGImage is immutable; the worker publishes a completed image and value geometry together.
private struct RenderedCanvas: @unchecked Sendable {
    let request: CanvasRenderRequest
    let image: CGImage?
    let cubes: SculptureVoxelFrame?
    let ascii: SculptureFrame?

    static func render(_ request: CanvasRenderRequest) -> Self {
        switch request.style {
        case .cubes:
            let frame = SculptureVoxelProjection.frame(
                request.sculpture,
                camera: request.camera,
                width: request.width,
                height: request.height,
                selectedLayer: request.layer,
                showsEmptyCells: request.showsEmptyCells
            )
            return Self(
                request: request,
                image: SculptureVoxelRasterizer.image(frame, opacity: request.opacity, selectedLayer: request.layer),
                cubes: frame,
                ascii: nil
            )
        case .ascii:
            let frame = SculptureProjection.frame(request.sculpture, camera: request.camera)
            return Self(
                request: request,
                image: SculptureRasterizer.image(frame, selectedLayer: request.layer),
                cubes: nil,
                ascii: frame
            )
        }
    }
}

internal struct SculptureViewport: View {
    @Bindable var workspace: SculptureWorkspace
    let showsControls: Bool
    let fit: () -> Void
    var focusCanvas: () -> Void = {}
    @State private var orbitStart: SculptureCamera?
    @State private var pointerStart: CGPoint?
    @State private var showingCamera = false
    @State private var panMode = false
    @State private var rotationAxis: Int?
    @State private var rotationStep = "15"
    @State private var panStep = "0.25"
    @State private var precisionMessage = ""
    @State private var sphereStart: SculptureCamera?
    @State private var rendered: RenderedCanvas?
    @State private var strokeFrame: RenderedCanvas?
    @State private var strokeDocument: UUID?
    @State private var beganPainting = false
    @State private var liveController = SculptureLiveVoxelController()
    @State private var liveScene: PreparedLiveScene?
    @State private var liveFailure: String?
    @State private var liveStroke: LiveStroke?

    var body: some View {
        GeometryReader { geometry in
            let request = CanvasRenderRequest(
                sculpture: workspace.sculpture,
                revision: workspace.sculptureRevision,
                camera: workspace.camera,
                style: workspace.renderStyle,
                layer: workspace.layer,
                opacity: workspace.cubeOpacity,
                width: max(128, min(1_280, Int(geometry.size.width))),
                height: max(128, min(1_280, Int(geometry.size.height))),
                showsEmptyCells: showsControls && workspace.paintsIn3D
            )
            let liveRequest = LiveSceneRequest(
                revision: request.revision,
                layer: request.layer,
                showsEmptyCells: request.showsEmptyCells,
                enabled: request.style == .cubes && MetalSculptureView.isAvailable
            )
            let rasterRequest = liveRequest.enabled ? nil : request
            ZStack(alignment: .bottom) {
                canvas(request: request, liveRequest: liveRequest, size: geometry.size)
                if showsControls { cameraBar.padding(16) }
            }
            .overlay(alignment: .topTrailing) {
                if showsControls { axisSphere.padding(12) }
            }
            .background(Color(red: 0.065, green: 0.085, blue: 0.10))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onAppear { workspace.camera.fitsVolume = true }
            .onChange(of: workspace.camera.fitsVolume) { _, fits in
                if !fits { workspace.camera.fitsVolume = true }
            }
            .onChange(of: workspace.paintsIn3D) { _, paints in
                if paints { panMode = false }
            }
            .task(id: rasterRequest) {
                guard let request = rasterRequest else { return }
                let worker = Task.detached(priority: .userInitiated) { RenderedCanvas.render(request) }
                let result = await withTaskCancellationHandler {
                    await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled else { return }
                rendered = result
            }
            .task(id: liveStroke?.prepared.request ?? liveRequest) {
                guard liveRequest.enabled else { return }
                let sculpture = request.sculpture
                let cached = liveScene?.request.revision == request.revision ? liveScene : nil
                // A gallery opening may already have prepared this exact revision away from the main actor.
                let reusable =
                    cached.map { SculpturePreparedGeometry(scene: $0.scene, mesh: $0.mesh) }
                    ?? workspace.preparedGeometry(for: request.revision)
                let worker = Task.detached(priority: .userInitiated) {
                    let scene = try reusable?.scene ?? SculptureVoxelSurfaceExtractor.extract(sculpture)
                    let mesh = try reusable?.mesh ?? SculptureVoxelMeshBuffers.prepare(scene)
                    var emptyCells: [SculptureCell] = []
                    if liveRequest.showsEmptyCells {
                        let slice = sculpture.layers[liveRequest.layer]
                        for y in 0..<sculpture.height {
                            try Task.checkCancellation()
                            for x in 0..<sculpture.width where slice[y * sculpture.width + x] == Sculpture.empty {
                                emptyCells.append(SculptureCell(x: x, y: y, z: liveRequest.layer))
                            }
                        }
                    }
                    let ghosts: SculptureVoxelGhostBuffers
                    if let cached, cached.request.layer == liveRequest.layer,
                        cached.request.showsEmptyCells == liveRequest.showsEmptyCells
                    {
                        ghosts = cached.ghosts
                    } else {
                        ghosts = try SculptureVoxelGhostBuffers.prepare(
                            cells: emptyCells,
                            scene: scene,
                            selectedLayer: liveRequest.layer
                        )
                    }
                    try Task.checkCancellation()
                    return PreparedLiveScene(
                        request: liveRequest,
                        scene: scene,
                        mesh: mesh,
                        ghosts: ghosts,
                        emptyCells: emptyCells
                    )
                }
                do {
                    let result = try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: {
                        worker.cancel()
                    }
                    guard !Task.isCancelled else { return }
                    liveScene = result
                    liveFailure = nil
                } catch {
                    guard !Task.isCancelled else { return }
                    liveFailure = error.localizedDescription
                    liveScene = nil
                }
            }
            .onChange(of: workspace.documentGeneration) { _, _ in finishStroke() }
            .onChange(of: workspace.paintsIn3D) { _, _ in finishStroke() }
            .onChange(of: workspace.renderStyle) { _, _ in finishStroke() }
            .onDisappear { finishStroke() }
        }
    }

    private func canvas(request: CanvasRenderRequest, liveRequest: LiveSceneRequest, size: CGSize) -> some View {
        ZStack {
            if liveRequest.enabled {
                if let prepared = liveStroke?.prepared ?? liveScene {
                    SculptureLiveVoxelView(
                        preparedMesh: prepared.mesh,
                        sceneID: prepared.request.revision,
                        camera: liveStroke?.camera ?? request.camera,
                        selectedLayer: prepared.request.layer,
                        opacity: liveStroke?.opacity ?? request.opacity,
                        preparedGhosts: prepared.ghosts,
                        controller: liveController
                    )
                } else if let liveFailure {
                    VStack(spacing: 10) {
                        Text("Cube preview is too detailed").font(.title3.weight(.medium))
                        Text(liveFailure)
                            .font(.callout).multilineTextAlignment(.center)
                    }.foregroundStyle(.white.opacity(0.8)).padding(30)
                } else {
                    ProgressView().controlSize(.small)
                }
            } else if rendered?.cubes?.isOverBudget == true {
                VStack(spacing: 10) {
                    Text("Cube preview is too detailed").font(.title3.weight(.medium))
                    Text("Use Slice or ASCII to edit this volume. Cubes can show up to 250,000 visible surfaces.")
                        .font(.callout).multilineTextAlignment(.center)
                }.foregroundStyle(.white.opacity(0.8)).padding(30)
            } else if let image = rendered?.image {
                if MetalSculptureView.isAvailable {
                    MetalSculptureView(image: image)
                } else {
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                }
            } else {
                ProgressView().controlSize(.small)
            }
            if workspace.sculpture.occupiedCount == 0 && !workspace.paintsIn3D {
                VStack(spacing: 10) {
                    Text("Start with a cube").font(.title3.weight(.medium))
                    Text("Choose Paint and click the slice grid, or open an example.").font(.callout)
                }.foregroundStyle(.white.opacity(0.8)).padding(30)
            }
            SculptureCanvasPointer(
                paint: isPainting,
                event: { phase, point in
                    handlePointer(phase, point: point, request: request, liveRequest: liveRequest, size: size)
                },
                camera: { input in
                    switch input {
                    case .pan(let phase, let point):
                        handlePointer(
                            phase,
                            point: point,
                            request: request,
                            liveRequest: liveRequest,
                            size: size,
                            pan: true
                        )
                    case .panBy(let delta):
                        finishStroke()
                        workspace.camera.pan(
                            horizontal: delta.width,
                            vertical: delta.height,
                            extent: Double(
                                max(workspace.sculpture.width, workspace.sculpture.height, workspace.sculpture.depth)
                            ),
                            width: size.width,
                            height: size.height,
                            dimensions: SIMD3(
                                workspace.sculpture.width,
                                workspace.sculpture.height,
                                workspace.sculpture.depth
                            )
                        )
                    case .zoom(let factor):
                        finishStroke()
                        workspace.camera.magnify(factor)
                    }
                }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("3D sculpture canvas")
        .accessibilityValue(
            "\(workspace.sculpture.title), \(workspace.sculpture.occupiedCount) voxels, \(workspace.renderStyle.rawValue), slice \(workspace.layer + 1) selected\((liveRequest.enabled ? liveFailure != nil : rendered?.cubes?.isOverBudget == true) ? "; cube preview unavailable; use Slice or ASCII" : "")"
        )
        .accessibilityHint(
            isPainting
                ? "Draw adds a cube on a face or an empty slice cell. Erase removes the clicked cube. Each drag is one undo step."
                : "Drag to orbit freely. Choose Pan or Shift, middle or right drag to move. Scroll or pinch to zoom. Click a cube to select its slice."
        )
        .accessibilityIdentifier("editor.canvas")
    }

    private func handlePointer(
        _ phase: SculpturePointerPhase,
        point: CGPoint,
        request: CanvasRenderRequest,
        liveRequest: LiveSceneRequest,
        size: CGSize,
        pan: Bool = false
    ) {
        let pans = pan || panMode
        let paints = isPainting && !pans
        if phase == .down {
            focusCanvas()
            pointerStart = point
            orbitStart = workspace.camera
        }
        if liveRequest.enabled, paints, phase != .up {
            if liveStroke == nil {
                guard let liveScene, liveScene.request == liveRequest,
                    liveController.installedSceneID == request.revision,
                    liveController.currentCamera == request.camera,
                    abs(liveController.viewportSize.width - size.width) < 1,
                    abs(liveController.viewportSize.height - size.height) < 1
                else {
                    workspace.message = "Preview is updating. Try painting again in a moment."
                    return
                }
                liveStroke = LiveStroke(prepared: liveScene, camera: request.camera, opacity: request.opacity)
                strokeDocument = workspace.documentGeneration
            }
            guard strokeDocument == workspace.documentGeneration else { return }
            if let hit = liveController.hitTest(x: point.x, y: point.y) {
                if workspace.paintVoxel(hit, start: !beganPainting) {
                    beganPainting = true
                } else if workspace.tool == .draw {
                    workspace.message = "This face reaches the volume edge. Choose another face or edit a slice."
                }
            } else {
                workspace.message = "Click a cube face or an empty cell in the selected slice grid."
            }
            return
        }
        if paints, phase != .up {
            guard rendered?.cubes?.isOverBudget != true else {
                workspace.message = "Cube preview limit exceeded. Use Slice or ASCII to edit this volume."
                return
            }
            if strokeFrame == nil {
                guard rendered?.request == request else {
                    workspace.message = "Preview is updating. Try painting again in a moment."
                    return
                }
                strokeFrame = rendered
                strokeDocument = workspace.documentGeneration
            }
            guard strokeDocument == workspace.documentGeneration, let frame = strokeFrame else { return }
            if let hit = cubeHit(frame, location: point, size: size) {
                if workspace.paintVoxel(hit, start: !beganPainting) {
                    beganPainting = true
                } else if workspace.tool == .draw {
                    workspace.message = "This face reaches the volume edge. Choose another face or edit a slice."
                }
            } else {
                workspace.message = "Click a cube face or an empty cell in the selected slice grid."
            }
        } else if !paints, let start = pointerStart {
            let dx = point.x - start.x, dy = point.y - start.y
            if phase == .drag, let orbitStart, abs(dx) + abs(dy) >= 3 {
                var camera = orbitStart
                if pans {
                    camera.pan(
                        horizontal: dx,
                        vertical: dy,
                        extent: Double(
                            max(workspace.sculpture.width, workspace.sculpture.height, workspace.sculpture.depth)
                        ),
                        width: size.width,
                        height: size.height,
                        dimensions: SIMD3(
                            workspace.sculpture.width,
                            workspace.sculpture.height,
                            workspace.sculpture.depth
                        )
                    )
                } else if let rotationAxis {
                    camera.rotate(axis: rotationAxis, radians: (abs(dx) >= abs(dy) ? dx : -dy) * 0.008)
                } else {
                    camera.orbit(horizontal: dx, vertical: dy)
                }
                workspace.camera = camera
                workspace.viewpoint = .perspective
            } else if phase == .up, !pans, abs(dx) + abs(dy) < 3 {
                if liveRequest.enabled, liveScene?.request == liveRequest,
                    liveController.installedSceneID == request.revision,
                    liveController.currentCamera == request.camera,
                    let hit = liveController.hitTest(x: point.x, y: point.y)
                {
                    workspace.select(hit.cell)
                } else if !liveRequest.enabled, rendered?.request == request, let rendered {
                    select(rendered, location: point, size: size)
                }
            }
        }
        if phase == .up {
            orbitStart = nil; pointerStart = nil
            finishStroke()
        }
    }
    private var isPainting: Bool {
        showsControls && workspace.renderStyle == .cubes && workspace.paintsIn3D && !panMode
    }

    private func finishStroke() {
        workspace.endStroke()
        strokeFrame = nil; strokeDocument = nil; beganPainting = false; liveStroke = nil
    }

    private func imagePoint(_ frame: RenderedCanvas, location: CGPoint, size: CGSize) -> CGPoint? {
        guard let image = frame.image else { return nil }
        let scale = min(size.width / Double(image.width), size.height / Double(image.height))
        guard scale > 0 else { return nil }
        return CGPoint(
            x: (location.x - (size.width - Double(image.width) * scale) / 2) / scale,
            y: (location.y - (size.height - Double(image.height) * scale) / 2) / scale
        )
    }

    private func cubeHit(_ frame: RenderedCanvas, location: CGPoint, size: CGSize) -> SculptureVoxelHit? {
        guard let point = imagePoint(frame, location: location, size: size) else { return nil }
        return frame.cubes?.hitTest(x: point.x, y: point.y)
    }

    private func select(_ frame: RenderedCanvas, location: CGPoint, size: CGSize) {
        if let hit = cubeHit(frame, location: location, size: size) {
            workspace.select(hit.cell)
        } else if let point = imagePoint(frame, location: location, size: size),
            let cell = frame.ascii?.cell(column: Int(floor(point.x / 9)), row: Int(floor(point.y / 18)))
        {
            workspace.select(cell)
        }
    }

    private func chooseAxis(_ axis: Int?) {
        workspace.endStroke()
        workspace.paintsIn3D = false
        panMode = false
        rotationAxis = axis
    }

    private func nudgeRotation(_ sign: Double) {
        guard let axis = rotationAxis, let step = Double(rotationStep), step.isFinite, step > 0 else {
            precisionMessage = "Choose an axis and enter a finite, positive step."
            return
        }
        precisionMessage = ""
        workspace.camera.rotate(axis: axis, radians: sign * step.truncatingRemainder(dividingBy: 360) * .pi / 180)
        workspace.viewpoint = .perspective
    }

    private func nudgePan(_ x: Double, _ y: Double) {
        guard let step = Double(panStep), step.isFinite, step > 0 else {
            precisionMessage = "Enter a finite, positive pan step."
            return
        }
        precisionMessage = ""
        workspace.camera.panX -= x * step
        workspace.camera.panY += y * step
        workspace.camera = workspace.camera.normalized
    }

    private func ringPoint(axis: Int, angle: Double) -> CGPoint {
        let other = (0...2).filter { $0 != axis }
        var point = SIMD3<Double>(repeating: 0)
        point[other[0]] = cos(angle)
        point[other[1]] = sin(angle)
        point.y *= -1
        let basis = workspace.camera.basis
        return CGPoint(x: 50 + 34 * (point * basis.right).sum(), y: 50 - 34 * (point * basis.up).sum())
    }

    private var axisSphere: some View {
        VStack(spacing: 4) {
            Canvas { context, _ in
                let colors: [Color] = [.red, .green, .blue]
                for axis in 0...2 {
                    var path = Path()
                    for index in 0...64 {
                        let point = ringPoint(axis: axis, angle: Double(index) * .pi / 32)
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    context.stroke(
                        path,
                        with: .color(colors[axis].opacity(rotationAxis == axis ? 1 : 0.65)),
                        lineWidth: rotationAxis == axis ? 4 : 2
                    )
                }
            }
            .frame(width: 100, height: 100)
            .accessibilityHidden(true)
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    if sphereStart == nil {
                        var nearest = (distance: Double.infinity, axis: 0)
                        for axis in 0...2 {
                            for index in 0...128 {
                                let point = ringPoint(axis: axis, angle: Double(index) * .pi / 64)
                                let distance = hypot(point.x - value.startLocation.x, point.y - value.startLocation.y)
                                if distance < nearest.distance { nearest = (distance, axis) }
                            }
                        }
                        chooseAxis(nearest.axis)
                        sphereStart = workspace.camera
                    }
                    guard var camera = sphereStart, let rotationAxis else { return }
                    let dx = value.translation.width, dy = value.translation.height
                    camera.rotate(axis: rotationAxis, radians: (abs(dx) >= abs(dy) ? dx : -dy) * 0.008)
                    workspace.camera = camera
                    workspace.viewpoint = .perspective
                }.onEnded { _ in sphereStart = nil }
            )
            HStack(spacing: 8) {
                Button("Free") { chooseAxis(nil) }.accessibilityLabel("Free orbit")
                ForEach(0...2, id: \.self) { axis in
                    Button(["X", "Y", "Z"][axis]) { chooseAxis(axis) }
                        .foregroundStyle(rotationAxis == axis ? Color.accentColor : Color.primary)
                        .accessibilityLabel("Rotate around " + ["X", "Y", "Z"][axis])
                        .accessibilityValue(rotationAxis == axis ? "Selected" : "Unselected")
                }
            }.buttonStyle(.borderless).font(.caption)
        }
        .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var cameraBar: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(SculptureViewpoint.allCases) { viewpoint in
                    Button(viewpoint.rawValue) { workspace.setViewpoint(viewpoint) }
                }
                Divider()
                Button("Reset camera") {
                    workspace.setViewpoint(.perspective); fit()
                }
            } label: {
                Label(
                    workspace.viewpoint == .perspective ? "Orbit" : workspace.viewpoint.rawValue,
                    systemImage: "viewfinder"
                )
            }
            .accessibilityLabel("Camera view").accessibilityIdentifier("editor.camera.view")
            Button("Pan") {
                panMode.toggle()
                if panMode { workspace.paintsIn3D = false }
            }
            .foregroundStyle(panMode ? Color.accentColor : Color.primary)
            .accessibilityValue(panMode ? "On" : "Off").accessibilityIdentifier("editor.camera.pan")
            Button("Fit") {
                workspace.setViewpoint(.perspective)
                fit()
            }.accessibilityLabel("Fit sculpture in canvas").accessibilityIdentifier(
                "editor.camera.fit"
            )
            Divider().frame(height: 18)
            Image(systemName: "minus.magnifyingglass").accessibilityHidden(true)
            Slider(value: $workspace.camera.zoom, in: 0.5...2).frame(width: 100)
                .accessibilityLabel("Camera zoom").accessibilityIdentifier("editor.camera.zoom")
            Image(systemName: "plus.magnifyingglass").accessibilityHidden(true)
            Button {
                showingCamera.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel("Camera controls").accessibilityIdentifier("editor.camera.controls")
            .popover(isPresented: $showingCamera) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Camera").font(.headline)
                    HStack {
                        Text("Degrees")
                        TextField("Degrees", text: $rotationStep).frame(width: 70)
                            .accessibilityLabel("Rotation step in degrees")
                        Button("−") { nudgeRotation(-1) }.accessibilityLabel("Rotate negative step")
                        Button("+") { nudgeRotation(1) }.accessibilityLabel("Rotate positive step")
                    }.disabled(rotationAxis == nil)
                    HStack {
                        Text("Pan cells")
                        TextField("Pan cells", text: $panStep).frame(width: 70)
                            .accessibilityLabel("Pan step in cells")
                        Button("←") { nudgePan(-1, 0) }.accessibilityLabel("Pan left")
                        Button("↑") { nudgePan(0, -1) }.accessibilityLabel("Pan up")
                        Button("↓") { nudgePan(0, 1) }.accessibilityLabel("Pan down")
                        Button("→") { nudgePan(1, 0) }.accessibilityLabel("Pan right")
                    }
                    if !precisionMessage.isEmpty { Text(precisionMessage).font(.caption) }
                    LabeledContent("Orbit") {
                        Slider(value: $workspace.camera.yaw, in: (-Double.pi)...Double.pi)
                            .accessibilityLabel("Camera orbit").accessibilityIdentifier("editor.camera.orbit")
                    }
                    LabeledContent("Tilt") {
                        Slider(value: $workspace.camera.pitch, in: (-Double.pi)...Double.pi)
                            .accessibilityLabel("Camera tilt").accessibilityIdentifier("editor.camera.tilt")
                    }
                    if workspace.renderStyle == .cubes {
                        LabeledContent("Opacity") {
                            Slider(value: $workspace.cubeOpacity, in: 0.15...1)
                                .accessibilityLabel("Cube opacity").accessibilityIdentifier("editor.voxel.opacity")
                        }
                    }
                }.frame(width: 270).padding(20)
            }
        }
        .buttonStyle(.borderless).font(.callout)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)).fixedSize()
    }
}
