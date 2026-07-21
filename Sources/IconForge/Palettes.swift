import SwiftUI

/// A four-colour palette offered in the picker.
struct ColorPalette: Identifiable, Hashable {
    let rank: Int
    let hexes: [String]

    var id: Int { rank }

    var colors: [Color] { hexes.map(Color.init(hex:)) }

    /// What gets dropped into the image prompt. Naming the exact hex values
    /// keeps the render close to the swatch the user clicked.
    var promptHint: String {
        "built from these exact colours: " + hexes.map { "#\($0)" }.joined(separator: ", ")
    }
}

/// The 50 most-liked ColorHunt palettes (colorhunt.co/palettes/popular).
enum PaletteLibrary {
    static let popular: [ColorPalette] = [
        ColorPalette(rank: 1, hexes: ["222831", "393E46", "00ADB5", "EEEEEE"]),
        ColorPalette(rank: 2, hexes: ["E3FDFD", "CBF1F5", "A6E3E9", "71C9CE"]),
        ColorPalette(rank: 3, hexes: ["F9F7F7", "DBE2EF", "3F72AF", "112D4E"]),
        ColorPalette(rank: 4, hexes: ["FFF5E4", "FFE3E1", "FFD1D1", "FF9494"]),
        ColorPalette(rank: 5, hexes: ["F9F5F6", "F8E8EE", "FDCEDF", "F2BED1"]),
        ColorPalette(rank: 6, hexes: ["AD8B73", "CEAB93", "E3CAA5", "FFFBE9"]),
        ColorPalette(rank: 7, hexes: ["FFC7C7", "FFE2E2", "F6F6F6", "8785A2"]),
        ColorPalette(rank: 8, hexes: ["F4EEFF", "DCD6F7", "A6B1E1", "424874"]),
        ColorPalette(rank: 9, hexes: ["1B262C", "0F4C75", "3282B8", "BBE1FA"]),
        ColorPalette(rank: 10, hexes: ["27374D", "526D82", "9DB2BF", "DDE6ED"]),
        ColorPalette(rank: 11, hexes: ["08D9D6", "252A34", "FF2E63", "EAEAEA"]),
        ColorPalette(rank: 12, hexes: ["F9ED69", "F08A5D", "B83B5E", "6A2C70"]),
        ColorPalette(rank: 13, hexes: ["F38181", "FCE38A", "EAFFD0", "95E1D3"]),
        ColorPalette(rank: 14, hexes: ["B1B2FF", "AAC4FF", "D2DAFF", "EEF1FF"]),
        ColorPalette(rank: 15, hexes: ["B7C4CF", "EEE3CB", "D7C0AE", "967E76"]),
        ColorPalette(rank: 16, hexes: ["6096B4", "93BFCF", "BDCDD6", "EEE9DA"]),
        ColorPalette(rank: 17, hexes: ["FFB6B9", "FAE3D9", "BBDED6", "61C0BF"]),
        ColorPalette(rank: 18, hexes: ["A8D8EA", "AA96DA", "FCBAD3", "FFFFD2"]),
        ColorPalette(rank: 19, hexes: ["FFEDDB", "EDCDBB", "E3B7A0", "BF9270"]),
        ColorPalette(rank: 20, hexes: ["8D7B68", "A4907C", "C8B6A6", "F1DEC9"]),
        ColorPalette(rank: 21, hexes: ["7D5A50", "B4846C", "E5B299", "FCDEC0"]),
        ColorPalette(rank: 22, hexes: ["F8EDE3", "BDD2B6", "A2B29F", "798777"]),
        ColorPalette(rank: 23, hexes: ["364F6B", "3FC1C9", "F5F5F5", "FC5185"]),
        ColorPalette(rank: 24, hexes: ["FFF8EA", "9E7676", "815B5B", "594545"]),
        ColorPalette(rank: 25, hexes: ["2C3639", "3F4E4F", "A27B5C", "DCD7C9"]),
        ColorPalette(rank: 26, hexes: ["FCD1D1", "ECE2E1", "D3E0DC", "AEE1E1"]),
        ColorPalette(rank: 27, hexes: ["FFE6E6", "F2D1D1", "DAEAF1", "C6DCE4"]),
        ColorPalette(rank: 28, hexes: ["DEFCF9", "CADEFC", "C3BEF0", "CCA8E9"]),
        ColorPalette(rank: 29, hexes: ["F5EFE6", "E8DFCA", "AEBDCA", "7895B2"]),
        ColorPalette(rank: 30, hexes: ["EDF1D6", "9DC08B", "609966", "40513B"]),
        ColorPalette(rank: 31, hexes: ["867070", "D5B4B4", "E4D0D0", "F5EBEB"]),
        ColorPalette(rank: 32, hexes: ["F7FBFC", "D6E6F2", "B9D7EA", "769FCD"]),
        ColorPalette(rank: 33, hexes: ["FEFCF3", "F5EBE0", "F0DBDB", "DBA39A"]),
        ColorPalette(rank: 34, hexes: ["96B6C5", "ADC4CE", "EEE0C9", "F1F0E8"]),
        ColorPalette(rank: 35, hexes: ["F67280", "C06C84", "6C5B7B", "355C7D"]),
        ColorPalette(rank: 36, hexes: ["C4DFDF", "D2E9E9", "E3F4F4", "F8F6F4"]),
        ColorPalette(rank: 37, hexes: ["FCD8D4", "FDF6F0", "F8E2CF", "F5C6AA"]),
        ColorPalette(rank: 38, hexes: ["212121", "323232", "0D7377", "14FFEC"]),
        ColorPalette(rank: 39, hexes: ["93B5C6", "C9CCD5", "E4D8DC", "FFE3E3"]),
        ColorPalette(rank: 40, hexes: ["2B2E4A", "E84545", "903749", "53354A"]),
        ColorPalette(rank: 41, hexes: ["000000", "3D0000", "950101", "FF0000"]),
        ColorPalette(rank: 42, hexes: ["F5F7F8", "F4CE14", "495E57", "45474B"]),
        ColorPalette(rank: 43, hexes: ["F8EDE3", "DFD3C3", "D0B8A8", "7D6E83"]),
        ColorPalette(rank: 44, hexes: ["FDEFEF", "F4DFD0", "DAD0C2", "CDBBA7"]),
        ColorPalette(rank: 45, hexes: ["E4F9F5", "30E3CA", "11999E", "40514E"]),
        ColorPalette(rank: 46, hexes: ["F6F6F6", "FFE2E2", "FFC7C7", "AAAAAA"]),
        ColorPalette(rank: 47, hexes: ["A75D5D", "D3756B", "F0997D", "FFC3A1"]),
        ColorPalette(rank: 48, hexes: ["F2D7D9", "D3CEDF", "9CB4CC", "748DA6"]),
        ColorPalette(rank: 49, hexes: ["E23E57", "88304E", "522546", "311D3F"]),
        ColorPalette(rank: 50, hexes: ["F3EEEA", "EBE3D5", "B0A695", "776B5D"]),
    ]

    /// Which palette produced a given hint, so a restored run shows its swatch.
    static func matching(hint: String) -> ColorPalette? {
        let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return popular.first { $0.promptHint == trimmed }
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

/// Four colour bars in one rounded pill, the shape used everywhere a palette
/// needs to be shown at a glance.
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
