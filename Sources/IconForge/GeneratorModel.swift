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
    /// Most icons one press of Generate can produce.
    static let maxVariants = 4
    /// Tries per icon before giving up on it.
    static let attemptsPerIcon = 2
    /// How many past subjects to steer away from on the next roll.
    static let rememberedSubjects = 12

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

/// One finished icon from the current batch.
struct IconVariant: Identifiable {
    let id = UUID()
    let subject: String
    var artifacts: IconPipeline.Artifacts
    var image: NSImage?
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
    @AppStorage("variantCount") var variantCount = 1

    /// The subject IconForge derived last time. If the field still holds this,
    /// it is ours to replace on the next roll; if it differs, the user typed
    /// something and we leave it alone.
    @Published private(set) var derivedSubject = ""
    /// Recently used subjects, so consecutive rolls stop landing on the same
    /// object. This is the main reason a reroll used to look like the last one.
    @Published private(set) var recentSubjects: [String] = []

    // State
    @Published private(set) var phase: GenerationPhase = .idle
    @Published private(set) var statusDetail = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var artifacts: IconPipeline.Artifacts?
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var lastPrompt = ""
    @Published private(set) var variants: [IconVariant] = []
    @Published private(set) var selectedVariantID: UUID?
    /// Whether the palette grid is open. It lives here so a click anywhere
    /// else in the window can put it away.
    @Published var showingPaletteLibrary = false
    @Published var refineRequest = ""

    /// Local polish pass. Changing it re-renders the current icon from the raw
    /// artwork, which takes milliseconds and never calls agy.
    @Published var finish: IconFinish = IconFinish(rawValue: UserDefaults.standard.string(forKey: "finish") ?? "") ?? .appleEdge {
        didSet {
            guard finish != oldValue else { return }
            UserDefaults.standard.set(finish.rawValue, forKey: "finish")
            reapplyFinish()
        }
    }

    // Model discovery
    @Published private(set) var availableModels: [String] = []
    @Published private(set) var isLoadingModels = false
    @Published private(set) var modelListError: String?

    private var handles: [AgyProcessHandle] = []

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
        let typedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let styleVariant = style
        let modelName = model
        let baseDir = outputDirectory
        let agyOverride = agyPath
        let count = max(1, min(Defaults.maxVariants, variantCount))

        // Only a subject the user actually typed survives a reroll. One we
        // derived is thrown away, so the next roll picks a different object.
        let keepSubject = !typedSubject.isEmpty && typedSubject != derivedSubject
        let avoid = recentSubjects

        let runHandles = (0..<count).map { _ in AgyProcessHandle() }
        handles = runHandles

        errorMessage = nil
        artifacts = nil
        variants = []
        selectedVariantID = nil
        showingPaletteLibrary = false
        phase = .derivingSubject
        statusDetail = "Checking that agy is reachable…"

