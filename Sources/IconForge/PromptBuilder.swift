import Foundation

/// Style variants offered in the picker. Each one bends the material and the
/// form language without leaving the Apple house style.
enum StyleVariant: String, CaseIterable, Identifiable, Codable {
    case standard = "Standard"
    case playful = "Playful"
    case minimal = "Minimal"
    case glossy = "Glossy"
    case technical = "Technical"
    case editorial = "Editorial"
    case retro = "Retro"
    case luxe = "Luxe"
    case organic = "Organic"
    case neon = "Neon"

    var id: String { rawValue }

    var blurb: String {
        switch self {
        case .standard: return "Straight Apple house style"
        case .playful: return "Consumer app, friendly and bouncy"
        case .minimal: return "Stripped back, utility-like"
        case .glossy: return "Polished, premium consumer feel"
        case .technical: return "Developer tool, precise and engineered"
        case .editorial: return "Writing and reading, paper and ink"
        case .retro: return "Warm vintage hardware"
        case .luxe: return "Finance or pro tool, expensive materials"
        case .organic: return "Health and nature, soft and tactile"
        case .neon: return "Media and creative, lit from within"
        }
    }

    /// A direct visual directive appended to the form paragraph. Naming the
    /// app's purpose here turned out to add noise without steering the picture,
    /// so these describe the look and nothing else.
    var modifier: String {
        switch self {
        case .standard:
            return ""
        case .playful:
            return " Make it charming and toy-like: extra-plump proportions with squash-and-stretch curves, candy-bright saturated colour, glossy highlights, an almost huggable character."
        case .minimal:
            return " Strip it to essentials: the simplest possible readable form, near-flat shading with one soft gradient, a single restrained colour plus one neutral, absolutely no ornament."
        case .glossy:
            return " Give it a premium sheen: polished reflective surfaces, one crisp window-shaped specular highlight, deep rich colour with strong dark-to-light contrast."
        case .technical:
            return " Make it precisely engineered: crisp machined geometry with chamfered edges, brushed-metal accents, a cool restrained palette, the feel of a precision instrument."
        case .editorial:
            return " Give it a print feel: matte paper and ink materials, layered card with clean cut edges, warm neutral tones with one strong accent colour."
        case .retro:
            return " Style it as warm vintage hardware: rounded 1970s industrial forms, creamy enamel and beige plastic, muted period colour with one orange or teal accent."
        case .luxe:
            return " Make it feel expensive: dense materials — anodised metal, smoked glass, deep lacquer — a dark restrained palette, one quiet metallic accent, museum-grade lighting."
        case .organic:
            return " Make it soft and natural: gently asymmetric hand-shaped forms, tactile matte surfaces, fresh botanical colour, the warmth of a crafted object."
        case .neon:
            return " Light it from within: the object glows against a deep, near-black background, luminous edges and hot colour accents, strong contrast, clean dark surroundings with no haze."
        }
    }

    /// Materials that suit this style. Without this, a roll could pair
    /// Editorial with injection-moulded plastic and argue with itself.
    var preferredMaterials: [String]? {
        switch self {
        case .standard:
            return nil
        case .playful:
            return ["glossy injection-moulded plastic, toy-like and colour-saturated",
                    "glossy ceramic with one crisp, window-shaped highlight"]
        case .minimal:
            return ["smooth matte ceramic with a satin sheen across the top surfaces",
                    "dense soft-touch rubberised plastic, deep and light-absorbing"]
        case .glossy:
            return ["glossy ceramic with one crisp, window-shaped highlight",
                    "deep polished lacquer with one long, soft reflection",
                    "glossy injection-moulded plastic, toy-like and colour-saturated"]
        case .technical:
            return ["brushed anodised aluminium with a cool directional sheen",
                    "dense soft-touch rubberised plastic, deep and light-absorbing"]
        case .editorial:
            return ["clean layered card stock with crisp cut edges",
                    "smooth matte ceramic with a satin sheen across the top surfaces"]
        case .retro:
            return ["glossy injection-moulded plastic, toy-like and colour-saturated",
                    "smooth matte ceramic with a satin sheen across the top surfaces"]
        case .luxe:
            return ["brushed anodised aluminium with a cool directional sheen",
                    "deep polished lacquer with one long, soft reflection",
                    "frosted glass with a soft inner glow, edges catching the light"]
        case .organic:
            return ["clean layered card stock with crisp cut edges",
                    "smooth matte ceramic with a satin sheen across the top surfaces"]
        case .neon:
            return ["frosted glass with a soft inner glow, edges catching the light",
                    "deep polished lacquer with one long, soft reflection",
                    "glossy ceramic with one crisp, window-shaped highlight"]
        }
    }
}

