import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Tunable geometry
//
// A macOS Big Sur+ app icon is not full-bleed. The artwork lives inside a
// continuous-corner "squircle" body centred on a larger transparent canvas;
// the surrounding margin is where the drop shadow lands. Everything here is
// expressed in pixels on the 1024 canvas — tweak and rebuild.

enum IconGeometry {
    /// Full canvas edge, in pixels. Apple ships 1024 for the @2x 512 slot.
    static let canvas: CGFloat = 1024
    /// Edge of the visible icon body. ~100px of transparent margin per side.
    static let bodySize: CGFloat = 824
    /// Corner radius as a fraction of the body edge (Apple's ratio ≈ 0.2237).
    static let cornerRadiusRatio: CGFloat = 0.2237
    /// Superellipse exponent for the corner curve. 2 = plain circular arc,
    /// higher = flatter, more "continuous". 5 matches Apple's squircle closely.
    static let squircleExponent: CGFloat = 5
    /// Line segments per corner. 96 is well past visually smooth at 1024px.
    static let cornerSampleCount = 96

    static let shadowBlur: CGFloat = 22
    static let shadowOffsetDown: CGFloat = 10
    static let shadowOpacity: CGFloat = 0.28
}

/// How much of the 1024 canvas the icon body fills.
///
/// Apple's own template leaves a wide transparent margin for the shadow, which
/// is correct but makes an icon look small next to the many third-party apps
/// that fill more of their tile.
enum IconBodySize: String, CaseIterable, Identifiable, Codable {
    case appleStandard = "Apple standard"
    case large = "Large"
    case fullBleed = "Full bleed"

    var id: String { rawValue }

    /// Body edge in pixels on the 1024 canvas.
    var pixels: CGFloat {
        switch self {
        case .appleStandard: return 824
        case .large: return 928
        case .fullBleed: return 1024
        }
    }

    var blurb: String {
        switch self {
        case .appleStandard: return "824 of 1024, Apple's template margin"
        case .large: return "928 of 1024, fills more of the tile"
        case .fullBleed: return "Plain square, no mask — macOS 26 applies its own"
        }
    }
}

/// Apple's required .iconset members: (file name, rendered pixel size).
let iconsetEntries: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

// MARK: - Errors

enum IconPipelineError: LocalizedError {
    case unreadableImage(URL)
    case contextFailure
    case encodeFailure(URL)
    case iconutilMissing
    case iconutilFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableImage(let url):
            return "Could not read the generated image at \(url.path). The file may be empty or in an unexpected format."
        case .contextFailure:
            return "Core Graphics refused to create a drawing context. This usually means the machine is out of memory."
        case .encodeFailure(let url):
            return "Could not write a PNG to \(url.path). Check that the output folder is writable."
        case .iconutilMissing:
            return "/usr/bin/iconutil is missing. It ships with the macOS command line tools — install them with: xcode-select --install"
        case .iconutilFailed(let message):
            return "iconutil could not build the .icns file.\n\n\(message)"
        }
    }
}

// MARK: - Pipeline

enum IconPipeline {

    /// Everything a finished run leaves behind on disk.
    struct Artifacts {
        let sessionDir: URL
        let rawPNG: URL
        let maskedPNG: URL
        let iconsetDir: URL
        let icns: URL
        let ico: URL
    }

    /// Full post-process: raw artwork in, complete icon set out.
    static func process(rawImage rawURL: URL,
                        into sessionDir: URL,
                        finish: IconFinish = .appleEdge,
                        bodySize: IconBodySize = .fullBleed) throws -> Artifacts {
        var source = try normalize(try loadImage(at: rawURL))
        if finish == .punchy { source = try enrich(source) }

        // Full bleed ships the square untouched: macOS 26 wraps a legacy .icns
        // in its own rounded plate, so any mask or margin of ours would sit
        // inside that plate and read as a border.
        let body = bodySize == .fullBleed
            ? try applyFinish(finish, to: source, rounded: false)
            : try applyFinish(finish, to: try maskBody(from: source, edge: bodySize.pixels))
        let masked = try composite(body: body, finish: finish)

        let maskedURL = sessionDir.appendingPathComponent("icon_1024.png")
        try writePNG(masked, to: maskedURL)

        let iconsetDir = sessionDir.appendingPathComponent("AppIcon.iconset")
        try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
        for entry in iconsetEntries {
            let scaled = try resize(masked, to: entry.pixels)
            try writePNG(scaled, to: iconsetDir.appendingPathComponent(entry.name))
        }

        let icnsURL = sessionDir.appendingPathComponent("AppIcon.icns")
        try runIconutil(iconset: iconsetDir, output: icnsURL)

        let icoURL = sessionDir.appendingPathComponent("AppIcon.ico")
        try ICOWriter.write(from: masked, to: icoURL)

        return Artifacts(sessionDir: sessionDir,
                         rawPNG: rawURL,
                         maskedPNG: maskedURL,
                         iconsetDir: iconsetDir,
                         icns: icnsURL,
                         ico: icoURL)
    }

