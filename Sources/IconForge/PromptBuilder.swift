import Foundation

/// Style variants offered in the picker. Each one bends the material and the
/// form language without leaving the Apple house style.
enum StyleVariant: String, CaseIterable, Identifiable, Codable {
    case standard = "Standard"
    case playful = "Playful"
    case minimal = "Minimal"
    case glossy = "Glossy"

    var id: String { rawValue }

    var modifier: String {
        switch self {
        case .standard:
            return ""
        case .playful:
            return " Push it playful: rounder, chunkier proportions, a little squash and bounce in the form, warmer saturated colour."
        case .minimal:
            return " Push it minimal: reduce the subject to its simplest readable silhouette, flatter shading, almost no surface detail."
        case .glossy:
            return " Push it glossy: a polished, slightly reflective surface with one crisp specular highlight and deeper contrast."
        }
    }
}

/// One roll's art direction. Randomising these is what stops a reroll from
/// handing back the same picture with different pixels.
struct VariationRecipe {
    let angle: String
    let material: String
    let composition: String

    static let angles = [
        "Shown straight on, face to camera, symmetrical and square to the frame",
        "Shown at a gentle three-quarter angle so two faces catch the light",
        "Shown from slightly above, tilted a few degrees toward the viewer",
        "Shown straight on with a slight lean, one side catching more light",
    ]

    static let materials = [
        "clean matte-to-satin",
        "soft matte ceramic",
        "smooth satin with a faint sheen",
        "dense soft-touch plastic",
    ]

    static let compositions = [
        "The subject sits dead centre and takes up about two thirds of the frame",
        "The subject is centred and generously large, close to filling the safe area",
        "The subject is centred a touch smaller, with airy margins around it",
        "The subject is centred and bold, its silhouette unmistakable from across the room",
    ]

    static func random() -> VariationRecipe {
        VariationRecipe(angle: angles.randomElement() ?? angles[0],
                        material: materials.randomElement() ?? materials[0],
                        composition: compositions.randomElement() ?? compositions[0])
    }

    /// Distinct recipes for a batch, so the variants don't collide with each other.
    static func distinct(count: Int) -> [VariationRecipe] {
        let shuffledAngles = angles.shuffled()
        let shuffledMaterials = materials.shuffled()
        let shuffledCompositions = compositions.shuffled()
        return (0..<count).map { index in
            VariationRecipe(angle: shuffledAngles[index % shuffledAngles.count],
                            material: shuffledMaterials[index % shuffledMaterials.count],
                            composition: shuffledCompositions[index % shuffledCompositions.count])
        }
    }
}

enum PromptBuilder {

    /// The image prompt handed to agy. The "do not draw a rounded square" line
    /// has to stay in sync with the squircle mask the pipeline applies
    /// afterwards, or the icon ends up with two frames.
    static func imagePrompt(appName: String,
                            description: String,
                            subject: String,
                            palette: String,
                            style: StyleVariant,
                            variation: VariationRecipe) -> String {
        let trimmedPalette = palette.trimmingCharacters(in: .whitespacesAndNewlines)
        let paletteClause = trimmedPalette.isEmpty
            ? "a cohesive two or three colour palette that suits the app's purpose"
            : trimmedPalette

        return """
        A macOS app icon for \(appName) — an app that \(description).

        Subject: \(subject). One single object, nothing else in the picture.

        Style: the current Apple macOS icon look, the family Notes, Reminders, Podcasts and Maps belong to. A smooth, softly three-dimensional object with generously rounded edges and corners and a \(variation.material) surface. \(variation.angle). Lit from above by one broad soft studio light: gentle highlights along the upper edges, soft shading underneath, no harsh speculars and no rim lighting. Confident and simplified — bold primary forms, very little surface detail, nothing fiddly or ornamental.\(style.modifier)

        Composition: \(variation.composition). The silhouette has to stay obvious at 16 pixels, so keep the shape chunky and clearly separated from the background, with even breathing room on all four sides.

        Background: a smooth vertical gradient built from \(paletteClause), brighter at the top, filling the whole frame edge to edge. The subject reads clearly against it and floats just above it with one short, soft contact shadow.

        Format: 1024x1024, crisp clean edges, no noise or grain, no banding. The artwork fills the entire square and bleeds off all four straight edges.

        Do not draw: a rounded square, outline, border, frame or badge of any kind — the rounded icon mask is applied afterwards. No text, letters, numbers or logos. No second object, no hands, no people, no scenery, no desk, table or floor. No photographic realism, no stock-photo lighting, no busy fine detail, no drop shadow outside the subject.
        """
    }

    /// agy is an agentic CLI, not a bare image endpoint: it only leaves a file
    /// behind when the prompt tells it where to put one.
    static func agyInstruction(imagePrompt: String, outputPath: String) -> String {
        """
        Generate a single image from this description:

        \(imagePrompt)

        Save the generated image as a PNG to this exact absolute path: \(outputPath)
        Do not save it anywhere else and do not ask any follow-up questions.
        When the file is written, print only that absolute path and nothing else.
        """
    }

    /// Asks agy for icon-friendly subjects. More than one at a time keeps a
    /// batch from drawing the same object four ways.
    static func subjectsPrompt(appName: String,
                               description: String,
                               count: Int,
                               avoiding used: [String]) -> String {
        let avoidClause = used.isEmpty
            ? ""
            : "\n\nDo not suggest any of these, or anything close to them: \(used.joined(separator: "; "))."

        let quantity = count == 1
            ? "Name one object"
            : "Name \(count) genuinely different objects, one per line, no numbering or bullets"

        return """
        An app called "\(appName)" does this: \(description)

        \(quantity) that could each represent it on an app icon.

        Each one must be a single physical object with a simple, chunky silhouette that still reads at 16 pixels. \
        No scenes, no arrangements of several things, no abstract shapes, no text, no screens showing content. \
        Prefer everyday objects with a strong recognisable outline.

        Reply with the objects only, lowercase, 2 to 5 words each, no punctuation and no explanation. \
        Example replies: "a paper airplane", "a brass compass", "a stack of coins".\(avoidClause)
        """
    }

    /// Pulls usable subjects out of whatever agy printed.
    static func cleanSubjects(_ raw: String, count: Int) -> [String] {
        var seen = Set<String>()
        var results: [String] = []

        for line in raw.split(separator: "\n") {
            var candidate = line.trimmingCharacters(in: .whitespaces)
            // Strip list markers: "1.", "1)", "-", "*", "•"
            candidate = candidate.replacingOccurrences(of: #"^\s*(\d+[\.\)]|[-*•])\s*"#,
                                                       with: "",
                                                       options: .regularExpression)
            candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`.*_ "))

            guard !candidate.isEmpty,
                  candidate.count <= 60,
                  candidate.split(separator: " ").count <= 8,
                  !candidate.contains(":"),
                  seen.insert(candidate.lowercased()).inserted else { continue }

            results.append(candidate)
            if results.count == count { break }
        }
        return results
    }

    /// Last-resort subject when the model call fails.
    static func fallbackSubject(description: String) -> String {
        "a single object representing \(description.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}
