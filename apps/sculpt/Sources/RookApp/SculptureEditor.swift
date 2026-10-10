import AppKit
import RookRendering
import RookSculpture
import SwiftUI
import UniformTypeIdentifiers

internal enum SculptureEditorMode: String, CaseIterable, Identifiable, Sendable {
    case sculpt = "Sculpt", slice = "Slice"
    var id: Self { self }
}

internal struct SculptureEditor: View {
    @Bindable var workspace: SculptureWorkspace
    @State private var mode: SculptureEditorMode
    @State private var importing = false
    /// What the one Open panel chooses: a document, or the project folder of a linked root that Open just read.
    @State private var importKind = ImportKind.document
    /// The linked root waiting for its project folder. Held in memory only, until the folder panel closes.
    @State private var linkedRoot: URL?
    @State private var exporting = false
    @State private var opening = false
    @State private var openingTask: Task<Void, Never>?
    @State private var openingGeneration = UUID()
    @State private var saveJob = SculptureSaveJob()
    @State private var graphSaveJob = SculptureGraphSaveJob()
    @State private var portableSaveJob = SculpturePortableSaveJob()
    @State private var pendingPortable: SculpturePreparedPortable?
    @State private var pendingPortableFormat: SculpturePortableFormat?
    @State private var portableVoxelSnapshot: SculptureThreeMDSnapshot?
    @State private var portableVoxelGeneration: UUID?
    @State private var pendingSave: SculpturePreparedSave?
    @State private var exportFile = SculptureExport(data: Data())
    @State private var exportType = UTType.png
    @State private var replacement: Replacement?
    @State private var confirmReplacement = false
    @State private var sheet: EditorSheet?
    /// A finished gallery load, routed after the gallery sheet has closed.
    @State private var pendingGalleryOpen: SculptureGalleryOpened?
    @State private var pendingReferenceSave: SculptureReferenceSaveSession?
    @State private var pendingCompositionVoxels: Sculpture?
    @State private var pendingWorldOpen: SculptureWorldHandoff?
    @State private var graphSaveSession: SculptureReferenceSaveSession?
    @State private var showingCommands = false
    @State private var showingCellControls = false
    @State private var initialFitComplete = false
    @State private var clickedSidebarLayer: Int?
    @State private var previousFocus: EditorFocus?
    @State private var paletteFocusHandoff: EditorFocus?
    @State private var canvasFocus = SculptureCanvasFocus()
    @FocusState private var focus: EditorFocus?

    private enum EditorFocus: Hashable { case title, canvas }
    private enum ImportKind { case document, projectFolder }
    private enum Replacement {
        case blank, volume(Int), example(SculptureGalleryEntry, Sculpture, SculpturePreparedGeometry?)
        case composition(Sculpture), open
    }
    private enum EditorSheet: Identifiable {
        case examples, composition(SculptureCompositionDraft), linked(SculptureLinkedSession),
            world(SculptureWorldDraft), exportStudio(
                Sculpture,
                SculptureCamera,
                SculptureRenderStyle,
                Double
            )
        var id: String {
            switch self {
            case .examples: "examples"
            case .composition: "composition"
            case .linked: "linked"
            case .world: "world"
            case .exportStudio: "export"
            }
        }

        @MainActor
        static func composition(
            _ document: SculptureComposition?,
            initiallyUnsaved: Bool = false,
            portableSnapshot: SculptureThreeMDSnapshot? = nil
        ) -> Self {
            let draft = SculptureCompositionDraft(composition: document, portableSnapshot: portableSnapshot)
            if initiallyUnsaved { draft.markUnsaved() }
            return .composition(draft)
        }

        @MainActor
        static func world(
            _ document: SculptureWorld?,
            initiallyUnsaved: Bool = false,
            portableSnapshot: SculptureThreeMDSnapshot? = nil,
            notice: String? = nil
        ) -> Self {
            let draft = SculptureWorldDraft(world: document, portableSnapshot: portableSnapshot, notice: notice)
            if initiallyUnsaved { draft.markUnsaved() }
            return .world(draft)
        }
    }

    internal init(workspace: SculptureWorkspace, mode: SculptureEditorMode = .sculpt) {
        self.workspace = workspace
        _mode = State(initialValue: mode)
    }

