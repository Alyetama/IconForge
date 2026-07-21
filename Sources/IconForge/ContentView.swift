import AppKit
import SwiftUI

/// The same continuous-corner shape the pipeline masks with, so placeholders
/// and preview chrome line up with the real artwork.
struct Squircle: Shape {
    func path(in rect: CGRect) -> Path {
        Path(IconPipeline.squirclePath(in: rect))
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: GeneratorModel
    @State private var showingSettings = false

    var body: some View {
        HSplitView {
            InspectorPane(showingSettings: $showingSettings)
                .frame(minWidth: 340, idealWidth: 380, maxWidth: 460)
            PreviewPane()
                .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingSettings) { SettingsSheet() }
        .toolbar {
            // No principal item: the toolbar's own rounded background sizes to
            // the text baseline, so any symbol placed there pokes out the top.
            // The wordmark lives in the inspector header instead, where the
            // layout is ours to control.
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
    }
}

// MARK: - Inspector

private struct InspectorPane: View {
    @EnvironmentObject private var model: GeneratorModel
    @Binding var showingSettings: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                FieldGroup(title: "App name", symbol: "textformat", enabled: !model.isEditPending) {
                    TextField("Tidepool", text: $model.appName)
                        .textFieldStyle(.roundedBorder)
                }

                FieldGroup(title: "What it does", symbol: "text.alignleft", enabled: !model.isEditPending) {
                    // A plain multiline TextField beats TextEditor here: it takes
                    // focus on the first click and carries its own placeholder.
                    TextField("tracks daily water intake",
                              text: $model.appDescription,
                              axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }

                FieldGroup(title: "Subject", symbol: "circle.hexagonpath",
                           hint: model.isEditPending ? "kept as it is" : "optional — the model picks one",
                           enabled: !model.isEditPending) {
                    TextField("a water droplet", text: $model.subject)
                        .textFieldStyle(.roundedBorder)
                }

                FieldGroup(title: "Palette", symbol: "paintpalette",
                           hint: model.isEditPending
                               ? (model.pendingRecolour == nil ? "pick one to recolour this icon" : "will recolour this icon")
                               : "optional") {
                    PaletteField()
                }

                FieldGroup(title: "Style", symbol: "wand.and.stars",
                           hint: model.style.blurb) {
                    Picker("", selection: $model.style) {
                        ForEach(StyleVariant.allCases) { variant in
                            Text(variant.rawValue).tag(variant)
                        }
                    }
                    .labelsHidden()
                }

                FieldGroup(title: "Model", symbol: "cpu",
                           hint: model.isLoadingModels ? "reading agy models…" : nil) {
                    HStack(spacing: 8) {
                        Picker("", selection: $model.model) {
                            ForEach(model.modelChoices, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .labelsHidden()

                        Button {
                            model.loadModels()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(model.isLoadingModels)
                        .help("Re-read the list from `agy models`")
                    }
                }

                FieldGroup(title: "Finish", symbol: "sparkle", hint: model.finish.blurb) {
                    Picker("", selection: $model.finish) {
                        ForEach(IconFinish.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .labelsHidden()
                }

                FieldGroup(title: "Body size", symbol: "arrow.up.left.and.arrow.down.right",
                           hint: model.bodySize.blurb) {
                    Picker("", selection: $model.bodySize) {
                        ForEach(IconBodySize.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .labelsHidden()
                }

                FieldGroup(title: "Icons per run", symbol: "square.grid.2x2",
                           hint: model.variantCount > 1 ? "pick one afterwards" : nil) {
                    Picker("", selection: $model.variantCount) {
                        ForEach(1...Defaults.maxVariants, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                actionButtons
                statusBlock

                if !model.lastPrompt.isEmpty {
                    promptDisclosure
                }
            }
            .padding(20)
            .padding(.bottom, 24)
        }
        .background(.background.secondary)
        // Clicking the panel's empty space puts the palette grid away. Controls
        // sit above this, so they still get their own clicks.
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.showingPaletteLibrary = false }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.orange, .pink],
                                                    startPoint: .top, endPoint: .bottom))
                Text("IconForge")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 2)

            Text("Describe the app")
                .font(.title3.weight(.semibold))
            Text("IconForge writes the prompt, calls agy, and masks the result into a real macOS icon.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if model.phase.isBusy {
                Button(role: .cancel) {
                    model.cancel()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            } else if model.isEditPending {
                // Edit mode owns the primary button too. Leaving it as Generate
                // meant a click here quietly threw the icon away and drew a new
                // one, which is not what the dimmed fields were promising.
                Button {
                    model.refine()
                } label: {
                    Label("Edit icon", systemImage: "wand.and.rays")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canRefine)
                .keyboardShortcut(.return, modifiers: .command)
            } else {
                Button {
                    model.generate()
                } label: {
                    Label("Generate icon", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canGenerate)
                .keyboardShortcut(.return, modifiers: .command)
            }

            HStack(spacing: 10) {
                Button {
                    model.regenerate()
                } label: {
                    Label("Reroll", systemImage: "dice")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!model.canGenerate || model.artifacts == nil)

                Button {
                    model.exportSet()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .disabled(model.artifacts == nil)
            }

            HStack(spacing: 10) {
                Button {
                    model.revealInFinder()
                } label: {
                    Label("Reveal", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    model.clear()
                } label: {
                    Label("Clear", systemImage: "eraser")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!model.canClear)
                .help("Empty the fields and the preview. Past runs stay in the gallery.")
            }
        }
    }

    @ViewBuilder
    private var statusBlock: some View {
        if let error = model.errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Label("Something went wrong", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if error.contains("agy path") {
                    Button("Open Settings") { showingSettings = true }
                        .buttonStyle(.link)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
        } else if model.phase.isBusy {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.phase.label).font(.callout.weight(.medium))
                    if !model.statusDetail.isEmpty {
                        Text(model.statusDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.35)))
        } else if !model.statusDetail.isEmpty {
            Label(model.statusDetail, systemImage: model.phase == .done ? "checkmark.circle.fill" : "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var promptDisclosure: some View {
        DisclosureGroup("Prompt sent to agy") {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    Text(model.lastPrompt)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 150)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.lastPrompt, forType: .string)
                } label: {
                    Label("Copy prompt", systemImage: "doc.on.doc")
                }
                .buttonStyle(.link)
            }
            .padding(.top, 6)
        }
        .font(.callout)
    }
}

/// Palette control: a swatch button that opens the library, with a plain text
/// field underneath for anyone who would rather describe the colours.
private struct PaletteField: View {
    @EnvironmentObject private var model: GeneratorModel

    private var selected: ColorPalette? { PaletteLibrary.matching(hint: model.palette) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                model.showingPaletteLibrary.toggle()
            } label: {
                HStack(spacing: 8) {
                    if let selected {
                        PaletteSwatch(palette: selected, height: 16)
                            .frame(width: 76)
                        Text(selected.displayName)
                            .lineLimit(1)
                    } else {
                        Image(systemName: "swatchpalette")
                            .foregroundStyle(.secondary)
                        Text("Browse palettes")
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            // Inline rather than a popover or a sheet: anchored inside this
            // scrolling inspector, a popover collapses to nothing and a sheet
            // drags the window off-screen on macOS 14.
            if model.showingPaletteLibrary {
                PaletteLibraryView(selected: selected) { choice in
                    model.palette = choice?.promptHint ?? ""
                    model.showingPaletteLibrary = false
                }
                .onExitCommand { model.showingPaletteLibrary = false }
            }

            // Always mounted. Showing it only for custom hints meant the field
            // was torn down the moment a palette was picked, and AppKit wrote
            // its stale empty value back through the binding on the way out.
            TextField("or describe it: deep indigo to violet", text: $model.palette)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

private struct PaletteLibraryView: View {
    let selected: ColorPalette?
    let choose: (ColorPalette?) -> Void

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Popular palettes")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Use none") { choose(nil) }
                    .buttonStyle(.link)
                    .font(.caption)
                    .disabled(selected == nil)
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(PaletteLibrary.trending) { palette in
                        PaletteTile(palette: palette,
                                    isSelected: palette == selected,
                                    choose: choose)
                    }
                }
                .padding(.bottom, 4)
            }
            .frame(height: 220)

            Text("The chosen colours go into the prompt as exact hex values.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .underPageBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

private struct PaletteTile: View {
    let palette: ColorPalette
    let isSelected: Bool
    let choose: (ColorPalette?) -> Void

    private var tooltip: String {
        palette.displayName + "  " + palette.hexes.map { "#\($0)" }.joined(separator: "  ")
    }

    var body: some View {
        Button {
            choose(palette)
        } label: {
            PaletteSwatch(palette: palette, height: 26, cornerRadius: 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2.5 : 0)
                )
                // The label is clipped to the pill, which leaves the button
                // with no hit region of its own.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}

private struct FieldGroup<Content: View>: View {
    let title: String
    let symbol: String
    var hint: String? = nil
    /// Off means this input has no effect on what the button will do, so it is
    /// dimmed and unclickable rather than silently ignored.
    var enabled: Bool = true
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.callout.weight(.medium))
                if let hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            content
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

// MARK: - Preview pane

private struct PreviewPane: View {
    @EnvironmentObject private var model: GeneratorModel

    var body: some View {
        VStack(spacing: 0) {
            // Scrolls, so a short window shortens the preview instead of
            // pushing the gallery off the bottom edge.
            ScrollView {
                VStack(spacing: 26) {
                    HStack(spacing: 26) {
                        PreviewCard(isLight: true)
                        PreviewCard(isLight: false)
                    }
                    smallSizes

                    if model.variants.count > 1 {
                        VariantPicker()
                    }

                    if let artifacts = model.artifacts {
                        VStack(spacing: 12) {
                            FileChips(artifacts: artifacts)

                            Button {
                                model.copyInstallPrompt()
                            } label: {
                                Label("Copy as agent prompt", systemImage: "doc.on.clipboard")
                            }
                            .controlSize(.small)
                            .help("Copies an instruction telling a coding agent to install this icon on the app you're working on")

                            RefineBar()
                        }
                    }
                }
                .padding(30)
                .frame(maxWidth: .infinity)
            }
            .background(
                LinearGradient(colors: [Color(nsColor: .windowBackgroundColor),
                                        Color(nsColor: .underPageBackgroundColor)],
                               startPoint: .top, endPoint: .bottom)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { model.showingPaletteLibrary = false }

            Divider()
            HistoryStrip()
        }
    }

    private var smallSizes: some View {
        HStack(spacing: 18) {
            ForEach([32, 16], id: \.self) { size in
                VStack(spacing: 6) {
                    IconThumb(image: model.previewImage,
                              side: CGFloat(size),
                              roundsAtDisplayTime: model.bodySize == .fullBleed)
                        .frame(width: CGFloat(size), height: CGFloat(size))
                    Text("\(size)pt")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 52, alignment: .bottom)
            }
            Text("small sizes should still read at a glance")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct PreviewCard: View {
    @EnvironmentObject private var model: GeneratorModel
    let isLight: Bool

    private var backdrop: LinearGradient {
        isLight
            ? LinearGradient(colors: [Color(white: 0.98), Color(white: 0.88)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(white: 0.20), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(backdrop)
                IconThumb(image: model.previewImage,
                          side: 224,
                          placeholderTint: isLight ? .black.opacity(0.22) : .white.opacity(0.30),
                          roundsAtDisplayTime: model.bodySize == .fullBleed)
                    .frame(width: 224, height: 224)
                    .opacity(model.phase.isBusy ? 0.35 : 1)
                    .overlay {
                        if model.phase.isBusy {
                            ProgressView().controlSize(.large)
                        }
                    }
            }
            .frame(width: 268, height: 268)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))

            Text(isLight ? "Light desktop" : "Dark desktop")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Renders the finished icon, or a placeholder in the same squircle shape.
private struct IconThumb: View {
    let image: NSImage?
    let side: CGFloat
    /// Placeholder ink. The preview cards set their own, since the app's dark
    /// appearance would otherwise draw a pale outline onto the light card.
    var placeholderTint: Color = Color(nsColor: .tertiaryLabelColor)
    /// Full bleed artwork is a plain square on purpose, because macOS rounds it
    /// at display time. Showing the file as-is would preview something nobody
    /// ever sees, so the preview stands in for the system mask.
    var roundsAtDisplayTime: Bool = false

    var body: some View {
        if let image {
            let art = Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)

            if roundsAtDisplayTime {
                art
                    .clipShape(Squircle())
                    .shadow(color: .black.opacity(0.28),
                            radius: side * 0.045,
                            y: side * 0.022)
                    .padding(side * 0.08)
            } else {
                art
            }
        } else {
            Squircle()
                .stroke(placeholderTint,
                        style: StrokeStyle(lineWidth: max(1, side / 110), dash: [side / 22, side / 30]))
                .padding(side * 0.1)
                .overlay {
                    if side > 80 {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: side * 0.18))
                            .foregroundStyle(placeholderTint.opacity(0.75))
                    }
                }
        }
    }
}

/// Sends the current icon back to the model with a change request. Typing here
/// dims the inputs an edit keeps as they are, so it is obvious this refines the
/// icon on screen rather than drawing a new one.
private struct RefineBar: View {
    @EnvironmentObject private var model: GeneratorModel

    var body: some View {
        HStack(spacing: 8) {
            // Holds edit mode on with an empty bar, for changing the look
            // through the pickers alone.
            Button {
                model.editModeOn.toggle()
            } label: {
                Image(systemName: model.editModeOn ? "wand.and.rays.inverse" : "wand.and.rays")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(model.editModeOn ? .accentColor : nil)
            .help(model.editModeOn
                  ? "Edit mode is on: the pickers change this icon instead of the next one"
                  : "Turn on edit mode to restyle this icon without typing")

            TextField(model.editModeOn ? "optional: also say what to change"
                                       : "change something: \"make the bird bigger\"",
                      text: $model.refineRequest)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .frame(maxWidth: 340)
                .onSubmit { model.refine() }

            Button("Edit icon") { model.refine() }
                .disabled(!model.canRefine)
                .help("Redraws this icon with your change, keeping the original alongside it")
        }
        .padding(.top, 4)
    }
}

/// The batch from the last press of Generate. Clicking one promotes it to the
/// main preview and to every action that follows.
private struct VariantPicker: View {
    @EnvironmentObject private var model: GeneratorModel

    var body: some View {
        VStack(spacing: 6) {
            Text("Pick one")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach(model.variants) { variant in
                    VariantTile(variant: variant,
                                isSelected: variant.id == model.selectedVariantID) {
                        model.select(variant)
                    }
                }
            }
        }
    }
}

private struct VariantTile: View {
    @EnvironmentObject private var model: GeneratorModel
    let variant: IconVariant
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 5) {
                IconThumb(image: variant.image,
                          side: 64,
                          roundsAtDisplayTime: model.bodySize == .fullBleed)
                    .frame(width: 64, height: 64)
                Text(variant.subject)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 92)
            }
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: isSelected ? 1.5 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(variant.subject)
    }
}

private struct FileChips: View {
    let artifacts: IconPipeline.Artifacts
    /// Which chip was copied last, so its button can show a tick for a moment.
    @State private var copied: String?

    private var files: [(String, String, URL)] {
        [("AppIcon.icns", "app.badge", artifacts.icns),
         ("icon_1024.png", "photo", artifacts.maskedPNG),
         ("AppIcon.iconset", "square.grid.3x3", artifacts.iconsetDir),
         ("AppIcon.ico", "square.on.square", artifacts.ico)]
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(files, id: \.0) { name, symbol, url in
                HStack(spacing: 2) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label(name, systemImage: symbol)
                            .font(.caption)
                    }
                    .help("Show \(name) in Finder")

                    Button {
                        copy(url, name: name)
                    } label: {
                        Image(systemName: copied == name ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                    }
                    .help("Copy the full path to \(name)")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func copy(_ url: URL, name: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
        copied = name
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if copied == name { copied = nil }
        }
    }
}

// MARK: - History

private struct HistoryStrip: View {
    @EnvironmentObject private var model: GeneratorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Previous rolls", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.reloadHistory()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Rescan the output folder")
            }

            if model.history.isEmpty {
                Text("Nothing generated yet. Finished icons show up here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(height: 62, alignment: .leading)
            } else {
                // Lazy, and only as many as the user has scrolled to: a folder
                // with hundreds of runs would otherwise decode hundreds of PNGs
                // before the window could draw.
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(model.history.prefix(model.historyWindow)) { entry in
                            HistoryTile(entry: entry)
                        }

                        if model.historyWindow < model.history.count {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 48, height: 48)
                                .onAppear { model.growHistoryWindow() }
                        }
                    }
                    .padding(.bottom, 6)
                }
                .frame(height: 92)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}

/// Decoded gallery thumbnails, kept between scrolls so a tile that comes back
/// into view doesn't re-read its PNG.
@MainActor
final class ThumbnailCache: ObservableObject {
    static let shared = ThumbnailCache()
    private var images: [String: NSImage] = [:]

    func image(for url: URL) -> NSImage? { images[url.path] }

    /// Decodes off the main thread at tile size, never at 1024.
    func load(_ url: URL) async -> NSImage? {
        if let cached = images[url.path] { return cached }
        let decoded = await Task.detached(priority: .utility) {
            IconPipeline.thumbnail(at: url, maxPixel: 128)
                .map { NSImage(cgImage: $0, size: NSSize(width: 48, height: 48)) }
        }.value
        if let decoded { images[url.path] = decoded }
        return decoded
    }
}

private struct HistoryTile: View {
    @EnvironmentObject private var model: GeneratorModel
    let entry: HistoryEntry
    @State private var thumbnail: NSImage?

    var body: some View {
        Button {
            model.restore(entry)
        } label: {
            VStack(spacing: 4) {
                if let image = thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 48, height: 48)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.35))
                        .frame(width: 48, height: 48)
                }
                Text(entry.title)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: 72)
            }
        }
        .buttonStyle(.plain)
        .task { thumbnail = await ThumbnailCache.shared.load(entry.iconURL) }
        .help("\(entry.title) — \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([entry.folder])
            }
        }
    }
}

// MARK: - Settings

private struct SettingsSheet: View {
    @EnvironmentObject private var model: GeneratorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings").font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Output folder").font(.callout.weight(.medium))
                HStack {
                    TextField("", text: $model.outputDirectoryPath)
                        .textFieldStyle(.roundedBorder)
                        .truncationMode(.head)
                    Button("Choose…") { model.chooseOutputDirectory() }
                }
                Text("Each run gets its own subfolder, so nothing overwrites anything.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Model").font(.callout.weight(.medium))
                HStack {
                    Picker("", selection: $model.model) {
                        ForEach(model.modelChoices, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()

                    if model.isLoadingModels {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Refresh") { model.loadModels() }
                    }
                }
                if let listError = model.modelListError {
                    Text(listError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                } else {
                    Text("Read from `agy models` when the app starts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("agy path").font(.callout.weight(.medium))
                TextField("found automatically", text: $model.agyPath)
                    .textFieldStyle(.roundedBorder)
                Text("Only needed if agy lives somewhere unusual. Run `which agy` to find it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Reset to defaults") {
                    model.outputDirectoryPath = Defaults.outputDirectory.path
                    model.model = Defaults.model
                    model.agyPath = ""
                }
                Spacer()
                Button("Done") {
                    model.reloadHistory()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