    // MARK: Source handling

    static func loadImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw IconPipelineError.unreadableImage(url)
        }
        return image
    }

    /// Centre-crop to a square, then redraw at the full canvas size so the rest
    /// of the pipeline can assume exactly 1024×1024 regardless of what came in.
    static func normalize(_ image: CGImage) throws -> CGImage {
        let side = min(image.width, image.height)
        let cropRect = CGRect(x: (image.width - side) / 2,
                              y: (image.height - side) / 2,
                              width: side, height: side)
        let square = image.cropping(to: cropRect) ?? image

        let size = Int(IconGeometry.canvas)
        let ctx = try makeContext(size: size)
        ctx.draw(square, in: CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size)))
        guard let out = ctx.makeImage() else { throw IconPipelineError.contextFailure }
        return out
    }

    // MARK: Squircle

    /// Continuous-corner rounded rectangle. Each corner is a superellipse
    /// quadrant, which is what gives the shape its Apple-ish "no visible seam
    /// where the arc meets the edge" quality.
    static func squirclePath(in rect: CGRect) -> CGPath {
        let radius = min(rect.width, rect.height) * IconGeometry.cornerRadiusRatio
        let path = CGMutablePath()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + radius))

        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        addCorner(path, corner: CGPoint(x: rect.minX, y: rect.maxY),
                  from: CGVector(dx: 0, dy: -1), to: CGVector(dx: 1, dy: 0), radius: radius)

        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        addCorner(path, corner: CGPoint(x: rect.maxX, y: rect.maxY),
                  from: CGVector(dx: -1, dy: 0), to: CGVector(dx: 0, dy: -1), radius: radius)

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + radius))
        addCorner(path, corner: CGPoint(x: rect.maxX, y: rect.minY),
                  from: CGVector(dx: 0, dy: 1), to: CGVector(dx: -1, dy: 0), radius: radius)

        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        addCorner(path, corner: CGPoint(x: rect.minX, y: rect.minY),
                  from: CGVector(dx: 1, dy: 0), to: CGVector(dx: 0, dy: 1), radius: radius)

        path.closeSubpath()
        return path
    }

    /// Walks one corner along |u|^n + |v|^n = 1 in the (u, v) basis, so the
    /// curve starts tangent to one edge and ends tangent to the next.
    private static func addCorner(_ path: CGMutablePath,
                                  corner: CGPoint,
                                  from u: CGVector,
                                  to v: CGVector,
                                  radius: CGFloat) {
        // In the (u, v) basis the curve satisfies |1 - a|^n + |1 - b|^n = 1, so
        // it leaves the first edge tangentially and arrives at the second the
        // same way. Dropping the "1 -" here inverts the corner into a notch.
        let exponent = 2 / IconGeometry.squircleExponent
        for step in 0...IconGeometry.cornerSampleCount {
            let t = CGFloat(step) / CGFloat(IconGeometry.cornerSampleCount) * (.pi / 2)
            let a = 1 - pow(sin(t), exponent)
            let b = 1 - pow(cos(t), exponent)
            path.addLine(to: CGPoint(x: corner.x + radius * (u.dx * a + v.dx * b),
                                     y: corner.y + radius * (u.dy * a + v.dy * b)))
        }
    }

    // MARK: Masking & composition

    /// Squircle-clipped artwork at body size, transparent outside the shape.
    static func maskBody(from source: CGImage, edge: CGFloat = IconGeometry.bodySize) throws -> CGImage {
        let size = Int(edge)
        let ctx = try makeContext(size: size)
        let rect = CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size))
        ctx.addPath(squirclePath(in: rect))
        ctx.clip()
        ctx.draw(source, in: rect)
        guard let out = ctx.makeImage() else { throw IconPipelineError.contextFailure }
        return out
    }

    // MARK: Finishes

    /// The edge treatment that separates a system icon from a flat picture in a
    /// rounded box: a lit top lip, a shaded base, and a hairline inside the
    /// silhouette. All of it is clipped to the squircle, so nothing spills.
    static func applyFinish(_ finish: IconFinish, to body: CGImage, rounded: Bool = true) throws -> CGImage {
        guard finish != .flat else { return body }

        let size = CGFloat(body.width)
        let ctx = try makeContext(size: body.width)
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        ctx.draw(body, in: rect)

        // A square clip when the system will be doing the rounding itself.
        let path = rounded ? squirclePath(in: rect) : CGPath(rect: rect, transform: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()

        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw IconPipelineError.contextFailure }

        // Lit top lip.
        if let top = CGGradient(colorsSpace: space,
                                colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.34),
                                         CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
                                locations: [0, 1]) {
            ctx.drawLinearGradient(top,
                                   start: CGPoint(x: 0, y: size),
                                   end: CGPoint(x: 0, y: size * 0.80),
                                   options: [])
        }

        // Shaded base.
        if let bottom = CGGradient(colorsSpace: space,
                                   colors: [CGColor(red: 0, green: 0, blue: 0, alpha: 0.22),
                                            CGColor(red: 0, green: 0, blue: 0, alpha: 0)] as CFArray,
                                   locations: [0, 1]) {
            ctx.drawLinearGradient(bottom,
                                   start: CGPoint(x: 0, y: 0),
                                   end: CGPoint(x: 0, y: size * 0.24),
                                   options: [])
        }

        if finish == .glossyDome {
            // A wide, shallow highlight sitting over the top half.
            let dome = CGRect(x: -size * 0.25, y: size * 0.42,
                              width: size * 1.5, height: size * 0.95)
            ctx.saveGState()
            ctx.addEllipse(in: dome)
            ctx.clip()
            if let sheen = CGGradient(colorsSpace: space,
                                      colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
                                               CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
                                      locations: [0, 1]) {
                ctx.drawLinearGradient(sheen,
                                       start: CGPoint(x: 0, y: size),
                                       end: CGPoint(x: 0, y: size * 0.5),
                                       options: [])
            }
            ctx.restoreGState()
        }

        // Hairline just inside the silhouette. The stroke straddles the path and
        // the clip removes its outer half, which is exactly the inner edge.
        // Pointless on a square the system is about to round away.
        if rounded {
            ctx.addPath(path)
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.30))
            ctx.setLineWidth(size * 0.006)
            ctx.strokePath()
        }

        ctx.restoreGState()

        guard let out = ctx.makeImage() else { throw IconPipelineError.contextFailure }
        return out
    }

    /// Slightly richer colour for the punchy finish.
    static func enrich(_ image: CGImage) throws -> CGImage {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(1.18, forKey: kCIInputSaturationKey)
        filter.setValue(1.05, forKey: kCIInputContrastKey)
        guard let output = filter.outputImage,
              let rendered = CIContext().createCGImage(output, from: input.extent) else { return image }
        return rendered
    }

    /// Body centred on the transparent canvas with a soft shadow beneath it.
    static func composite(body: CGImage, finish: IconFinish = .appleEdge) throws -> CGImage {
        let size = Int(IconGeometry.canvas)
        let ctx = try makeContext(size: size)
        let edge = CGFloat(body.width)
        let inset = (IconGeometry.canvas - edge) / 2

        let deep = finish == .deepShadow
        let opacity = deep ? 0.38 : IconGeometry.shadowOpacity
        let blur = deep ? IconGeometry.shadowBlur * 1.5 : IconGeometry.shadowBlur
        let drop = deep ? IconGeometry.shadowOffsetDown * 1.6 : IconGeometry.shadowOffsetDown

        let shadow = CGColor(red: 0, green: 0, blue: 0, alpha: opacity)
        ctx.setShadow(offset: CGSize(width: 0, height: -drop),
                      blur: blur,
                      color: shadow)
        ctx.draw(body, in: CGRect(x: inset, y: inset, width: edge, height: edge))

        guard let out = ctx.makeImage() else { throw IconPipelineError.contextFailure }
        return out
    }

    static func resize(_ image: CGImage, to pixels: Int) throws -> CGImage {
        if image.width == pixels && image.height == pixels { return image }
        let ctx = try makeContext(size: pixels)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels)))
        guard let out = ctx.makeImage() else { throw IconPipelineError.contextFailure }
        return out
    }

    private static func makeContext(size: Int) throws -> CGContext {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil,
                                  width: size,
                                  height: size,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw IconPipelineError.contextFailure
        }
        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)
        return ctx
    }

    // MARK: Encoding

    static func pngData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw IconPipelineError.contextFailure
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw IconPipelineError.contextFailure }
        return data as Data
    }

    /// Small decode for gallery tiles — ImageIO scales during decode, so this
    /// never inflates a 1024×1024 PNG into memory just to draw it at 48pt.
    static func thumbnail(at url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw IconPipelineError.encodeFailure(url)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw IconPipelineError.encodeFailure(url) }
    }

    // MARK: iconutil

    static func runIconutil(iconset: URL, output: URL) throws {
        let tool = URL(fileURLWithPath: "/usr/bin/iconutil")
        guard FileManager.default.isExecutableFile(atPath: tool.path) else {
            throw IconPipelineError.iconutilMissing
        }

        let process = Process()
        process.executableURL = tool
        process.arguments = ["-c", "icns", iconset.path, "-o", output.path]

        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()

        try process.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let raw = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw IconPipelineError.iconutilFailed(raw.isEmpty ? "exit code \(process.terminationStatus)" : raw)
        }
    }
}