/// Post-processing finishes applied to the masked body after the artwork comes
/// back. These are local Core Graphics passes, so switching between them is
/// instant and costs nothing.
enum IconFinish: String, CaseIterable, Identifiable, Codable {
    case flat = "Flat"
    case appleEdge = "Apple edge"
    case glossyDome = "Glossy dome"
    case deepShadow = "Deep shadow"
    case punchy = "Punchy"

    var id: String { rawValue }

    var blurb: String {
        switch self {
        case .flat: return "The artwork exactly as generated"
        case .appleEdge: return "Lit top edge and shaded base, the way system icons catch light"
        case .glossyDome: return "Apple edge plus a soft dome highlight over the top half"
        case .deepShadow: return "Apple edge with a heavier, further drop shadow"
        case .punchy: return "Apple edge with richer colour and a touch more contrast"
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
        "Shown perfectly straight on, symmetrical and square to the frame.",
        "Shown at a gentle three-quarter turn so two faces catch the light differently.",
        "Shown from slightly above, tipped a few degrees toward the viewer.",
        "Shown straight on but rotated a playful few degrees off vertical.",
        "Shown from a slightly low three-quarter angle so the object feels quietly monumental.",
    ]

    /// Each finish carries its own highlight behaviour, which is where the
    /// visible difference between rolls actually comes from.
    static let materials = [
        "glossy ceramic with one crisp, window-shaped highlight",
        "frosted glass with a soft inner glow, edges catching the light",
        "smooth matte ceramic with a satin sheen across the top surfaces",
        "dense soft-touch rubberised plastic, deep and light-absorbing",
        "brushed anodised aluminium with a cool directional sheen",
        "clean layered card stock with crisp cut edges",
        "glossy injection-moulded plastic, toy-like and colour-saturated",
        "deep polished lacquer with one long, soft reflection",
    ]

    /// Deliberately similar: icons should always be centred and large, so the
    /// variety budget goes to material and angle instead.
    static let compositions = [
        "The object sits dead centre at about two-thirds the height of the frame.",
        "The object is centred and confident, nearly filling the central safe zone.",
        "The object is centred a touch smaller, floating with airy margins all around.",
        "The object is centred and feels close to the camera, large and softly rounded, its silhouette unmistakable.",
    ]

    static func random(style: StyleVariant = .standard) -> VariationRecipe {
        let pool = style.preferredMaterials ?? materials
        return VariationRecipe(angle: angles.randomElement() ?? angles[0],
                               material: pool.randomElement() ?? materials[0],
                               composition: compositions.randomElement() ?? compositions[0])
    }

    /// Distinct recipes for a batch, so the variants don't collide with each other.
    static func distinct(count: Int, style: StyleVariant = .standard) -> [VariationRecipe] {
        let shuffledAngles = angles.shuffled()
        let shuffledMaterials = (style.preferredMaterials ?? materials).shuffled()
        let shuffledCompositions = compositions.shuffled()
        return (0..<count).map { index in
            VariationRecipe(angle: shuffledAngles[index % shuffledAngles.count],
                            material: shuffledMaterials[index % shuffledMaterials.count],
                            composition: shuffledCompositions[index % shuffledCompositions.count])
        }
    }
}

enum PromptBuilder {

