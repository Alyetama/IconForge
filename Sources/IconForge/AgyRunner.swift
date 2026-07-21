import Foundation

/// Which command line agent draws the artwork. Both take a prompt and leave a
/// PNG where the prompt tells them to; only the flags differ.
enum GeneratorBackend: String, CaseIterable, Identifiable, Codable {
    case agy = "agy"
    case codex = "codex"

    var id: String { rawValue }
    var binaryName: String { rawValue }

    var defaultModel: String {
        switch self {
        case .agy: return "gemini-3.1-pro-high"
        case .codex: return "gpt-5.6-luna"
        }
    }

    /// Models this backend offers. agy returns nil because it lists its own.
    var models: [String]? {
        switch self {
        case .agy: return nil
        case .codex: return ["gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol"]
        }
    }

    /// agy encodes effort in the model id itself (…-low, …-high), so there is
    /// nothing separate to choose.
    var supportsEffort: Bool { self == .codex }

    static let effortLevels = ["low", "medium", "high", "max"]

    /// codex refuses to run outside a git repo without being told not to care,
    /// and takes its reasoning effort through a config override.
    func arguments(model: String, effort: String, prompt: String) -> [String] {
        switch self {
        case .agy:
            return ["--model", model, "-p", prompt]
        case .codex:
            return ["exec", prompt,
                    "--model", model,
                    "-c", "model_reasoning_effort=\"\(effort)\"",
                    "--skip-git-repo-check"]
        }
    }

    /// Only agy can list its own models.
    var canListModels: Bool { self == .agy }

    var blurb: String {
        switch self {
        case .agy: return "gemini models, lists its own"
        case .codex: return "gpt models, effort chosen separately"
        }
    }
}

enum AgyError: LocalizedError {
    case notFound(tool: String, searched: [String])
    case launchFailed(tool: String, String)
    case timedOut(tool: String, seconds: Int)
    case failed(tool: String, status: Int32, output: String)
    case noImageProduced(tool: String, output: String)

    var errorDescription: String? {
        switch self {
        case .notFound(let tool, let searched):
            return """
            Could not find the \(tool) command.

            Looked in: \(searched.joined(separator: ", "))

            Install \(tool), or point IconForge at it directly under Settings. \
            (Apps launched from Finder don't inherit your shell PATH, so a tool in ~/.local/bin \
            can be invisible to them even when it works in Terminal.)
            """
        case .launchFailed(let tool, let message):
            return "Could not start \(tool): \(message)"
        case .timedOut(let tool, let seconds):
            return "\(tool) did not finish within \(seconds) seconds and was stopped. Try again, or pick a faster model."
        case .failed(let tool, let status, let output):
            let tail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return """
            \(tool) exited with code \(status).

            \(tail.isEmpty ? "It printed nothing." : tail)

            If this mentions an unknown model, check the model name against what \(tool) actually offers.
            """
        case .noImageProduced(let tool, let output):
            let tail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return """
            \(tool) finished but no image file appeared.

            It said: \(tail.isEmpty ? "(nothing)" : tail)

            This usually means the model refused the prompt or ran out of its turn budget. Try regenerating.
            """
        }
    }
}

