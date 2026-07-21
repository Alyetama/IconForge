import SwiftUI

/// One palette offered in the picker. Colour counts vary between three and ten.
struct ColorPalette: Identifiable, Hashable {
    let rank: Int
    let name: String?
    let hexes: [String]

    var id: Int { rank }

    var colors: [Color] { hexes.map(Color.init(hex:)) }

    var displayName: String { name ?? "Palette \(rank)" }

    /// Colours named in the image prompt. Long palettes are trimmed: past half
    /// a dozen the model starts sprinkling them around instead of choosing.
    var promptColors: [String] { Array(hexes.prefix(6)) }

    var promptHint: String {
        let list = promptColors.map { "#\($0)" }.joined(separator: ", ")
        if let name {
            return "the \"\(name)\" palette: \(list)"
        }
        return "these exact colours: \(list)"
    }
}

enum PaletteLibrary {
    /// Which palette produced a given hint, so a restored run shows its swatch.
    static func matching(hint: String) -> ColorPalette? {
        let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trending.first { $0.promptHint == trimmed }
    }
}

extension Color {
    /// Six-digit RGB hex, with or without the leading hash.
    init(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt64(cleaned, radix: 16) ?? 0
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255,
                  opacity: 1)
    }
}

/// The palette's colours as bars in one rounded pill.
struct PaletteSwatch: View {
    let palette: ColorPalette
    var height: CGFloat = 22
    var cornerRadius: CGFloat = 5

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(palette.colors.enumerated()), id: \.offset) { _, color in
                Rectangle().fill(color)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}