    /// The image prompt handed to agy.
    ///
    /// It describes the artwork, not the artifact: saying "app icon" pulled the
    /// model toward icon *presentations* (rounded rectangles, badges, mockups),
    /// which then had to be fought with a long list of prohibitions. The app
    /// name is gone too, since it invited rendered text. The mask this pipeline
    /// applies afterwards is why the object has to stay inside the central 70%.
    static func imagePrompt(description: String,
                            subject: String,
                            palette: String,
                            style: StyleVariant,
                            variation: VariationRecipe) -> String {
        let trimmedPalette = palette.trimmingCharacters(in: .whitespacesAndNewlines)
        let paletteClause = trimmedPalette.isEmpty
            ? "a cohesive palette of one dominant hue plus one supporting accent that suits an app that \(description)"
            : trimmedPalette

        return """
        A polished 3D render of \(subject) — the soft, friendly, high-end 3D illustration style used for modern Mac app artwork. Exactly one object on a clean gradient backdrop, nothing else in frame.

        Form: confident and simplified — a few big, rounded primary masses in \(variation.material). Every edge and corner generously rounded. Keep only a handful of bold, functional details; no fine texture, engraving, patterning or clutter. The object should look like a beautifully manufactured physical product, not a photograph.\(style.modifier)

        \(variation.angle)

        Light: one broad, soft studio key light from the upper front, a faint cool fill from below, and gentle ambient occlusion where surfaces meet, so the object feels genuinely dimensional. Give the top surfaces one controlled highlight appropriate to the material; keep all shading smooth and creamy, with no harsh cross-shadows.

        Colour: built from \(paletteClause). Put the deepest tone at the bottom of the background and a lighter tone toward the top, and keep the object's own colours clearly separated from the backdrop so the silhouette pops — a light object on a deeper background, or a deep object on a lighter background. Add a soft, subtle radial glow behind the object to lift it off the backdrop, and one short, soft contact shadow directly beneath it.

        Composition: \(variation.composition) The whole object stays inside the central 70% of the canvas with even breathing room on all sides — the outer band and corners are pure background, because the image is cropped later. The silhouette must stay instantly readable at thumbnail size.

        Background: one smooth, immaculate gradient filling the entire 1024x1024 square and bleeding off all four edges — no noise, grain, banding, texture, vignetting or scenery.

        The frame contains exactly one object on that gradient and nothing more: no text or lettering, no border, badge or container shape of any kind, no extra props, hands, people or surfaces.
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

    /// Asks agy to edit an icon that already exists rather than draw a new one.
    static func refineInstruction(sourcePath: String,
                                  outputPath: String,
                                  request: String,
                                  style: StyleVariant,
                                  recolourTo palette: String?) -> String {
        // The style directive rides along so picking one in edit mode does
        // something; without it the edit would silently ignore the picker.
        let styleNote = style.modifier.isEmpty ? "" : "\n\nHold to this look while you do it:\(style.modifier)"

        // A recolour has to override the "keep the palette" line, or the two
        // instructions contradict each other and the model picks one.
        let keepLine = palette.map { new in
            "Keep the same subject, composition and camera angle, but recolour it to use \(new). Repaint the background gradient and the object's colours in those colours, and keep the deepest tone at the bottom."
        } ?? "Keep the same subject, composition, camera angle and colour palette."

        return """
        Edit an existing image.

        Read the image at this path: \(sourcePath)

        \(keepLine) Change only this: \(request)\(styleNote)

        Everything else about the picture stays as it is. Keep it a single centred object on a smooth gradient background, filling the whole square and bleeding off all four straight edges. Do not add a rounded square, border, frame, text, letters or numbers.

        Save the edited image as a PNG at exactly 1024x1024 to this absolute path: \(outputPath)
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
        // Scoped per app by the caller, so this list only ever holds objects
        // already used for this same app.
        let avoidClause = used.isEmpty
            ? ""
            : "\n\nDo not suggest any of these or close variants: \(used.joined(separator: "; "))"

        return """
        You are choosing the subject for a macOS app icon.

        The app: "\(appName)" — \(description).

        Suggest \(count) different objects. Mix two kinds:
        - literal: an object people directly associate with what the app does
        - lateral: an object that captures the app's feeling or outcome through a simple metaphor (growth → a sprout; speed → a paper dart; scheduling → a mechanical timer)

        Rules for every object:
        - one single physical object with a bold, chunky, instantly recognisable silhouette that survives at 16 pixels
        - concrete nouns only — no scenes, groups of things, abstract shapes, screens, text or symbols
        - avoid tired icon clichés — gear, lightbulb, rocket, generic star, magnifying glass, checkmark — unless the app is literally about that object
        - word each as 2 to 6 lowercase words: the object plus at most one vivid form or character adjective (e.g. "a plump paper dart", "a stout brass bell", "a squat mechanical timer")\(avoidClause)

        Reply with the objects only, one per line, no numbering, no punctuation, no explanation.
        """
    }

    /// Words that mean the model is talking to us rather than naming an object.
    /// Without this, a stray "sure here are four ideas" passes every other
    /// check and becomes the subject of an icon.
    private static let chatterWords: Set<String> = [
        "sure", "here", "heres", "okay", "ok", "certainly", "option", "options",
        "idea", "ideas", "object", "objects", "icon", "icons", "app", "apps",
        "suggestion", "suggestions", "note", "reply", "answer", "represent",
        "representing", "these", "below", "following", "choice", "choices",
    ]

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

            let words = candidate.lowercased()
                .split(whereSeparator: { !$0.isLetter })
                .map(String.init)

            guard !candidate.isEmpty,
                  candidate.count <= 60,
                  words.count >= 1,
                  words.count <= 6,
                  !candidate.contains(":"),
                  !words.contains(where: { chatterWords.contains($0) }),
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
