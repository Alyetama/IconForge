import Foundation

/// Style variants offered in the picker. Each one appends a sentence that
/// nudges the render without breaking the Apple house style.
enum StyleVariant: String, CaseIterable, Identifiable, Codable {
    case standard = "Standard"
    case playful = "Playful"
    case minimal = "Minimal"
    case glossy = "Glossy"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .standard: return "app.dashed"
        case .playful: return "face.smiling"
        case .minimal: return "circle.dashed"
        case .glossy: return "sparkles"
        }
    }

    var modifier: String {
        switch self {
        case .standard:
            return ""
        case .playful:
            return " Lean playful: rounder proportions, a touch more bounce in the form, warmer and more saturated colours."
        case .minimal:
            return " Lean minimal: strip the subject to its simplest readable silhouette, flatter shading, restrained two-colour background."
        case .glossy:
            return " Lean glossy: a polished, slightly reflective surface with a crisp specular highlight and deeper contrast."
        }
    }
}

enum PromptBuilder {

    /// The image prompt handed to agy. The trailing "do not draw a rounded
    /// square" instruction has to stay in sync with the squircle mask the
    /// pipeline applies afterwards — two frames would be one too many.
    static func imagePrompt(appName: String,
                            description: String,
                            subject: String,
                            palette: String,
                            style: StyleVariant) -> String {
        let trimmedPalette = palette.trimmingCharacters(in: .whitespacesAndNewlines)
        let paletteClause = trimmedPalette.isEmpty ? "" : " (\(trimmedPalette))"

        return """
        A macOS app icon for \(appName) — an app that \(description). The icon shows \(subject), a single centered subject that reads instantly at small sizes.

        Render it in the current Apple macOS style — the family look of Notes, Reminders, Podcasts, and Maps. The subject is a smooth, softly three-dimensional object with rounded edges and a clean matte-to-satin surface, lit from top-center by a soft light with gentle highlights on upper faces and subtle shadow beneath. Simplified and iconic, never busy — one hero object, minimal detail, no clutter.\(style.modifier)

        Background: a smooth vertical gradient in a cohesive 2–3 color palette\(paletteClause) that fits the app's purpose, brighter at the top, filling the whole frame. The subject floats slightly above it with a short, soft contact shadow.

        Format: 1024x1024, subject centered with even breathing room on all sides, crisp edges, high detail. The artwork must fill the entire square and bleed off all four straight edges. Do NOT draw a rounded square, border, frame, or squircle outline — the rounded icon mask is applied afterward. No text, letters, numbers, or logos anywhere.
        """
    }

    /// agy is an agentic CLI, not a bare image endpoint: it only leaves a file
    /// behind when the prompt tells it where to put one, so the save
    /// instruction is appended to whatever goes over the wire.
    static func agyInstruction(imagePrompt: String, outputPath: String) -> String {
        """
        Generate a single image from this description:

        \(imagePrompt)

        Save the generated image as a PNG to this exact absolute path: \(outputPath)
        Do not save it anywhere else and do not ask any follow-up questions.
        When the file is written, print only that absolute path and nothing else.
        """
    }

    /// Asks agy for the one literal object the artwork should show.
    static func subjectPrompt(appName: String, description: String) -> String {
        """
        An app called "\(appName)" does this: \(description)

        Name the single most literal physical object that would represent it on an app icon. \
        One object, no scene, no text, nothing abstract.

        Reply with only that object as a short noun phrase of 2 to 5 words, lowercase, no punctuation, no explanation. \
        Example replies: "a paper airplane", "a brass compass", "a stack of coins".
        """
    }

    /// agy sometimes wraps its answer in quotes or a sentence; keep the last
    /// usable line and drop anything that looks like commentary.
    static func cleanSubject(_ raw: String) -> String? {
        let line = raw
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last(where: { !$0.isEmpty })

        guard var subject = line else { return nil }
        subject = subject.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`.*_ "))
        guard !subject.isEmpty, subject.count <= 60, subject.split(separator: " ").count <= 8 else { return nil }
        return subject
    }

    /// Last-resort subject when the model call fails — the description itself
    /// still gives the image model something concrete to hold onto.
    static func fallbackSubject(description: String) -> String {
        "a single object representing \(description.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}
