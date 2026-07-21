import CoreGraphics
import Foundation

/// Minimal Windows .ico writer.
///
/// Every entry is stored as a PNG blob, which Windows has accepted since Vista
/// and which keeps the alpha channel intact — no BMP/AND-mask juggling.
enum ICOWriter {

    /// Sizes packed into the .ico, largest last.
    static let sizes = [16, 24, 32, 48, 64, 128, 256]

    static func write(from image: CGImage, to url: URL) throws {
        var blobs: [Data] = []
        for size in sizes {
            blobs.append(try IconPipeline.pngData(try IconPipeline.resize(image, to: size)))
        }

        var out = Data()
        out.append(uint16(0))                    // reserved
        out.append(uint16(1))                    // type: 1 = icon
        out.append(uint16(UInt16(blobs.count)))  // image count

        // Directory entries come first, so the payload starts after all of them.
        var offset = 6 + 16 * blobs.count
        for (size, blob) in zip(sizes, blobs) {
            // 256 is stored as 0 — the field is a single byte.
            out.append(UInt8(size == 256 ? 0 : size))  // width
            out.append(UInt8(size == 256 ? 0 : size))  // height
            out.append(UInt8(0))                       // palette size (0 = truecolour)
            out.append(UInt8(0))                       // reserved
            out.append(uint16(1))                      // colour planes
            out.append(uint16(32))                     // bits per pixel
            out.append(uint32(UInt32(blob.count)))     // byte length of the blob
            out.append(uint32(UInt32(offset)))         // byte offset of the blob
            offset += blob.count
        }

        for blob in blobs { out.append(blob) }
        try out.write(to: url)
    }

    private static func uint16(_ value: UInt16) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func uint32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
