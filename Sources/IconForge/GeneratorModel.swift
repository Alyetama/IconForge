import AppKit
import Foundation
import SwiftUI

/// Where output lands by default, and the model IconForge asks for.
enum Defaults {
    static let outputFolderName = "IconForge"
    static let model = "gemini-3.6-flash-low"
    static let timeoutSeconds = 420
    /// Newest N runs shown in the gallery strip.
    static let historyLimit = 60

    static var outputDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(outputFolderName, isDirectory: true)
    }
}

/// Sidecar written next to each icon so the gallery can describe past rolls.
struct RunMetadata: Codable {
    var appName: String
    var description: String
    var subject: String
    var palette: String
    var style: StyleVariant
    var model: String
    var createdAt: Date
}

/// One past generation, as read back off disk.
struct HistoryEntry: Identifiable, Hashable {
    let id: String
    let folder: URL
    let iconURL: URL
    let title: String
    let createdAt: Date
    let metadata: RunMetadata?
    /// Decoded once at scan time so the gallery doesn't re-read 1024px PNGs on
    /// every SwiftUI render pass.
    let thumbnail: NSImage?

    static func == (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum GenerationPhase: Equatable {
    case idle
    case derivingSubject
    case generatingArtwork
    case masking
    case buildingIconset
    case done
    case failed

    var isBusy: Bool {
        switch self {
        case .derivingSubject, .generatingArtwork, .masking, .buildingIconset: return true
        default: return false
        }
    }

    var label: String {
        switch self {
        case .idle: return "Ready"
        case .derivingSubject: return "Working out the subject…"
        case .generatingArtwork: return "Generating artwork with agy…"
        case .masking: return "Applying the squircle mask…"
        case .buildingIconset: return "Building .iconset, .icns and .ico…"
        case .done: return "Done"
        case .failed: return "Failed"
        }
    }
}

@MainActor
final class GeneratorModel: ObservableObject {

    // Inputs
    @Published var appName = ""
    @Published var appDescription = ""
    @Published var palette = ""
    @Published var subject = ""
    @Published var style: StyleVariant = .standard

    // Settings
    @AppStorage("outputDirectory") var outputDirectoryPath = Defaults.outputDirectory.path
    @AppStorage("model") var model = Defaults.model
    @AppStorage("agyPath") var agyPath = ""

    // State
    @Published private(set) var phase: GenerationPhase = .idle
    @Published private(set) var statusDetail = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var artifacts: IconPipeline.Artifacts?
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var lastPrompt = ""

    // Model discovery
    @Published private(set) var availableModels: [String] = []
    @Published private(set) var isLoadingModels = false
    @Published private(set) var modelListError: String?

    private var handle: AgyProcessHandle?

    var canGenerate: Bool {
        !appName.trimmingCharacters(in: .whitespaces).isEmpty
            && !appDescription.trimmingCharacters(in: .whitespaces).isEmpty
            && !phase.isBusy
    }

    var outputDirectory: URL {
        URL(fileURLWithPath: (outputDirectoryPath as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// The picker's contents: whatever agy reported, plus the current choice if
    /// it isn't in that list (a hand-typed or since-removed model).
    var modelChoices: [String] {
        var choices = availableModels
        let excluded = AgyRunner.excludedModelPrefixes.contains { model.lowercased().hasPrefix($0) }
        if !model.isEmpty && !excluded && !choices.contains(model) { choices.insert(model, at: 0) }
        if choices.isEmpty { choices = [Defaults.model] }
        return choices
    }

    // MARK: - Model discovery

    func loadModels() {
        guard !isLoadingModels else { return }

        // A model saved before it was excluded would leave the picker with a
        // selection it can't show, so drop it back to the default first.
        if AgyRunner.excludedModelPrefixes.contains(where: { model.lowercased().hasPrefix($0) }) {
            model = Defaults.model
        }

        isLoadingModels = true
        modelListError = nil
        let agyOverride = agyPath

        Task {
            do {
                let binary = try AgyRunner.resolveBinary(customPath: agyOverride)
                let models = try await Task.detached(priority: .utility) {
                    try AgyRunner.listModels(binary: binary)
                }.value

                availableModels = models
                if !models.isEmpty && !models.contains(model) {
                    // The saved model is gone; fall back to something real.
                    model = models.contains(Defaults.model) ? Defaults.model : models[0]
                }
            } catch {
                modelListError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isLoadingModels = false
        }
    }

    // MARK: - Generation

    func generate() {
        guard canGenerate else { return }

        let name = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = appDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let paletteHint = palette.trimmingCharacters(in: .whitespacesAndNewlines)
        let manualSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let variant = style
        let modelName = model
        let baseDir = outputDirectory
        let agyOverride = agyPath
        let runHandle = AgyProcessHandle()
        handle = runHandle

        errorMessage = nil
        artifacts = nil
        phase = .derivingSubject
        statusDetail = "Checking that agy is reachable…"

        Task {
            do {
                let binary = try AgyRunner.resolveBinary(customPath: agyOverride)
                let sessionDir = try Self.makeSessionDirectory(base: baseDir, appName: name)

                // 1. Subject — either typed in, or asked of the model.
                var resolvedSubject = manualSubject
                if resolvedSubject.isEmpty {
                    setPhase(.derivingSubject, detail: "Asking \(modelName) what to draw…")
                    resolvedSubject = await Self.deriveSubject(binary: binary,
                                                              model: modelName,
                                                              appName: name,
                                                              description: description,
                                                              sessionDir: sessionDir,
                                                              handle: runHandle)
                    subject = resolvedSubject
                }
                if runHandle.isCancelled { throw CancellationError() }

                // 2. Artwork.
                let imagePrompt = PromptBuilder.imagePrompt(appName: name,
                                                            description: description,
                                                            subject: resolvedSubject,
                                                            palette: paletteHint,
                                                            style: variant)
                try imagePrompt.write(to: sessionDir.appendingPathComponent("prompt.txt"),
                                      atomically: true, encoding: .utf8)
                lastPrompt = imagePrompt

                phase = .generatingArtwork
                statusDetail = "\(modelName) is drawing. This usually takes under a minute."

                let rawURL = sessionDir.appendingPathComponent("source_raw.png")
                let started = Date()
                let instruction = PromptBuilder.agyInstruction(imagePrompt: imagePrompt, outputPath: rawURL.path)

                let output = try await Task.detached(priority: .userInitiated) {
                    try AgyRunner.run(binary: binary,
                                      model: modelName,
                                      prompt: instruction,
                                      workingDirectory: sessionDir,
                                      timeout: Defaults.timeoutSeconds,
                                      handle: runHandle)
                }.value

                guard let produced = AgyRunner.locateImage(expected: rawURL,
                                                           output: output,
                                                           sessionDir: sessionDir,
                                                           after: started) else {
                    throw AgyError.noImageProduced(output: output)
                }
                if produced != rawURL {
                    try? FileManager.default.removeItem(at: rawURL)
                    try FileManager.default.copyItem(at: produced, to: rawURL)
                }

                // 3. Post-process.
                phase = .masking
                statusDetail = "Cropping to 1024, masking, adding the shadow…"

                let built = try await Task.detached(priority: .userInitiated) {
                    try IconPipeline.process(rawImage: rawURL, into: sessionDir)
                }.value

                phase = .buildingIconset
                statusDetail = "Writing every size…"

                let metadata = RunMetadata(appName: name,
                                           description: description,
                                           subject: resolvedSubject,
                                           palette: paletteHint,
                                           style: variant,
                                           model: modelName,
                                           createdAt: Date())
                Self.writeMetadata(metadata, to: sessionDir)

                artifacts = built
                previewImage = NSImage(contentsOf: built.maskedPNG)
                phase = .done
                statusDetail = "Saved to \(built.sessionDir.lastPathComponent)"
                handle = nil
                reloadHistory()
            } catch is CancellationError {
                phase = .idle
                statusDetail = "Cancelled"
                handle = nil
            } catch {
                phase = .failed
                statusDetail = ""
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                handle = nil
            }
        }
    }

    /// Same inputs, fresh roll. The subject field keeps whatever is in it, so a
    /// regenerate re-rolls the artwork rather than the concept.
    func regenerate() { generate() }

    func cancel() {
        handle?.cancel()
        statusDetail = "Stopping…"
    }

    private func setPhase(_ newPhase: GenerationPhase, detail: String) {
        phase = newPhase
        statusDetail = detail
    }

    // MARK: - Subject derivation

    private static func deriveSubject(binary: URL,
                                      model: String,
                                      appName: String,
                                      description: String,
                                      sessionDir: URL,
                                      handle: AgyProcessHandle) async -> String {
        let prompt = PromptBuilder.subjectPrompt(appName: appName, description: description)
        let raw = try? await Task.detached(priority: .userInitiated) {
            try AgyRunner.run(binary: binary,
                              model: model,
                              prompt: prompt,
                              workingDirectory: sessionDir,
                              timeout: 120,
                              handle: handle)
        }.value

        if let raw, let cleaned = PromptBuilder.cleanSubject(raw) { return cleaned }
        return PromptBuilder.fallbackSubject(description: description)
    }

    // MARK: - Files

    private static func makeSessionDirectory(base: URL, appName: String) throws -> URL {
        let slug = slugify(appName)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let stamp = formatter.string(from: Date())

        var dir = base.appendingPathComponent("\(slug)-\(stamp)", isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: dir.path) {
            dir = base.appendingPathComponent("\(slug)-\(stamp)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func slugify(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let mapped = text.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(mapped)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "icon" : String(collapsed.prefix(40))
    }

    private static func writeMetadata(_ metadata: RunMetadata, to dir: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(metadata) else { return }
        try? data.write(to: dir.appendingPathComponent("meta.json"))
    }

    // MARK: - History

    func reloadHistory() {
        let base = outputDirectory
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: base,
                                                        includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                                                        options: [.skipsHiddenFiles]) else {
            history = []
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        history = folders
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .compactMap { folder -> HistoryEntry? in
                let icon = folder.appendingPathComponent("icon_1024.png")
                guard fm.fileExists(atPath: icon.path) else { return nil }

                let metadata = (try? Data(contentsOf: folder.appendingPathComponent("meta.json")))
                    .flatMap { try? decoder.decode(RunMetadata.self, from: $0) }
                let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast

                let thumbnail = IconPipeline.thumbnail(at: icon, maxPixel: 128)
                    .map { NSImage(cgImage: $0, size: NSSize(width: 48, height: 48)) }

                return HistoryEntry(id: folder.path,
                                    folder: folder,
                                    iconURL: icon,
                                    title: metadata?.appName ?? folder.lastPathComponent,
                                    createdAt: metadata?.createdAt ?? modified,
                                    metadata: metadata,
                                    thumbnail: thumbnail)
            }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(Defaults.historyLimit)
            .map { $0 }
    }

    /// Load a past run back into the preview and the input fields.
    func restore(_ entry: HistoryEntry) {
        previewImage = NSImage(contentsOf: entry.iconURL)
        artifacts = IconPipeline.Artifacts(sessionDir: entry.folder,
                                           rawPNG: entry.folder.appendingPathComponent("source_raw.png"),
                                           maskedPNG: entry.iconURL,
                                           iconsetDir: entry.folder.appendingPathComponent("AppIcon.iconset"),
                                           icns: entry.folder.appendingPathComponent("AppIcon.icns"),
                                           ico: entry.folder.appendingPathComponent("AppIcon.ico"))
        phase = .done
        errorMessage = nil
        statusDetail = "Loaded \(entry.folder.lastPathComponent)"
        lastPrompt = (try? String(contentsOf: entry.folder.appendingPathComponent("prompt.txt"), encoding: .utf8)) ?? ""

        if let metadata = entry.metadata {
            appName = metadata.appName
            appDescription = metadata.description
            palette = metadata.palette
            subject = metadata.subject
            style = metadata.style
        }
    }

    // MARK: - Finder

    func revealInFinder() {
        if let session = artifacts?.sessionDir, FileManager.default.fileExists(atPath: session.path) {
            NSWorkspace.shared.activateFileViewerSelecting([session])
            return
        }
        let base = outputDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([base])
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = outputDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputDirectoryPath = url.path
        reloadHistory()
    }

    /// Copy the finished set somewhere the user picks.
    func exportSet() {
        guard let artifacts else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export here"
        panel.message = "Choose where to copy the .icns, .ico, .iconset and PNGs."
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let fm = FileManager.default
        let folderName = "\(GeneratorModel.slugify(appName.isEmpty ? "icon" : appName))-icons"
        var target = destination.appendingPathComponent(folderName, isDirectory: true)
        var suffix = 2
        while fm.fileExists(atPath: target.path) {
            target = destination.appendingPathComponent("\(folderName)-\(suffix)", isDirectory: true)
            suffix += 1
        }

        do {
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            for item in [artifacts.icns, artifacts.ico, artifacts.maskedPNG, artifacts.rawPNG, artifacts.iconsetDir] {
                guard fm.fileExists(atPath: item.path) else { continue }
                try fm.copyItem(at: item, to: target.appendingPathComponent(item.lastPathComponent))
            }
            NSWorkspace.shared.activateFileViewerSelecting([target])
        } catch {
            errorMessage = "Could not export: \(error.localizedDescription)"
            phase = .failed
        }
    }
}