    private var editorBase: some View {
        ZStack(alignment: .top) {
            editorContent.accessibilityHidden(showingCommands).allowsHitTesting(!showingCommands)
            if showingCommands {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.18).contentShape(Rectangle()).onTapGesture { closeCommands() }
                    SculptureCommandPalette(
                        actions: commands,
                        close: { closeCommands() },
                        inputReleased: { completePaletteDismissal() },
                        executionStarted: { previousFocus = .canvas }
                    )
                    .padding(.top, 80)
                }
            }
        }
        .frame(minWidth: 940, minHeight: 650)
        .background(Brand.paper).foregroundStyle(Brand.ink).tint(Brand.accent)
        .disabled(opening || graphSaveJob.isRunning || portableSaveJob.isRunning)
        .focusedSceneValue(
            \.sculptureDocumentActions,
            SculptureEditorCommandAvailability.documentActionsAvailable(sheet: sheetContext, activity: activity)
                ? SculptureDocumentActions(
                    newDocument: {
                        dismissPaletteForDocumentAction()
                        requestReplacement(.blank)
                    },
                    newComposition: {
                        dismissPaletteForDocumentAction()
                        sheet = .composition(nil)
                    },
                    newWorld: {
                        dismissPaletteForDocumentAction()
                        sheet = .world(nil)
                    },
                    openDocument: {
                        dismissPaletteForDocumentAction()
                        requestReplacement(.open)
                    },
                    saveDocument: {
                        dismissPaletteForDocumentAction()
                        save()
                    },
                    saveReadableDocument: {
                        dismissPaletteForDocumentAction()
                        save(format: .readable)
                    }
                ) : nil
        )
        .focusedSceneValue(\.sculpturePortableActions, portableActions)
        .focusedSceneValue(\.sculptureInsertionActions, insertionActions)
        .focusedSceneValue(\.sculptureLinkedActions, linkedActions)
        .focusedSceneValue(\.sculptureSheetHistory, sheetHistory)
        .onChange(of: sheet?.id) { _, _ in syncOpenSheet() }
        .onChange(of: graphSaveSession == nil) { _, _ in syncOpenSheet() }
        .onAppear {
            syncOpenSheet()
            if graphSaveSession != nil && !graphSaveJob.isRunning && !portableSaveJob.isRunning && !exporting {
                restoreGraphAfterSave()
            }
            guard !initialFitComplete else { return }
            initialFitComplete = true
            if workspace.camera == SculptureCamera() { fitCamera() }
        }
    }

    private var sheetPresentation: some View {
        editorBase
            .sheet(
                item: $sheet,
                onDismiss: {
                    if let pendingGalleryOpen {
                        self.pendingGalleryOpen = nil
                        openFromGallery(pendingGalleryOpen)
                    }
                    if let pendingCompositionVoxels {
                        self.pendingCompositionVoxels = nil
                        requestReplacement(.composition(pendingCompositionVoxels))
                    }
                    if let pendingReferenceSave {
                        self.pendingReferenceSave = nil
                        if let pendingPortableFormat {
                            self.pendingPortableFormat = nil
                            graphSaveSession = pendingReferenceSave
                            preparePortableGraph(pendingReferenceSave, format: pendingPortableFormat)
                        } else {
                            saveGraph(pendingReferenceSave)
                        }
                    }
                    if let pendingWorldOpen {
                        self.pendingWorldOpen = nil
                        sheet = .world(
                            pendingWorldOpen.world,
                            initiallyUnsaved: true,
                            portableSnapshot: pendingWorldOpen.snapshot,
                            notice: pendingWorldOpen.notice
                        )
                    }
                }
            ) { sheet in
                switch sheet {
                case .examples:
                    SculptureExamplesBrowser { opened in
                        pendingGalleryOpen = opened
                        self.sheet = nil
                    }
                case .composition(let draft):
                    SculptureCompositionEditor(
                        draft: draft,
                        onDirtyChange: { workspace.referenceDraftIsDirty = $0 },
                        onOpen: { _, voxels in
                            pendingCompositionVoxels = voxels
                            self.sheet = nil
                        },
                        onSave: { _ in
                            do {
                                pendingReferenceSave = try SculptureReferenceSaveSession(draft: .composition(draft))
                                self.sheet = nil
                            } catch { workspace.error = error.localizedDescription }
                        },
                        onWorld: { handoff in
                            pendingWorldOpen = handoff
                            self.sheet = nil
                        }
                    )
                case .linked(let session):
                    SculptureLinkedSessionView(session: session)
                case .world(let draft):
                    SculptureWorldEditor(
                        draft: draft,
                        onDirtyChange: { workspace.referenceDraftIsDirty = $0 },
                        onSave: { _ in
                            do {
                                pendingReferenceSave = try SculptureReferenceSaveSession(draft: .world(draft))
                                self.sheet = nil
                            } catch { workspace.error = error.localizedDescription }
                        },
                        onOpen: { voxels in
                            pendingCompositionVoxels = voxels
                            self.sheet = nil
                        }
                    )
                case .exportStudio(let sculpture, let camera, let style, let opacity):
                    SculptureExportStudio(sculpture: sculpture, camera: camera, style: style, opacity: opacity) { url in
                        workspace.message = "Exported \(url.lastPathComponent)."
                    }
                }
            }
    }

    private var lifecyclePresentation: some View {
        sheetPresentation
            .onChange(of: focus) { old, new in
                if old == .title && new != .title { workspace.commitTitle() }
                if new == .title { canvasFocus.release() }
            }
            .onChange(of: workspace.renderStyle) { _, _ in
                workspace.endStroke()
                fitCamera()
            }
            .onChange(of: workspace.documentGeneration) { _, _ in
                saveJob.cancel(); portableSaveJob.cancel()
            }
            .onChange(of: saveJob.result?.id) { _, _ in
                guard let result = saveJob.result,
                    result.documentGeneration == workspace.documentGeneration
                else { return }
                pendingSave = result
                exportFile = SculptureExport(data: result.data)
                exportType = result.format == .compact ? .compactSculpture : .sculpture
                exporting = true
            }
            .onChange(of: saveJob.error) { _, error in
                if let error { workspace.error = error }
            }
            .onChange(of: graphSaveJob.result?.id) { _, _ in
                guard let prepared = graphSaveJob.result, let graphSaveSession,
                    prepared.document == graphSaveSession.document
                else { return }
                pendingSave = nil
                exportFile = SculptureExport(data: prepared.data)
                exportType = .sculpture
                exporting = true
            }
            .onChange(of: graphSaveJob.error) { _, error in
                if let error {
                    workspace.error = error
                    restoreGraphAfterSave()
                }
            }
            .onChange(of: portableSaveJob.result?.id) { _, _ in
                guard let prepared = portableSaveJob.result,
                    prepared.documentGeneration == workspace.documentGeneration
                else { return }
                pendingPortable = prepared
                pendingSave = nil
                exportFile = SculptureExport(data: prepared.data)
                exportType = prepared.format == .binary ? .compactSculpture : .sculpture
                exporting = true
            }
            .onChange(of: portableSaveJob.error) { _, error in
                if let error {
                    workspace.error = error
                    restoreGraphAfterSave()
                }
            }
            .onDisappear {
                saveJob.cancel(); graphSaveJob.cancel(); portableSaveJob.cancel(); cancelOpening()
            }
            .overlay(alignment: .bottom) {
                if opening {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Opening scene…")
                        Button("Cancel") { cancelOpening() }
                            .accessibilityIdentifier("editor.open.cancel")
                    }
                    .padding().background(Brand.paper, in: RoundedRectangle(cornerRadius: 12)).padding()
                } else if graphSaveJob.isRunning || portableSaveJob.isRunning {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(
                            portableSaveJob.isRunning
                                ? "Preparing portable ThreeMD copy…" : "Preparing reference document…"
                        )
                        Button("Cancel") {
                            portableSaveJob.cancel(); restoreGraphAfterSave()
                        }
                        .accessibilityIdentifier("editor.graph-save.cancel")
                    }
                    .padding().background(Brand.paper, in: RoundedRectangle(cornerRadius: 12)).padding()
                }
            }
    }

    private var filePresentation: some View {
        lifecyclePresentation
            // One panel serves Open and the project folder grant of a linked root, so neither importer shadows the
            // other.
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: importKind == .projectFolder
                    ? [.folder] : [.sculpture, .compactSculpture, .plainText],
                allowsMultipleSelection: false
            ) { result in
                guard importKind == .projectFolder else {
                    switch result {
                    case .success(let urls):
                        if let url = urls.first { startOpening(url) }
                    case .failure(let error): workspace.error = error.localizedDescription
                    }
                    return
                }
                importKind = .document
                let root = linkedRoot
                linkedRoot = nil
                switch result {
                case .success(let urls):
                    if let root, let folder = urls.first { startLinkedOpening(root: root, folder: folder) }
                case .failure(let error):
                    // Cancelling the folder panel opens nothing and leaves the current document as it was.
                    if (error as? CocoaError)?.code != .userCancelled { workspace.error = error.localizedDescription }
                }
            }
            .fileDialogMessage(
                importKind == .projectFolder
                    ? Text(
                        "Choose the project folder that contains \(linkedRoot?.lastPathComponent ?? "the linked composition")."
                    ) : nil
            )
            .fileExporter(
                isPresented: $exporting,
                document: exportFile,
                contentTypes: [exportType],
                defaultFilename: exportFilename,
                onCompletion: completeFileExport,
                onCancellation: cancelFileExport
            )
    }

    var body: some View {
        filePresentation
            .confirmationDialog("Replace this sculpture? Unsaved edits will be lost.", isPresented: $confirmReplacement)
        {
            Button("Discard edits", role: .destructive) { performReplacement() }
            Button("Cancel", role: .cancel) { replacement = nil }
        }
            .alert(
                "Couldn’t complete that action",
                isPresented: Binding(get: { workspace.error != nil }, set: { if !$0 { workspace.error = nil } })
            ) {
                Button("OK") { workspace.error = nil }
            } message: {
                Text(workspace.error ?? "")
            }
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 20).padding(.vertical, 16)
            Divider()
            HStack(spacing: 20) {
                modeSwitcher
                Picker("Rendering", selection: $workspace.renderStyle) {
                    ForEach(SculptureRenderStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 148)
                .accessibilityIdentifier("editor.render-style")
                Text("Slice \(workspace.layer + 1) of \(workspace.sculpture.depth)")
                    .font(.callout).foregroundStyle(Brand.secondary)
                    .accessibilityIdentifier("editor.selected-slice")
                Spacer()
                if mode == .sculpt {
                    if workspace.renderStyle == .cubes {
                        Toggle("Paint", isOn: $workspace.paintsIn3D)
                            .toggleStyle(.button)
                            .accessibilityLabel("Paint cubes in 3D")
                            .accessibilityIdentifier("editor.voxel.paint-mode")
                    }
                    Button {
                        changeMode(.slice)
                    } label: {
                        Label("Edit slice", systemImage: "square.grid.3x3")
                    }
                    .accessibilityIdentifier("editor.edit-slice")
                } else {
                    Menu("Slice actions") {
                        Button("Rotate 90°") { workspace.rotateLayer() }
                            .disabled(workspace.sculpture.width != workspace.sculpture.height)
                        Button("Clear slice") { workspace.clearLayer() }
                        Button("Duplicate slice") { addLayer(duplicate: true) }.disabled(
                            workspace.sculpture.depth == Sculpture.maximumDimension
                        )
                        Button("Remove slice") {
                            let index = workspace.layer
                            workspace.change { try $0.removeLayer(at: index) }
                        }.disabled(workspace.sculpture.depth == 1)
                    }
                    .accessibilityIdentifier("editor.slice.actions")
                }
            }
            .buttonStyle(.bordered).padding(.horizontal, 20).padding(.vertical, 12)
            HStack(spacing: 0) {
                layers.frame(width: 134).padding(.leading, 16).padding(.trailing, 12)
                Divider()
                Group {
                    if mode == .sculpt {
                        VStack(spacing: 10) {
                            if workspace.renderStyle == .cubes && workspace.paintsIn3D { voxelTools }
                            SculptureViewport(
                                workspace: workspace,
                                showsControls: true,
                                fit: { fitCamera() },
                                focusCanvas: { setEditorFocus(.canvas) }
                            )
                        }.padding(16)
                    } else {
                        sliceWorkspace.padding(16)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    SculptureCanvasKeyboard(focus: canvasFocus, key: { handleCanvasKey($0) })
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            canvasFocus.isFocused && !showingCommands ? Brand.accent.opacity(0.45) : Color.clear,
                            lineWidth: 1
                        )
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            status
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Sculpt.3md").font(.caption).foregroundStyle(Brand.secondary)
                TextField("Sculpture title", text: $workspace.titleDraft)
                    .textFieldStyle(.plain).font(.system(size: 20, weight: .semibold))
                    .focused($focus, equals: .title).onSubmit { workspace.commitTitle() }
                    .accessibilityLabel("Sculpture title").accessibilityIdentifier("editor.document.title")
                if let validation = workspace.titleValidation {
                    Text(validation).font(.caption).foregroundStyle(.red)
                }
            }
            .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            Menu("File") {
                Button("New empty sculpture") { requestReplacement(.blank) }
                Menu("New cube volume") {
                    ForEach([16, 32, 64, 128, 256], id: \.self) { size in
                        Button("\(size) × \(size) × \(size)") { requestReplacement(.volume(size)) }
                    }
                }
                Button("Open sculpture…") { requestReplacement(.open) }
                Button("New composition…") { sheet = .composition(nil) }
                Button("New sparse world…") { sheet = .world(nil) }
                Divider()
                Button("Insert 3md into a new composition…") { openInsertion(.composition, kind: .files) }
                Button("Insert 3md into a new world…") { openInsertion(.world, kind: .files) }
                Divider()
                Button("Save readable 3md…") { save(format: .readable) }
            }
            .accessibilityIdentifier("editor.document.file")
            Button("Examples") { sheet = .examples }.accessibilityIdentifier("editor.examples")
            Button(saveJob.isRunning ? "Preparing…" : "Save") { save() }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("editor.document.save")
                .help("Save compressed voxel data as .3mdb. File also offers readable .3md.")
                .disabled(saveJob.isRunning)
            Menu("Export") {
                Button("Image (PNG)") { export(png: true) }
                Button("ASCII text") { export(png: false) }
                Divider()
                Button("GIF, video or OBJ…") { openExportStudio() }
            }
            .accessibilityIdentifier("editor.export")
            Button {
                toggleCommands()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                    Text("Commands")
                    Text("⌘K").font(.caption).foregroundStyle(Brand.secondary)
                }
            }
            .keyboardShortcut("k").accessibilityLabel("Search editor commands")
            .accessibilityIdentifier("editor.commands.open")
        }
        .buttonStyle(.bordered).controlSize(.large)
    }

    private var modeSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(SculptureEditorMode.allCases) { option in
                Button {
                    changeMode(option)
                } label: {
                    Label(option.rawValue, systemImage: option == .sculpt ? "cube" : "square.grid.3x3")
                        .font(.callout.weight(.medium)).frame(width: 94, height: 32)
                        .background(mode == option ? Brand.paper : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).keyboardShortcut(option == .sculpt ? "1" : "2")
                .accessibilityLabel(option == .sculpt ? "Sculpt mode, 3D canvas" : "Slice mode, character editor")
                .accessibilityIdentifier("editor.mode.\(option == .sculpt ? "sculpt" : "slice")")
                .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
        }
        .padding(3).background(Brand.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
    }

    private var layers: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Slices").font(.headline)
                Spacer()
                Menu {
                    Button("Add empty slice") { addLayer() }.disabled(
                        workspace.sculpture.depth == Sculpture.maximumDimension
                    )
                    Button("Duplicate selected slice") { addLayer(duplicate: true) }.disabled(
                        workspace.sculpture.depth == Sculpture.maximumDimension
                    )
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Add or duplicate slice").accessibilityIdentifier("editor.slice.add-menu")
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(0..<workspace.sculpture.depth, id: \.self) { index in
                            Button {
                                clickedSidebarLayer = index == workspace.layer ? nil : index
                                workspace.layer = index
                            } label: {
                                HStack(spacing: 8) {
                                    SliceThumbnail(
                                        glyphs: workspace.sculpture.layers[index],
                                        width: workspace.sculpture.width,
                                        height: workspace.sculpture.height,
                                        occupiedCount: workspace.sculpture.occupiedCount(inLayer: index)
                                    ).frame(
                                        width: 32,
                                        height: 32
                                    )
                                    Text("\(index + 1)").font(.callout.monospacedDigit())
                                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                    Spacer(minLength: 0)
                                    if index == workspace.layer {
                                        Image(systemName: "checkmark").font(.caption).foregroundStyle(Brand.accent)
                                    }
                                }
                                .padding(8).background(
                                    index == workspace.layer ? Brand.accent.opacity(0.13) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).id(index)
                            .accessibilityLabel("Slice \(index + 1)")
                            .accessibilityValue(
                                "\(workspace.sculpture.occupiedCount(inLayer: index)) characters"
                            )
                            .accessibilityIdentifier("editor.slice.\(index)")
                            .accessibilityAddTraits(index == workspace.layer ? .isSelected : [])
                        }
                    }
                }
                .onAppear { proxy.scrollTo(workspace.layer, anchor: .center) }
                .onChange(of: workspace.layer) { _, layer in
                    let selectedInSidebar = clickedSidebarLayer == layer
                    clickedSidebarLayer = nil
                    if !selectedInSidebar { proxy.scrollTo(layer, anchor: .center) }
                }
                .onChange(of: workspace.sculpture.depth) { _, _ in proxy.scrollTo(workspace.layer, anchor: .center) }
            }
            Text("\(workspace.sculpture.width) × \(workspace.sculpture.height) cells")
                .font(.caption).foregroundStyle(Brand.secondary).padding(.bottom, 10)
        }
        .padding(.top, 18)
    }

    private var sliceWorkspace: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Slice \(workspace.layer + 1)").font(.title3.weight(.semibold))
                    Spacer()
                    Text("X \(workspace.column + 1)  Y \(workspace.row + 1)")
                        .font(.callout.monospacedDigit()).foregroundStyle(Brand.secondary)
                }
                LayerGrid(
                    sculpture: workspace.sculpture,
                    layer: workspace.layer,
                    column: workspace.column,
                    row: workspace.row,
                    showPreviousLayer: workspace.showPreviousLayer,
                    stroke: { workspace.paint($0, start: $1) },
                    finishStroke: { workspace.endStroke() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Toggle("Show previous slice", isOn: $workspace.showPreviousLayer)
                    .toggleStyle(.checkbox).disabled(workspace.layer == 0)
                    .accessibilityIdentifier("editor.slice.previous")
                Text("Arrow keys select a cell. Space applies the current tool.")
                    .font(.caption).foregroundStyle(Brand.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("3D reference").font(.callout.weight(.medium))
                        Spacer()
                        Button("Expand") { changeMode(.sculpt) }.buttonStyle(.borderless)
                            .accessibilityIdentifier("editor.reference.expand")
                    }
                    SculptureViewport(
                        workspace: workspace,
                        showsControls: false,
                        fit: { fitCamera() },
                        focusCanvas: { setEditorFocus(.canvas) }
                    )
                    .frame(height: 170)
                    drawingTools
                    DisclosureGroup("Selected cell", isExpanded: $showingCellControls) {
                        VStack(alignment: .leading, spacing: 10) {
                            Stepper(
                                "X: \(workspace.column + 1)",
                                value: $workspace.column,
                                in: 0...(workspace.sculpture.width - 1)
                            )
                            .accessibilityIdentifier("editor.cell.x")
                            Stepper(
                                "Y: \(workspace.row + 1)",
                                value: $workspace.row,
                                in: 0...(workspace.sculpture.height - 1)
                            )
                            .accessibilityIdentifier("editor.cell.y")
                            Button(selectedCellAction) { paintSelectedCell() }.buttonStyle(.bordered)
                                .accessibilityIdentifier("editor.cell.apply")
                        }.padding(.top, 8)
                    }
                    .accessibilityIdentifier("editor.cell.controls")
                }
            }
            .frame(width: 230)
        }
    }

    private var drawingTools: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Editing tool", selection: $workspace.tool) {
                ForEach(SculptureEditingTool.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("editor.tool")
            if !workspace.erase {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 6)], spacing: 6) {
                    ForEach(Sculpture.palette, id: \.self) { glyph in
                        Button {
                            workspace.brush = glyph
                        } label: {
                            Text(String(UnicodeScalar(glyph))).font(
                                .system(size: 18, weight: .medium, design: .monospaced)
                            )
                            .frame(maxWidth: .infinity).frame(height: 34)
                            .background(
                                workspace.brush == glyph ? Brand.accent.opacity(0.16) : Brand.secondary.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 6).strokeBorder(
                                    workspace.brush == glyph ? Brand.accent : Color.clear
                                )
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityLabel("Paint \(String(UnicodeScalar(glyph)))")
                        .accessibilityIdentifier("editor.brush.\(glyph)")
                        .accessibilityAddTraits(workspace.brush == glyph ? .isSelected : [])
                    }
                }
            }
            if workspace.tool != .fill {
                HStack(spacing: 10) {
                    Text("Size").font(.callout).foregroundStyle(Brand.secondary)
                    Picker("Brush size", selection: $workspace.brushSize) {
                        Text("1").tag(1); Text("3").tag(3); Text("5").tag(5)
                    }
                    .pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("editor.brush.size")
                }
            }
            Text(
                workspace.tool == .fill
                    ? "Fill a connected region of matching characters."
                    : workspace.erase
                        ? "Drag to erase characters from this slice."
                        : "Drag to draw with \(String(UnicodeScalar(workspace.brush)))."
            )
            .font(.caption).foregroundStyle(Brand.secondary)
        }
    }

    private var voxelTools: some View {
        HStack(spacing: 12) {
            Picker("Cube tool", selection: $workspace.tool) {
                ForEach(SculptureEditingTool.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 180).accessibilityIdentifier("editor.voxel.tool")
            Menu {
                ForEach(Sculpture.palette, id: \.self) { glyph in
                    Button("\(SculptureVoxelRasterizer.name(for: glyph)) · \(String(UnicodeScalar(glyph)))") {
                        workspace.brush = glyph
                    }
                }
            } label: {
                let tint = SculptureVoxelRasterizer.color(for: workspace.brush)
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(Color(red: tint.red, green: tint.green, blue: tint.blue))
                        .frame(width: 14, height: 14)
                    Text(SculptureVoxelRasterizer.name(for: workspace.brush))
                }
            }.accessibilityLabel("Cube material").accessibilityIdentifier("editor.voxel.material")
            Spacer()
            Text(
                workspace.tool == .draw
                    ? "Click a face to add. Drag for a stroke."
                    : workspace.tool == .erase
                        ? "Click a cube to remove it." : "Fill matching cells in the clicked slice."
            )
            .font(.caption).foregroundStyle(Brand.secondary)
        }.padding(.horizontal, 4)
    }

    private var status: some View {
        HStack(spacing: 12) {
            Text(workspace.message).lineLimit(1).help(workspace.message).accessibilityIdentifier(
                "editor.status.message"
            )
            if saveJob.isRunning {
                ProgressView().controlSize(.small)
                Button("Cancel save") { saveJob.cancel() }
                    .accessibilityIdentifier("editor.document.save.cancel")
            }
            Spacer()
            Text(workspace.isDirty ? "Unsaved changes" : "No unsaved changes").fixedSize()
                .accessibilityIdentifier("editor.status.saved")
            Text("\(workspace.sculpture.occupiedCount) characters").fixedSize()
        }
        .font(.caption).foregroundStyle(Brand.secondary).padding(.horizontal, 20).padding(.vertical, 10)
    }

    private var selectedCellAction: String {
        workspace.tool == .fill
            ? "Fill from selected cell" : workspace.erase ? "Erase selected cell" : "Paint selected cell"
    }

    private var commands: [SculptureEditorAction] {
        [
            action(
                "render.cubes",
                "Show translucent cubes",
                "View the same 3md volume as colored cube faces.",
                "cube.transparent",
                "voxel transparent geometry",
                perform: {
                    workspace.renderStyle = .cubes; changeMode(.sculpt); fitCamera()
                }
            ),
            action(
                "render.ascii",
                "Show ASCII",
                "View the same volume as characters.",
                "textformat",
                "glyph characters",
                perform: {
                    workspace.renderStyle = .ascii; changeMode(.sculpt); fitCamera()
                }
            ),
            action(
                "voxel.paint",
                "Paint cubes",
                "Add on a face, erase a cube, or fill its slice.",
                "pencil.tip",
                "voxel surface draw sculpt",
                perform: {
                    workspace.renderStyle = .cubes; workspace.paintsIn3D = true; changeMode(.sculpt)
                }
            ),
            action(
                "voxel.orbit",
                "Orbit sculpture",
                "Drag to look around without painting.",
                "rotate.3d",
                "camera rotate",
                perform: {
                    workspace.paintsIn3D = false; changeMode(.sculpt)
                }
            ),
            action(
                "document.volume",
                "New 64-cubed volume",
                "Start a larger empty cube sculpture.",
                "cube",
                "world blank large",
                perform: {
                    requestReplacement(.volume(64))
                }
            ),
            action(
                "document.volume.256",
                "New 256-cubed volume",
                "Start a full-size editable cube sculpture.",
                "cube",
                "world solar blank huge maximum large 256",
                perform: { requestReplacement(.volume(256)) }
            ),
            action(
                "gallery.open",
                "Open examples",
                "Choose a shape or a map.",
                "square.grid.2x2",
                "gallery templates",
                perform: { sheet = .examples }
            ),
            action(
                "world.new",
                "Explore a sparse world",
                "Place reusable models without a fixed cube boundary.",
                "globe",
                "infinite grow distance detail world chunks sparse",
                perform: { sheet = .world(nil) }
            ),
            action(
                "composition.new",
                "Compose reusable 3md models",
                "Place a whole model with one character in a tile map.",
                "square.grid.3x3",
                "composition references tile tree castle map assembly",
                perform: { sheet = .composition(nil) }
            ),
            action(
                "document.open",
                "Open sculpture file",
                "Choose a readable .3md or compact .3mdb sculpture.",
                "folder",
                "load import 3md 3mdb binary compact",
                perform: { requestReplacement(.open) }
            ),
            action(
                "document.save",
                "Save compact 3md file",
                "Compress editable voxels into a .3mdb file.",
                "square.and.arrow.down",
                "write document 3mdb binary compact",
                enabled: !saveJob.isRunning,
                perform: { save() }
            ),
            action(
                "document.save.readable",
                "Save readable 3md file",
                "Save text layers for sharing with other 3md tools.",
                "doc.text",
                "write document 3md markdown text",
                enabled: !saveJob.isRunning,
                perform: { save(format: .readable) }
            ),
            action(
                "document.new",
                "New empty sculpture",
                "Start with an empty slice.",
                "doc.badge.plus",
                "blank new",
                perform: { requestReplacement(.blank) }
            ),
            action(
                "export.studio",
                "Export GIF, video or OBJ",
                "Create an animation or a 3D voxel mesh.",
                "square.and.arrow.up",
                "mp4 movie share mesh",
                perform: { openExportStudio() }
            ),
            action(
                "export.png",
                "Export PNG image",
                "Export the current camera view.",
                "photo",
                "image screenshot",
                perform: { export(png: true) }
            ),
            action(
                "export.text",
                "Export ASCII text",
                "Export characters from the current camera.",
                "text.alignleft",
                "text plain",
                perform: { export(png: false) }
            ),
            action(
                "view.sculpt",
                "Show Sculpt mode",
                "Focus on the full 3D canvas. ⌘1",
                "cube",
                "view explore",
                perform: { changeMode(.sculpt) }
            ),
            action(
                "view.slice",
                "Show Slice mode",
                "Draw into the selected character layer. ⌘2",
                "square.grid.3x3",
                "view edit grid",
                perform: { changeMode(.slice) }
            ),
            action(
                "tool.draw",
                "Draw characters",
                "Use the drawing brush in Slice mode.",
                "pencil.tip",
                "paint brush",
                perform: { chooseTool(.draw) }
            ),
            action(
                "tool.erase",
                "Erase characters",
                "Use the eraser in Slice mode.",
                "eraser",
                "remove brush",
                perform: { chooseTool(.erase) }
            ),
            action(
                "tool.fill",
                "Fill a region",
                "Fill connected characters in Slice mode.",
                "drop",
                "paint bucket flood",
                perform: { chooseTool(.fill) }
            ),
            action(
                "slice.add",
                "Add empty slice",
                "Insert a new slice after the selection.",
                "plus.square",
                "layer depth",
                enabled: workspace.sculpture.depth < Sculpture.maximumDimension,
                perform: { addLayer() }
            ),
            action(
                "slice.duplicate",
                "Duplicate slice",
                "Copy the selected layer into a new slice.",
                "square.on.square",
                "layer copy",
                enabled: workspace.sculpture.depth < Sculpture.maximumDimension,
                perform: { addLayer(duplicate: true) }
            ),
            action(
                "slice.clear",
                "Clear selected slice",
                "Remove its characters; Undo restores them.",
                "trash",
                "layer delete empty",
                perform: { workspace.clearLayer() }
            ),
            action(
                "slice.rotate",
                "Rotate slice 90°",
                "Rotate the selected square grid clockwise.",
                "rotate.right",
                "layer turn",
                enabled: workspace.sculpture.width == workspace.sculpture.height,
                perform: { workspace.rotateLayer() }
            ),
            action(
                "history.undo",
                "Undo",
                "Restore the previous document edit.",
                "arrow.uturn.backward",
                "history revert",
                enabled: workspace.canUndo,
                perform: { workspace.undo() }
            ),
            action(
                "history.redo",
                "Redo",
                "Reapply the last undone edit.",
                "arrow.uturn.forward",
                "history repeat",
                enabled: workspace.canRedo,
                perform: { workspace.redo() }
            ),
            action(
                "camera.orbit",
                "Orbit camera view",
                "Reset to the perspective view.",
                "viewfinder",
                "perspective reset",
                perform: { showViewpoint(.perspective) }
            ),
            action(
                "camera.front",
                "Front camera view",
                "Look straight at the sculpture.",
                "square",
                "front view",
                perform: { showViewpoint(.front) }
            ),
            action(
                "camera.side",
                "Side camera view",
                "Look along the side of the sculpture.",
                "rectangle.portrait",
                "side view",
                perform: { showViewpoint(.side) }
            ),
            action(
                "camera.above",
                "Camera view from above",
                "Look down at the sculpture or map.",
                "square.3.layers.3d",
                "top above view",
                perform: { showViewpoint(.above) }
            ),
            action(
                "camera.fit",
                "Fit sculpture in canvas",
                "Frame the object at a comfortable size.",
                "arrow.up.left.and.arrow.down.right",
                "zoom size center",
                perform: { fitCamera() }
            ),
        ]
            + SculptureInsertionPalette.actions(
                enabled: SculptureEditorCommandAvailability.documentActionsAvailable(
                    sheet: sheetContext,
                    activity: activity
                )
            ) { destination, kind in
                openInsertion(destination, kind: kind)
            }
    }

    private func action(
        _ id: String,
        _ title: String,
        _ detail: String,
        _ symbol: String,
        _ keywords: String,
        enabled: Bool = true,
        perform: @escaping @MainActor () -> Void
    ) -> SculptureEditorAction {
        SculptureEditorAction(
            id: id,
            title: title,
            detail: detail,
            symbol: symbol,
            keywords: keywords,
            enabled: enabled,
            perform: perform
        )
    }

    private func toggleCommands() {
        if showingCommands {
            closeCommands()
        } else {
            previousFocus = canvasFocus.isFocused ? .canvas : focus
            paletteFocusHandoff = nil
            focus = nil
            canvasFocus.release()
            NSApp.keyWindow?.makeFirstResponder(nil)
            showingCommands = true
        }
    }

    private func closeCommands() {
        paletteFocusHandoff = previousFocus ?? .canvas
        focus = nil
        showingCommands = false
    }

    private func completePaletteDismissal() {
        guard !showingCommands, let target = paletteFocusHandoff else { return }
        paletteFocusHandoff = nil
        setEditorFocus(target)
    }

    private func setEditorFocus(_ target: EditorFocus) {
        if paletteFocusHandoff != nil {
            paletteFocusHandoff = target
        } else if target == .canvas {
            focus = nil
            canvasFocus.acquire()
        } else {
            canvasFocus.release()
            focus = target
        }
    }

    private func changeMode(_ mode: SculptureEditorMode) {
        workspace.endStroke()
        self.mode = mode
        setEditorFocus(.canvas)
    }

    private func chooseTool(_ tool: SculptureEditingTool) {
        workspace.tool = tool
        if workspace.renderStyle == .cubes && mode == .sculpt {
            workspace.paintsIn3D = true
            setEditorFocus(.canvas)
        } else {
            changeMode(.slice)
        }
    }

    private func moveCell(x: Int, y: Int) {
        workspace.column = min(workspace.sculpture.width - 1, max(0, workspace.column + x))
        workspace.row = min(workspace.sculpture.height - 1, max(0, workspace.row + y))
    }

    private func handleCanvasKey(_ key: SculptureCanvasKey) -> Bool {
        guard mode == .slice || (workspace.renderStyle == .cubes && workspace.paintsIn3D), !showingCommands else {
            return false
        }
        switch key {
        case .left: moveCell(x: -1, y: 0)
        case .right: moveCell(x: 1, y: 0)
        case .up: moveCell(x: 0, y: -1)
        case .down: moveCell(x: 0, y: 1)
        case .apply: paintSelectedCell()
        }
        return true
    }

    private func dismissPaletteForDocumentAction() {
        if showingCommands { closeCommands() }
    }

    private func paintSelectedCell() {
        workspace.paint(SculptureCell(x: workspace.column, y: workspace.row, z: workspace.layer), start: true)
        workspace.endStroke()
    }

    private func addLayer(duplicate: Bool = false) {
        let index = workspace.layer
        let depth = workspace.sculpture.depth
        workspace.change { try $0.addLayer(after: index, duplicate: duplicate) }
        if workspace.sculpture.depth == depth + 1 { workspace.layer = index + 1; changeMode(.slice) }
    }

    private func showViewpoint(_ viewpoint: SculptureViewpoint) {
        workspace.setViewpoint(viewpoint)
        fitCamera()
        changeMode(.sculpt)
    }

    private func fitCamera() {
        workspace.camera.fitsVolume = true
        workspace.camera.panX = 0
        workspace.camera.panY = 0
        if workspace.renderStyle == .cubes { workspace.camera.zoom = 1; return }
        var camera = workspace.camera
        camera.zoom = 0.5
        let frame = SculptureProjection.frame(workspace.sculpture, camera: camera)
        let occupied = frame.pixels.indices.filter { frame.pixels[$0] != nil }
        guard !occupied.isEmpty else { return }
        let xs = occupied.map { $0 % frame.columns }
        let ys = occupied.map { $0 / frame.columns }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return }
        let horizontal = Double(frame.columns) * 0.78 / Double(maxX - minX + 1)
        let vertical = Double(frame.rows) * 0.78 / Double(maxY - minY + 1)
        workspace.camera.zoom = max(0.5, min(2, 0.5 * min(horizontal, vertical)))
    }

    private func save(format: SculptureStorageFormat = .compact) {
        guard !saveJob.isRunning, !exporting else { return }
        guard workspace.commitTitle() else { setEditorFocus(.title); return }
        saveJob.start(workspace.sculpture, format: format, documentGeneration: workspace.documentGeneration)
    }

    private func openExportStudio() {
        guard workspace.commitTitle() else { setEditorFocus(.title); return }
        sheet = .exportStudio(workspace.sculpture, workspace.camera, workspace.renderStyle, workspace.cubeOpacity)
    }

    /// A model replaces the document through the same dirty-work confirmation as every other replacement. A
    /// composition or world opens as a new, unmodified draft, the way Open routes those scenes; the main document
    /// stays in place under its sheet.
    private func openFromGallery(_ opened: SculptureGalleryOpened) {
        let entry = opened.entry
        switch SculptureGalleryDestination(opened) {
        case .document(_, let sculpture, let geometry):
            requestReplacement(.example(entry, sculpture, geometry))
        case .composition(let draft):
            sheet = .composition(draft)
            workspace.message =
                "Opened \(entry.title) from the gallery. Its model references are preserved in the tile editor."
        case .world(let draft):
            sheet = .world(draft)
            workspace.message =
                "Opened \(entry.title) from the gallery. Distant placements remain stored outside the rendered area."
        }
    }

    private func requestReplacement(_ replacement: Replacement) {
        self.replacement = replacement
        if workspace.isDirty { confirmReplacement = true } else { performReplacement() }
    }

    private func performReplacement() {
        switch replacement {
        case .blank: workspace.replace(with: .blank()); changeMode(.slice)
        case .volume(let size):
            do {
                let volume = try Sculpture(
                    title: "Untitled",
                    width: size,
                    height: size,
                    layers: Array(repeating: Array(repeating: Sculpture.empty, count: size * size), count: size)
                )
                workspace.replace(with: volume)
                workspace.renderStyle = .cubes
                workspace.paintsIn3D = true
                fitCamera()
                changeMode(.sculpt)
            } catch { workspace.error = error.localizedDescription }
        case .example(let entry, let sculpture, let geometry):
            workspace.replace(with: sculpture, preparedGeometry: geometry)
            workspace.camera.pitch = ["Maps", "Worlds", "Space"].contains(entry.category) ? 0.7 : 0.35
            fitCamera()
            changeMode(.sculpt)
            workspace.message = "Opened \(entry.title), \(SculptureGalleryBrowserModel.sizeLabel(for: entry))."
        case .composition(let voxels):
            workspace.replace(with: voxels)
            workspace.renderStyle = .cubes
            workspace.paintsIn3D = false
            fitCamera()
            changeMode(.sculpt)
            workspace.message =
                "Opened an editable voxel copy. Save the reference document separately to keep shared models."
        case .open:
            importKind = .document
            linkedRoot = nil
            importing = true
        case nil: break
        }
        replacement = nil
    }

    private func export(png: Bool) {
        guard !saveJob.isRunning, !exporting else { return }
        let data =
            png
            ? SculptureImageRenderer.png(
                sculpture: workspace.sculpture,
                camera: workspace.camera,
                style: workspace.renderStyle,
                opacity: workspace.cubeOpacity
            ) : Data(workspace.frame.text.utf8)
        guard let data else { workspace.error = "The image couldn’t be created. Try exporting ASCII text."; return }
        exportFile = SculptureExport(data: data)
        exportType = png ? .png : .plainText
        pendingSave = nil
        exporting = true
    }

    private func startOpening(_ url: URL) {
        cancelOpening()
        let identifier = UUID()
        openingGeneration = identifier
        opening = true
        openingTask = Task { await open(url, generation: identifier) }
    }

    private func cancelOpening() {
        openingGeneration = UUID()
        openingTask?.cancel()
        openingTask = nil
        opening = false
    }

    private func open(_ url: URL, generation: UUID) async {
        defer {
            if openingGeneration == generation { opening = false; openingTask = nil }
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let worker = Task.detached { () throws -> SculptureOpenedScene in
                try SculptureOpenedScene.read(url)
            }
            let opened = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            try Task.checkCancellation()
            guard openingGeneration == generation else { return }
            switch opened.scene {
            case .voxels(let sculpture):
                workspace.replace(with: sculpture, opened: true)
                portableVoxelSnapshot = opened.snapshot
                portableVoxelGeneration = workspace.documentGeneration
                fitCamera()
                changeMode(.sculpt)
            case .composition(let composition):
                sheet = .composition(composition, portableSnapshot: opened.snapshot)
                workspace.message = "Opened a composition. Its model references are preserved in the tile editor."
            case .world(let world):
                sheet = .world(world, portableSnapshot: opened.snapshot)
                workspace.message = "Opened a sparse world. Distant placements remain stored outside the rendered area."
            }

        } catch is CancellationError {} catch {
            guard openingGeneration == generation else { return }
            switch SculptureLinkedSession.openFailure(error, file: url.lastPathComponent) {
            case .requestProjectFolder: requestProjectFolder(for: url)
            case .report(let message): workspace.error = message
            }
        }
    }

    /// A linked root reads its models from files in a project folder, so Open asks for that folder next.
    private func requestProjectFolder(for root: URL) {
        linkedRoot = root
        importKind = .projectFolder
        workspace.message = "\(root.lastPathComponent) is a linked composition. Choose its project folder to open it."
        importing = true
    }

    /// Resolves a linked root with the chosen folder, then shows it view-only, or its repair view when it fails.
    /// Cancelling opens nothing. The folder grant lives only in the session.
    private func startLinkedOpening(root: URL, folder: URL) {
        cancelOpening()
        let identifier = UUID()
        openingGeneration = identifier
        opening = true
        openingTask = Task {
            defer {
                if openingGeneration == identifier { opening = false; openingTask = nil }
            }
            let outcome = await SculptureLinkedSession.open(root: root, folder: folder)
            guard openingGeneration == identifier, !Task.isCancelled else {
                if case .opened(let session) = outcome { session.cancel() }
                return
            }
            switch outcome {
            case .cancelled: break
            case .refused(let message): workspace.error = message
            case .opened(let session):
                sheet = .linked(session)
                workspace.message =
                    session.draft != nil
                    ? "Opened \(session.title) view only, with models read from \(session.folder.name)."
                    : "\(session.fileName) has links that need attention. Nothing was changed."
            }
        }
    }

    private var exportFilename: String {
        pendingPortable?.scene.title ?? graphSaveSession?.document.title ?? pendingSave?.sculpture.title
            ?? workspace.sculpture.title
    }

    private func completeFileExport(_ result: Result<URL, any Error>) {
        switch result {
        case .success:
            if let pendingPortable {
                retainPortableSnapshot(pendingPortable.snapshot)
                workspace.message = "Exported a portable ThreeMD copy of \(pendingPortable.scene.title)."
                restoreGraphAfterSave()
            } else if let graphSaveSession {
                workspace.message = "Saved \(graphSaveSession.document.title) with reusable model references."
                restoreGraphAfterSave(written: true)
            } else if let pendingSave {
                workspace.markSaved(pendingSave)
            } else {
                workspace.message = "Exported the current camera view."
            }
        case .failure(let error): workspace.error = error.localizedDescription
        }
        cancelFileExport()
    }

    private func cancelFileExport() {
        pendingSave = nil
        pendingPortable = nil
        portableSaveJob.cancel()
        saveJob.cancel()
        restoreGraphAfterSave()
    }

    private var portableActions: SculpturePortableActions? {
        guard !opening, !exporting, !saveJob.isRunning, !graphSaveJob.isRunning,
            !portableSaveJob.isRunning, graphSaveSession == nil
        else { return nil }
        switch sheet {
        case .composition(let draft):
            return Self.portableActions(
                for: draft,
                exportReadable: { exportPortable(format: .readable) },
                exportBinary: { exportPortable(format: .binary) }
            )
        case .world(let draft):
            guard draft.sharedEdit == nil, !draft.isMakingUnique, !draft.isOpeningModel else { return nil }
        case .linked, .examples, .exportStudio: return nil
        case nil: break
        }
        return SculpturePortableActions(
            exportReadable: { exportPortable(format: .readable) },
            exportBinary: { exportPortable(format: .binary) }
        )
    }

    /// The sheet over the window, reduced to what command availability depends on.
    private var sheetContext: SculptureSheetContext {
        switch sheet {
        case .composition(let draft): .composition(draft)
        case .linked(let session): .linked(session)
        case .world(let draft): .world(draft)
        case .examples, .exportStudio: .other
        case nil: .none
        }
    }

    /// Work in progress that blocks new document actions, read from the window's jobs.
    private var activity: SculptureEditorActivity {
        SculptureEditorActivity(
            isOpening: opening,
            isExporting: exporting,
            isSaving: saveJob.isRunning,
            isGraphSaving: graphSaveJob.isRunning,
            isPortableSaving: portableSaveJob.isRunning,
            hasGraphSaveSession: graphSaveSession != nil
        )
    }

    /// File menu insertion is available only while an open composition or world sheet is settled and unobstructed.
    private var insertionActions: SculptureInsertionActions? {
        SculptureEditorCommandAvailability.insertionActions(sheet: sheetContext, activity: activity)
    }

    /// Reload Linked Files follows an open linked session.
    private var linkedActions: SculptureLinkedActions? {
        SculptureEditorCommandAvailability.linkedActions(sheet: sheetContext, activity: activity)
    }

    /// Menu Undo and Redo follow the frontmost sheet. A covered main sculpture is never their target.
    private var sheetHistory: SculptureHistoryActions? {
        SculptureEditorCommandAvailability.sheetHistory(sheet: sheetContext, activity: activity)
    }

    private func syncOpenSheet() {
        workspace.hasOpenSheet = sheet != nil || graphSaveSession != nil
    }

    /// Opens an empty composition or world and presents its importer, with no starter models to replace.
    private func openInsertion(_ destination: SculptureInsertionDestination, kind: SculptureInsertionKind) {
        // The palette runs this a moment after it closes, so availability is checked again here.
        guard SculptureEditorCommandAvailability.documentActionsAvailable(sheet: sheetContext, activity: activity)
        else { return }
        switch destination {
        case .composition:
            let draft = SculptureCompositionDraft.insertionCanvas()
            draft.requestInsertion(kind)
            sheet = .composition(draft)
        case .world:
            let draft = SculptureWorldDraft.insertionCanvas()
            draft.requestInsertion(kind)
            sheet = .world(draft)
        }
    }

    /// A composition may export only its settled parent, after any insertion decision or shared edit finishes.
    @MainActor
    internal static func portableActions(
        for draft: SculptureCompositionDraft,
        exportReadable: @escaping @MainActor () -> Void,
        exportBinary: @escaping @MainActor () -> Void
    ) -> SculpturePortableActions? {
        guard draft.sharedEdit == nil, !draft.isBusy, !draft.isViewOnly else { return nil }
        return SculpturePortableActions(exportReadable: exportReadable, exportBinary: exportBinary)
    }

    private func exportPortable(format: SculpturePortableFormat) {
        guard portableActions != nil else { return }
        dismissPaletteForDocumentAction()
        do {
            switch sheet {
            case .composition(let draft):
                pendingReferenceSave = try SculptureReferenceSaveSession(draft: .composition(draft))
                pendingPortableFormat = format
                sheet = nil
            case .world(let draft):
                pendingReferenceSave = try SculptureReferenceSaveSession(draft: .world(draft))
                pendingPortableFormat = format
                sheet = nil
            case nil:
                guard workspace.commitTitle() else { return }
                portableSaveJob.start(
                    .voxels(workspace.sculpture),
                    preserving: portableVoxelGeneration == workspace.documentGeneration ? portableVoxelSnapshot : nil,
                    format: format,
                    documentGeneration: workspace.documentGeneration
                )
            default: break
            }
        } catch { workspace.error = SculpturePortableDiagnostic.message(error) }
    }

    private func preparePortableGraph(_ session: SculptureReferenceSaveSession, format: SculpturePortableFormat) {
        workspace.referenceDraftIsDirty = session.draft.hasChanges
        switch session.draft {
        case .composition(let draft):
            guard case .composition(let document) = session.document else { return }
            portableSaveJob.start(
                .composition(document),
                preserving: draft.portableSnapshot,
                format: format,
                documentGeneration: workspace.documentGeneration
            )
        case .world(let draft):
            guard case .world(let document) = session.document else { return }
            portableSaveJob.start(
                .world(document),
                preserving: draft.portableSnapshot,
                format: format,
                documentGeneration: workspace.documentGeneration
            )
        }
    }

    private func retainPortableSnapshot(_ snapshot: SculptureThreeMDSnapshot) {
        if let graphSaveSession {
            switch graphSaveSession.draft {
            case .composition(let draft): draft.retainPortableSnapshot(snapshot)
            case .world(let draft): draft.retainPortableSnapshot(snapshot)
            }
        } else {
            portableVoxelSnapshot = snapshot
            portableVoxelGeneration = workspace.documentGeneration
        }
    }

    private func saveGraph(_ session: SculptureReferenceSaveSession) {
        graphSaveSession = session
        workspace.referenceDraftIsDirty = session.draft.hasChanges
        guard !saveJob.isRunning, !exporting else { restoreGraphAfterSave(); return }
        graphSaveJob.start(session.document)
    }

    private func restoreGraphAfterSave(written: Bool = false) {
        graphSaveJob.cancel()
        guard let graphSaveSession else { return }
        self.graphSaveSession = nil
        let retained = graphSaveSession.finish(written: written)
        workspace.referenceDraftIsDirty = retained.hasChanges
        switch retained {
        case .composition(let draft): sheet = .composition(draft)
        case .world(let draft): sheet = .world(draft)
        }
    }
}
