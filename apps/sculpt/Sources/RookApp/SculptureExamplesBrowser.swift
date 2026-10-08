import RookSculpture
import SwiftUI

/// Every built-in example in one gallery, grouped by kind and category with its size. Opening an entry generates and
/// prepares it on a worker with a visible stage, progress and Cancel; only a finished load reaches `choose`.
internal struct SculptureExamplesBrowser: View {
    internal let choose: @MainActor (SculptureGalleryOpened) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var model: SculptureGalleryBrowserModel

    internal init(
        model: SculptureGalleryBrowserModel = SculptureGalleryBrowserModel(),
        choose: @escaping @MainActor (SculptureGalleryOpened) -> Void
    ) {
        _model = State(initialValue: model)
        self.choose = choose
    }

    internal var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            filters
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    ForEach(model.sections) { section in
                        sectionView(section)
                    }
                }
                .padding(.bottom, 8)
                if model.sections.isEmpty {
                    ContentUnavailableView.search(text: model.search)
                }
            }
            if let loading = model.loading {
                loadingBar(loading)
            } else if let error = model.error {
                errorBar(error)
            }
        }
        .padding(24)
        .frame(minWidth: 860, idealWidth: 1_040, minHeight: 620, idealHeight: 760)
        .background(Brand.paper)
        .foregroundStyle(Brand.ink)
        .tint(Brand.accent)
        .onChange(of: model.loading?.stage) { _, stage in
            guard let stage, let loading = model.loading else { return }
            AccessibilityNotification.Announcement("\(stage.label) \(loading.entry.title)").post()
        }
        // Closing the gallery stops its opening and thumbnails, and nothing they produced is published.
        .onDisappear { model.cancelAll() }
    }


    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Every example, from 16 cells to 256 on each axis").font(.system(size: 24, weight: .semibold))
                Text(
                    "Models, compositions and sparse worlds. Small models preview right away; larger ones preview when you ask, and every example opens with progress you can cancel."
                )
                .font(.callout).foregroundStyle(Brand.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            // Stops the opening and thumbnails before the sheet leaves, so a load finishing meanwhile never opens.
            Button("Done") { model.close { dismiss() } }
                .keyboardShortcut(model.loading == nil ? .cancelAction : nil)
                .accessibilityIdentifier("gallery.done")
        }
    }

    private var filters: some View {
        HStack(spacing: 12) {
            TextField("Search examples", text: $model.search)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("gallery.search")
            Picker("Kind", selection: $model.kind) {
                Text("All kinds").tag(SculptureGalleryKind?.none)
                ForEach(SculptureGalleryKind.allCases, id: \.self) { kind in
                    Text(SculptureGalleryBrowserModel.title(for: kind)).tag(SculptureGalleryKind?.some(kind))
                }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 340)
            .accessibilityLabel("Kind")
            .accessibilityIdentifier("gallery.kind")
            Picker("Category", selection: $model.category) {
                ForEach(model.categories, id: \.self) { Text($0).tag($0) }
            }
            .frame(width: 210)
            .accessibilityIdentifier("gallery.category")
        }
    }

    private func sectionView(_ section: SculptureGalleryBrowserModel.Section) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(section.title).font(.title3.weight(.semibold))
                Text(section.entries.count == 1 ? "1 example" : "\(section.entries.count) examples")
                    .font(.callout).foregroundStyle(Brand.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("gallery.section.\(section.id)")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .top)],
                alignment: .leading,
                spacing: 20
            ) {
                ForEach(section.entries) { entry in
                    card(entry)
                }
            }
        }
    }

    private func card(_ entry: SculptureGalleryEntry) -> some View {
        let openLabel = SculptureGalleryBrowserModel.openLabel(for: entry)
        let spokenSize = SculptureGalleryBrowserModel.spokenSize(for: entry)
        return VStack(alignment: .leading, spacing: 8) {
            SculptureGalleryPreviewArea(entry: entry, model: model)
            // The section heading names the kind and category, so the title keeps the card's full width.
            Text(entry.title).font(.headline).lineLimit(1).help(entry.title)
            Text(entry.summary).font(.callout).foregroundStyle(Brand.secondary)
                .lineLimit(2).frame(height: 38, alignment: .top)
            VStack(alignment: .leading, spacing: 2) {
                Text(SculptureGalleryBrowserModel.cellsLabel(for: entry)).lineLimit(2)
                if let placements = SculptureGalleryBrowserModel.placementLabel(for: entry) {
                    Text(placements).lineLimit(1)
                }
            }
            .font(.caption.monospacedDigit()).foregroundStyle(Brand.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenSize)
            .accessibilityIdentifier("gallery.size.\(entry.id)")
            if let formula = entry.formula {
                Text(formula).font(.system(.caption2, design: .monospaced)).foregroundStyle(Brand.secondary)
                    .lineLimit(2).help(formula)
                    .accessibilityLabel("Formula: \(formula)")
            }
            // The entry being opened keeps its enabled button, so keyboard focus stays put while it loads.
            let isOpening = model.loading?.entry.id == entry.id
            Button(isOpening ? "Opening…" : openLabel) {
                guard !isOpening else { return }
                model.open(entry) { opened in choose(opened) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.loading != nil && !isOpening)
            .help(
                entry.kind == .model
                    ? "Open an editable copy of \(entry.title)" : "Open \(entry.title) in its own editor"
            )
            .accessibilityLabel(isOpening ? "Opening \(entry.title)" : "\(openLabel) \(entry.title), \(spokenSize)")
            .accessibilityIdentifier("gallery.open.\(entry.id)")
        }
        .padding(10)
        .background(Brand.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(entry.title). \(entry.summary)")
        .accessibilityIdentifier("gallery.entry.\(entry.id)")
    }


    // MARK: - Loading

    private func loadingBar(_ loading: SculptureGalleryBrowserModel.Loading) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Opening \(loading.entry.title)").font(.callout.weight(.semibold))
                Group {
                    if let fraction = loading.fraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                }
                .accessibilityLabel("Opening progress")
                .accessibilityValue(loading.description)
                .accessibilityIdentifier("gallery.loading.progress")
                Text("\(loading.description) · \(SculptureGalleryBrowserModel.sizeLabel(for: loading.entry))")
                    .font(.caption.monospacedDigit()).foregroundStyle(Brand.secondary)
                    .accessibilityIdentifier("gallery.loading.stage")
            }
            Button("Cancel") { model.cancelOpening() }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel opening \(loading.entry.title)")
                .accessibilityIdentifier("gallery.loading.cancel")
        }
        .padding(14)
        .background(Brand.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gallery.loading")
    }

    private func errorBar(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").accessibilityHidden(true)
            Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("gallery.error")
            Spacer()
            Button("OK") { model.dismissError() }
                .accessibilityIdentifier("gallery.error.dismiss")
        }
        .padding(14)
        .background(Brand.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// A card's thumbnail. Small models render as soon as the card appears; every larger entry shows Load preview and
/// renders a bounded thumbnail on a worker only when asked, so a large example never blocks the gallery.
private struct SculptureGalleryPreviewArea: View {
    let entry: SculptureGalleryEntry
    let model: SculptureGalleryBrowserModel

    var body: some View {
        ZStack {
            switch model.previews[entry.id] {
            case .ready(let preview)?:
                if let image = preview.image {
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                } else {
                    message("Nothing to preview")
                }
            case .loading?:
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    if !model.loadsPreviewAutomatically(entry) {
                        Button("Cancel") { model.cancelPreview(entry.id) }
                            .controlSize(.small)
                            .accessibilityLabel("Cancel the preview of \(entry.title)")
                            .accessibilityIdentifier("gallery.preview.cancel.\(entry.id)")
                    }
                }
            case .failed(let failure)?:
                VStack(spacing: 8) {
                    message("Preview unavailable")
                    Button("Try again") { model.requestPreview(entry, explicitly: true) }
                        .controlSize(.small)
                        .help(failure)
                        .accessibilityIdentifier("gallery.preview.load.\(entry.id)")
                }
            case nil:
                if model.loadsPreviewAutomatically(entry) {
                    ProgressView().controlSize(.small)
                } else {
                    placeholder
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .background(Color(red: 0.065, green: 0.085, blue: 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gallery.preview.\(entry.id)")
        .onAppear { model.requestPreview(entry) }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.white.opacity(0.8))
                .accessibilityHidden(true)
            Text(entry.kind == .world ? "Plan preview on request" : "Large preview on request")
                .font(.caption).foregroundStyle(.white.opacity(0.8))
            Button("Load preview") { model.requestPreview(entry, explicitly: true) }
                .controlSize(.small)
                .accessibilityLabel("Load a preview of \(entry.title)")
                .accessibilityIdentifier("gallery.preview.load.\(entry.id)")
        }
    }

    private var symbol: String {
        switch entry.kind {
        case .model: "cube"
        case .composition: "square.grid.3x3"
        case .world: "globe"
        }
    }

    private func message(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.white.opacity(0.8))
    }
}
