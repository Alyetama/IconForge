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
            ToolbarItem(placement: .principal) {
                // Fixed point sizes: the hammer glyph's bounding box is taller
                // than its optical size, and at .headline it clips against the
                // toolbar item's rounded background.
                HStack(spacing: 6) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: [.orange, .pink],
                                                        startPoint: .top, endPoint: .bottom))
                    Text("IconForge")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.vertical, 1)
            }
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

                FieldGroup(title: "App name", symbol: "textformat") {
                    TextField("Tidepool", text: $model.appName)
                        .textFieldStyle(.roundedBorder)
                }

                FieldGroup(title: "What it does", symbol: "text.alignleft") {
                    // A plain multiline TextField beats TextEditor here: it takes
                    // focus on the first click and carries its own placeholder.
                    TextField("tracks daily water intake",
                              text: $model.appDescription,
                              axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }

                FieldGroup(title: "Subject", symbol: "circle.hexagonpath",
                           hint: "optional — the model picks one") {
                    TextField("a water droplet", text: $model.subject)
                        .textFieldStyle(.roundedBorder)
                }

                FieldGroup(title: "Palette hint", symbol: "paintpalette", hint: "optional") {
                    TextField("deep indigo to violet", text: $model.palette)
                        .textFieldStyle(.roundedBorder)
                }

                FieldGroup(title: "Style", symbol: "wand.and.stars") {
                    Picker("", selection: $model.style) {
                        ForEach(StyleVariant.allCases) { variant in
                            Text(variant.rawValue).tag(variant)
                        }
                    }
                    .pickerStyle(.segmented)
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

                actionButtons
                statusBlock

                if !model.lastPrompt.isEmpty {
                    promptDisclosure
                }
            }
            .padding(20)
        }
        .background(.background.secondary)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
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

            Button {
                model.revealInFinder()
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
                    .frame(maxWidth: .infinity)
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

private struct FieldGroup<Content: View>: View {
    let title: String
    let symbol: String
    var hint: String? = nil
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
    }
}

// MARK: - Preview pane

private struct PreviewPane: View {
    @EnvironmentObject private var model: GeneratorModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: [Color(nsColor: .windowBackgroundColor),
                                        Color(nsColor: .underPageBackgroundColor)],
                               startPoint: .top, endPoint: .bottom)

                VStack(spacing: 26) {
                    HStack(spacing: 26) {
                        PreviewCard(isLight: true)
                        PreviewCard(isLight: false)
                    }
                    smallSizes
                    if let artifacts = model.artifacts {
                        FileChips(artifacts: artifacts)
                    }
                }
                .padding(30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HistoryStrip()
        }
    }

    private var smallSizes: some View {
        HStack(spacing: 18) {
            ForEach([32, 16], id: \.self) { size in
                VStack(spacing: 6) {
                    IconThumb(image: model.previewImage, side: CGFloat(size))
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
                IconThumb(image: model.previewImage, side: 224)
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

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Squircle()
                .stroke(Color(nsColor: .tertiaryLabelColor),
                        style: StrokeStyle(lineWidth: max(1, side / 110), dash: [side / 22, side / 30]))
                .padding(side * 0.1)
                .overlay {
                    if side > 80 {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: side * 0.18))
                            .foregroundStyle(.quaternary)
                    }
                }
        }
    }
}

private struct FileChips: View {
    let artifacts: IconPipeline.Artifacts

    private var files: [(String, String, URL)] {
        [("AppIcon.icns", "app.badge", artifacts.icns),
         ("icon_1024.png", "photo", artifacts.maskedPNG),
         ("AppIcon.iconset", "square.grid.3x3", artifacts.iconsetDir),
         ("AppIcon.ico", "square.on.square", artifacts.ico)]
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(files, id: \.0) { name, symbol, url in
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label(name, systemImage: symbol)
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(url.path)
            }
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(model.history) { entry in
                            HistoryTile(entry: entry)
                        }
                    }
                    .padding(.bottom, 4)
                }
                .frame(height: 78)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}

private struct HistoryTile: View {
    @EnvironmentObject private var model: GeneratorModel
    let entry: HistoryEntry

    var body: some View {
        Button {
            model.restore(entry)
        } label: {
            VStack(spacing: 4) {
                if let image = entry.thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 48, height: 48)
                }
                Text(entry.title)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: 72)
            }
        }
        .buttonStyle(.plain)
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