/// Thread-safe handle so the UI can cancel a run that is already in flight.
final class AgyProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func adopt(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        if cancelled {
            process.terminate()
        } else {
            self.process = process
        }
    }

    func release() {
        lock.lock()
        process = nil
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let running = process
        lock.unlock()
        running?.terminate()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

enum AgyRunner {

    /// Directories worth checking beyond PATH — a GUI app gets a bare
    /// /usr/bin:/bin PATH, so the usual install locations are spelled out.
    static var searchDirectories: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        dirs.append(contentsOf: [
            "\(home)/.local/bin",
            "\(home)/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
        ])
        return dirs
    }

    /// Resolve the agy binary: explicit override first, then the search
    /// directories, then whatever the login shell would use.
    static func resolveBinary(customPath: String, named name: String = "agy") throws -> URL {
        let fm = FileManager.default
        let trimmed = customPath.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty {
            let expanded = (trimmed as NSString).expandingTildeInPath
            guard fm.isExecutableFile(atPath: expanded) else {
                throw AgyError.notFound(tool: name, searched: [expanded])
            }
            return URL(fileURLWithPath: expanded)
        }

        var seen: [String] = []
        for dir in searchDirectories {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if !seen.contains(dir) { seen.append(dir) }
            if fm.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        if let fromShell = lookupViaLoginShell(name), fm.isExecutableFile(atPath: fromShell) {
            return URL(fileURLWithPath: fromShell)
        }

        throw AgyError.notFound(tool: name, searched: seen)
    }

    private static func lookupViaLoginShell(_ name: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", "command -v \(name)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (path?.isEmpty == false) ? path : nil
    }

    /// Model families left out of the picker.
    static let excludedModelPrefixes = ["claude"]

    /// Asks agy which models it can drive (`agy models`). Anything that isn't a
    /// bare identifier is dropped, so a stray banner line can't become a
    /// "model" in the picker.
    static func listModels(binary: URL) throws -> [String] {
        let process = Process()
        process.executableURL = binary
        process.arguments = ["models"]

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ([binary.deletingLastPathComponent().path] + searchDirectories).joined(separator: ":")
        process.environment = env

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw AgyError.launchFailed(tool: binary.lastPathComponent, error.localizedDescription)
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let text = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw AgyError.failed(tool: binary.lastPathComponent, status: process.terminationStatus, output: text)
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        var seen = Set<String>()
        return text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { name in
                guard name.count >= 2, name.count <= 60 else { return false }
                guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
                let lowered = name.lowercased()
                return !excludedModelPrefixes.contains { lowered.hasPrefix($0) }
            }
            .filter { seen.insert($0).inserted }
    }

    /// Runs `agy --model <model> -p <prompt>` and returns everything it printed.
    /// Blocking — call it off the main thread.
    static func run(binary: URL,
                    backend: GeneratorBackend,
                    effort: String,
                    model: String,
                    prompt: String,
                    workingDirectory: URL,
                    timeout: Int,
                    handle: AgyProcessHandle) throws -> String {
        let process = Process()
        process.executableURL = binary
        process.arguments = backend.arguments(model: model, effort: effort, prompt: prompt)
        process.currentDirectoryURL = workingDirectory

        // Give the child a PATH that includes wherever agy itself lives, so any
        // helper it shells out to is reachable even from a Finder-launched app.
        var env = ProcessInfo.processInfo.environment
        let extraPath = binary.deletingLastPathComponent().path
        env["PATH"] = ([extraPath] + searchDirectories).joined(separator: ":")
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        // Drain both pipes concurrently; a full pipe buffer would deadlock the child.
        let collector = OutputCollector()
        let group = DispatchGroup()
        for pipe in [outPipe, errPipe] {
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                collector.append(String(data: data, encoding: .utf8) ?? "")
            }
        }

        do {
            try process.run()
        } catch {
            throw AgyError.launchFailed(tool: backend.rawValue, error.localizedDescription)
        }
        handle.adopt(process)

        let timeoutFlag = TimeoutFlag()
        let deadline = DispatchWorkItem {
            timeoutFlag.trip()
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeout), execute: deadline)

        process.waitUntilExit()
        deadline.cancel()
        group.wait()
        handle.release()

        let output = collector.text
        if handle.isCancelled { throw CancellationError() }
        if timeoutFlag.tripped { throw AgyError.timedOut(tool: backend.rawValue, seconds: timeout) }
        guard process.terminationStatus == 0 else {
            throw AgyError.failed(tool: backend.rawValue, status: process.terminationStatus, output: output)
        }
        return output
    }

    /// Locate the artwork agy produced: the path we asked for, else a path it
    /// printed, else the newest image that appeared in the session folder.
    static func locateImage(expected: URL, output: String, sessionDir: URL, after start: Date) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: expected.path) { return expected }

        let imageExtensions = ["png", "jpg", "jpeg", "webp"]
        for token in output.split(whereSeparator: { " \t\n\"'`<>()[]".contains($0) }) {
            let candidate = String(token)
            guard imageExtensions.contains(where: { candidate.lowercased().hasSuffix(".\($0)") }) else { continue }
            let path = (candidate as NSString).expandingTildeInPath
            let url = path.hasPrefix("/")
                ? URL(fileURLWithPath: path)
                : sessionDir.appendingPathComponent(path)
            if fm.fileExists(atPath: url.path) { return url }
        }

        let contents = (try? fm.contentsOfDirectory(at: sessionDir,
                                                    includingPropertiesForKeys: [.contentModificationDateKey],
                                                    options: [.skipsHiddenFiles])) ?? []
        return contents
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .filter { modificationDate($0) >= start }
            .max { modificationDate($0) < modificationDate($1) }
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

/// Tiny lock-guarded string buffer for the two pipe readers.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""

    func append(_ chunk: String) {
        lock.lock()
        buffer += chunk
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}

/// One-way flag flipped by the timeout timer, read after the process exits.
private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func trip() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var tripped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