        Task {
            do {
                let binary = try AgyRunner.resolveBinary(customPath: agyOverride)
                let stamp = Self.timestamp()

                // 1. Subjects: the typed one for every variant, or a fresh set.
                var subjects: [String]
                if keepSubject {
                    subjects = Array(repeating: typedSubject, count: count)
                } else {
                    statusDetail = count == 1
                        ? "Asking \(modelName) what to draw…"
                        : "Asking \(modelName) for \(count) ideas…"
                    subjects = await Self.deriveSubjects(binary: binary,
                                                         model: modelName,
                                                         appName: name,
                                                         description: description,
                                                         count: count,
                                                         avoiding: avoid,
                                                         workingDirectory: baseDir,
                                                         handle: runHandles[0])
                    derivedSubject = subjects[0]
                    subject = subjects[0]
                }
                if runHandles.contains(where: { $0.isCancelled }) { throw CancellationError() }

                // 2. One art-direction recipe per variant, so a batch doesn't
                // come back as four takes on the same picture.
                let recipes = VariationRecipe.distinct(count: count)

                phase = .generatingArtwork
                statusDetail = count == 1
                    ? "\(modelName) is drawing. This usually takes under a minute."
                    : "\(modelName) is drawing \(count) icons…"

                let request = BatchRequest(binary: binary,
                                           model: modelName,
                                           appName: name,
                                           description: description,
                                           palette: paletteHint,
                                           style: styleVariant,
                                           baseDir: baseDir,
                                           stamp: stamp,
                                           isBatch: count > 1,
                                           finish: finish)

                var built: [(Int, IconVariant, String)] = []
                try await withThrowingTaskGroup(of: (Int, IconVariant, String)?.self) { group in
                    for index in 0..<count {
                        group.addTask { [request] in
                            try await Self.buildOne(index: index,
                                                    subject: subjects[index],
                                                    recipe: recipes[index],
                                                    request: request,
                                                    handle: runHandles[index])
                        }
                    }
                    for try await result in group {
                        guard let result else { continue }
                        built.append(result)
                        let done = built.count
                        if count > 1 {
                            statusDetail = "\(done) of \(count) done…"
                        }
                    }
                }

                guard !built.isEmpty else { throw AgyError.noImageProduced(output: "") }
                built.sort { $0.0 < $1.0 }

                let finished = built.map(\.1)
                variants = finished
                selectedVariantID = finished.first?.id
                artifacts = finished.first?.artifacts
                previewImage = finished.first?.image
                lastPrompt = built.first?.2 ?? ""
                if !keepSubject, let first = finished.first {
                    derivedSubject = first.subject
                    subject = first.subject
                }
                rememberSubjects(finished.map(\.subject))

                phase = .done
                if finished.count == 1 && count == 1 {
                    statusDetail = "Saved to \(finished[0].artifacts.sessionDir.lastPathComponent)"
                } else if finished.count < count {
                    statusDetail = "\(finished.count) of \(count) came back — pick one"
                } else {
                    statusDetail = "\(finished.count) icons ready — pick one"
                }
                handles = []
                reloadHistory()
            } catch is CancellationError {
                phase = .idle
                statusDetail = "Cancelled"
                handles = []
            } catch {
                phase = .failed
                statusDetail = ""
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                handles = []
            }
        }
    }

    /// Same inputs, fresh roll. A derived subject is re-derived, so the reroll
    /// is a different idea rather than the same object drawn again.
    func regenerate() { generate() }

    /// Re-runs the local part of the pipeline with the current finish. The raw
    /// artwork is untouched, so this is reversible and free.
    func reapplyFinish() {
        guard let current = artifacts, !phase.isBusy else { return }
        let chosen = finish
        let raw = current.rawPNG
        let dir = current.sessionDir
        guard FileManager.default.fileExists(atPath: raw.path) else { return }

        Task {
            do {
                let rebuilt = try await Task.detached(priority: .userInitiated) {
                    try IconPipeline.process(rawImage: raw, into: dir, finish: chosen)
                }.value
                let image = NSImage(contentsOf: rebuilt.maskedPNG)
                artifacts = rebuilt
                previewImage = image
                if let index = variants.firstIndex(where: { $0.artifacts.sessionDir == dir }) {
                    variants[index].artifacts = rebuilt
                    variants[index].image = image
                }
                statusDetail = "\(chosen.rawValue) finish applied"
                reloadHistory()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: - Refining

    var canRefine: Bool {
        artifacts != nil && !phase.isBusy && !refineRequest.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Sends the icon back to the model with a change request, keeping the
    /// original untouched and adding the result alongside it.
    func refine() {
        guard canRefine, let current = artifacts else { return }

        let request = refineRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = current.rawPNG
        let name = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelName = model
        let baseDir = outputDirectory
        let agyOverride = agyPath
        let chosenFinish = finish
        let styleVariant = style
        let paletteHint = palette.trimmingCharacters(in: .whitespacesAndNewlines)
        let runHandle = AgyProcessHandle()
        handles = [runHandle]

        errorMessage = nil
        phase = .generatingArtwork
        statusDetail = "Applying your edit…"

        Task {
            do {
                let binary = try AgyRunner.resolveBinary(customPath: agyOverride)
                let sessionDir = try Self.makeSessionDirectory(base: baseDir,
                                                               appName: name.isEmpty ? "icon" : name,
                                                               stamp: Self.timestamp(),
                                                               suffix: "-edit")

                let rawURL = sessionDir.appendingPathComponent("source_raw.png")
                let instruction = PromptBuilder.refineInstruction(sourcePath: source.path,
                                                                  outputPath: rawURL.path,
                                                                  request: request)
                try instruction.write(to: sessionDir.appendingPathComponent("prompt.txt"),
                                      atomically: true, encoding: .utf8)

                let started = Date()
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
                    try? FileManager.default.removeItem(at: sessionDir)
                    throw AgyError.noImageProduced(output: output)
                }
                if produced != rawURL {
                    try? FileManager.default.removeItem(at: rawURL)
                    try FileManager.default.copyItem(at: produced, to: rawURL)
                }

                phase = .masking
                let rebuilt = try await Task.detached(priority: .userInitiated) {
                    try IconPipeline.process(rawImage: rawURL, into: sessionDir, finish: chosenFinish)
                }.value

                let metadata = RunMetadata(appName: name,
                                           description: appDescription,
                                           subject: currentSubject.isEmpty ? request : currentSubject,
                                           palette: paletteHint,
                                           style: styleVariant,
                                           model: modelName,
                                           createdAt: Date())
                Self.writeMetadata(metadata, to: sessionDir)

                let image = NSImage(contentsOf: rebuilt.maskedPNG)
                let edited = IconVariant(subject: currentSubject.isEmpty ? "edited" : currentSubject,
                                         artifacts: rebuilt,
                                         image: image)
                variants.append(edited)
                selectedVariantID = edited.id
                artifacts = rebuilt
                previewImage = image
                refineRequest = ""
                phase = .done
                statusDetail = "Edit saved to \(rebuilt.sessionDir.lastPathComponent)"
                handles = []
                reloadHistory()
            } catch is CancellationError {
                phase = .done
                statusDetail = "Cancelled"
                handles = []
            } catch {
                phase = .failed
                statusDetail = ""
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                handles = []
            }
        }
    }

    /// Promote one of the batch to the main preview.
    func select(_ variant: IconVariant) {
        applyAfterEditing { [weak self] in
            guard let self else { return }
            self.selectedVariantID = variant.id
            self.artifacts = variant.artifacts
            self.previewImage = variant.image
            self.subject = variant.subject
            self.derivedSubject = variant.subject
            self.lastPrompt = (try? String(contentsOf: variant.artifacts.sessionDir.appendingPathComponent("prompt.txt"),
                                           encoding: .utf8)) ?? self.lastPrompt
            self.statusDetail = "Using \(variant.artifacts.sessionDir.lastPathComponent)"
        }
    }

    private func rememberSubjects(_ used: [String]) {
        for subject in used where !recentSubjects.contains(subject) {
            recentSubjects.insert(subject, at: 0)
        }
        if recentSubjects.count > Defaults.rememberedSubjects {
            recentSubjects = Array(recentSubjects.prefix(Defaults.rememberedSubjects))
        }
    }

    /// The parts of a run that every variant shares.
    private struct BatchRequest: Sendable {
        let binary: URL
        let model: String
        let appName: String
        let description: String
        let palette: String
        let style: StyleVariant
        let baseDir: URL
        let stamp: String
        let isBatch: Bool
        let finish: IconFinish
    }

    /// Generates and post-processes one icon. Returns its index, the finished
    /// variant, and the prompt that produced it.
    private static func buildOne(index: Int,
                                 subject: String,
                                 recipe: VariationRecipe,
                                 request: BatchRequest,
                                 handle: AgyProcessHandle) async throws -> (Int, IconVariant, String)? {
        let suffix = request.isBatch ? "-v\(index + 1)" : ""
        let sessionDir = try makeSessionDirectory(base: request.baseDir,
                                                  appName: request.appName,
                                                  stamp: request.stamp,
                                                  suffix: suffix)

        let imagePrompt = PromptBuilder.imagePrompt(appName: request.appName,
                                                    description: request.description,
                                                    subject: subject,
                                                    palette: request.palette,
                                                    style: request.style,
                                                    variation: recipe)
        try imagePrompt.write(to: sessionDir.appendingPathComponent("prompt.txt"),
                              atomically: true, encoding: .utf8)

        let rawURL = sessionDir.appendingPathComponent("source_raw.png")
        let instruction = PromptBuilder.agyInstruction(imagePrompt: imagePrompt, outputPath: rawURL.path)

        // agy comes back empty-handed often enough that one retry is worth it,
        // especially in a batch where a dud costs the user a whole slot.
        var lastOutput = ""
        var locatedImage: URL?
        for attempt in 0..<Defaults.attemptsPerIcon {
            if handle.isCancelled { throw CancellationError() }
            let started = Date()
            lastOutput = try await Task.detached(priority: .userInitiated) {
                try AgyRunner.run(binary: request.binary,
                                  model: request.model,
                                  prompt: instruction,
                                  workingDirectory: sessionDir,
                                  timeout: Defaults.timeoutSeconds,
                                  handle: handle)
            }.value

            if let produced = AgyRunner.locateImage(expected: rawURL,
                                                    output: lastOutput,
                                                    sessionDir: sessionDir,
                                                    after: started) {
                locatedImage = produced
                break
            }
            _ = attempt
        }

        guard let produced = locatedImage else {
            // A dud shouldn't sink the batch, and it shouldn't leave an empty
            // folder behind either.
            try? FileManager.default.removeItem(at: sessionDir)
            if request.isBatch { return nil }
            throw AgyError.noImageProduced(output: lastOutput)
        }
        if produced != rawURL {
            try? FileManager.default.removeItem(at: rawURL)
            try FileManager.default.copyItem(at: produced, to: rawURL)
        }

        let artifacts = try await Task.detached(priority: .userInitiated) {
            try IconPipeline.process(rawImage: rawURL, into: sessionDir, finish: request.finish)
        }.value

        let metadata = RunMetadata(appName: request.appName,
                                   description: request.description,
                                   subject: subject,
                                   palette: request.palette,
                                   style: request.style,
                                   model: request.model,
                                   createdAt: Date())
        writeMetadata(metadata, to: sessionDir)

        let image = NSImage(contentsOf: artifacts.maskedPNG)
        return (index, IconVariant(subject: subject, artifacts: artifacts, image: image), imagePrompt)
    }

    var canClear: Bool {
        guard !phase.isBusy else { return false }
        return artifacts != nil
            || errorMessage != nil
            || !appName.isEmpty
            || !appDescription.isEmpty
            || !palette.isEmpty
            || !subject.isEmpty
            || style != .standard
    }

    /// Hands first responder back to the window before the text-bound fields
    /// are rewritten. Without this the open field editor commits whatever it
    /// was holding on top of the new value, which shows up as stray characters
    /// glued to the end of a restored app name.
    private func endTextEditing() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    /// Resigns first responder, then rewrites the text-bound fields on the next
    /// runloop turn. Doing both in the same turn still let the field editor
    /// commit over the top of the new values.
    private func applyAfterEditing(_ work: @escaping @MainActor () -> Void) {
        endTextEditing()
        Task { @MainActor in work() }
    }

    /// Empties the window: inputs, preview, and the last run's status. Files
    /// already on disk stay where they are, and so does the gallery.
    func clear() {
        guard !phase.isBusy else { return }
        endTextEditing()

        appName = ""
        appDescription = ""
        palette = ""
        subject = ""
        style = .standard

        artifacts = nil
        previewImage = nil
        variants = []
        selectedVariantID = nil
        derivedSubject = ""
        recentSubjects = []
        refineRequest = ""
        showingPaletteLibrary = false
        lastPrompt = ""
        errorMessage = nil
        statusDetail = ""
        phase = .idle
    }

    func cancel() {
        handles.forEach { $0.cancel() }
        statusDetail = "Stopping…"
    }

    // MARK: - Subject derivation

    /// Asks for `count` icon-friendly subjects in one call, steering away from
    /// anything recent. Short of a full set, the list is padded so every
    /// variant still has something to draw.
    private static func deriveSubjects(binary: URL,
                                       model: String,
                                       appName: String,
                                       description: String,
                                       count: Int,
                                       avoiding used: [String],
                                       workingDirectory: URL,
                                       handle: AgyProcessHandle) async -> [String] {
        try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        let prompt = PromptBuilder.subjectsPrompt(appName: appName,
                                                  description: description,
                                                  count: count,
                                                  avoiding: used)
        let raw = try? await Task.detached(priority: .userInitiated) {
            try AgyRunner.run(binary: binary,
                              model: model,
                              prompt: prompt,
                              workingDirectory: workingDirectory,
                              timeout: 150,
                              handle: handle)
        }.value

        var subjects = raw.map { PromptBuilder.cleanSubjects($0, count: count) } ?? []
        let fallback = PromptBuilder.fallbackSubject(description: description)
        while subjects.count < count {
            subjects.append(subjects.first ?? fallback)
        }
        return subjects
    }

    // MARK: - Files

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    /// One folder per icon. A batch shares a timestamp and separates on the
    /// `-v1`, `-v2` suffix, so the variants of one press sort together.
    private static func makeSessionDirectory(base: URL,
                                             appName: String,
                                             stamp: String,
                                             suffix: String) throws -> URL {
        let slug = slugify(appName) + suffix

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
        applyAfterEditing { [weak self] in
            self?.applyRestore(entry)
        }
    }

    private func applyRestore(_ entry: HistoryEntry) {
        previewImage = NSImage(contentsOf: entry.iconURL)
        artifacts = IconPipeline.Artifacts(sessionDir: entry.folder,
                                           rawPNG: entry.folder.appendingPathComponent("source_raw.png"),
                                           maskedPNG: entry.iconURL,
                                           iconsetDir: entry.folder.appendingPathComponent("AppIcon.iconset"),
                                           icns: entry.folder.appendingPathComponent("AppIcon.icns"),
                                           ico: entry.folder.appendingPathComponent("AppIcon.ico"))
        variants = []
        selectedVariantID = nil
        phase = .done
        errorMessage = nil
        statusDetail = "Loaded \(entry.folder.lastPathComponent)"
        lastPrompt = (try? String(contentsOf: entry.folder.appendingPathComponent("prompt.txt"), encoding: .utf8)) ?? ""

        if let metadata = entry.metadata {
            appName = metadata.appName
            appDescription = metadata.description
            palette = metadata.palette
            subject = metadata.subject
            derivedSubject = metadata.subject
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

    /// Copies a ready-to-paste instruction for a coding agent: which files to
    /// use, where they are, and what to do with them.
    func copyInstallPrompt() {
        guard let artifacts else { return }

        let name = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let appLabel = name.isEmpty ? "the app" : name

        let prompt = """
        Set the icon below as the app icon for the macOS app we are working on in this session (\(appLabel)), then rebuild and reinstall it so the new icon shows up.

        The icon is already generated. Use these files as they are, do not generate or redraw anything:

          .icns (use this one):  \(artifacts.icns.path)
          .iconset folder:       \(artifacts.iconsetDir.path)
          1024 PNG (masked):     \(artifacts.maskedPNG.path)
          raw 1024 PNG:          \(artifacts.rawPNG.path)
          everything:            \(artifacts.sessionDir.path)

        What to do:
        1. Copy the .icns into the project where its icon lives. For a hand-built Swift Package app that is usually Resources/AppIcon.icns; for an Xcode project, import the .iconset contents into the AppIcon asset instead.
        2. Make sure the bundle's Info.plist has CFBundleIconFile set to the icon's base name (AppIcon) and that the build step copies the .icns into Contents/Resources.
        3. Rebuild the .app, re-sign it (codesign --force --sign - path/to/App.app), and reinstall it, replacing any copy already in /Applications.
        4. If the Dock or Finder still shows the old icon, touch the bundle and restart the Dock to drop the cached version.

        Tell me which files you changed and confirm the installed app is using the new icon.
        """

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        statusDetail = "Agent prompt copied to the clipboard"
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
