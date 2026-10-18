import AppKit
import CoreGraphics

enum ImageResizer {
    /// Scales the image to an exact pixel width (preserving aspect ratio) and re-encodes as PNG.
    /// Returns nil if the input can't be decoded, in which case callers should fall back to the
    /// original data rather than dropping the paste entirely.
    static func resizedToWidth(_ data: Data, targetWidth: CGFloat) -> Data? {
        guard let sourceRep = NSBitmapImageRep(data: data),
              let sourceCGImage = sourceRep.cgImage else { return nil }

        let originalWidth = CGFloat(sourceRep.pixelsWide)
        let originalHeight = CGFloat(sourceRep.pixelsHigh)
        guard originalWidth > 0, originalHeight > 0 else { return nil }

        let scale = targetWidth / originalWidth
        let targetHeight = (originalHeight * scale).rounded()
        let width = Int(targetWidth)
        let height = Int(targetHeight)
        guard width > 0, height > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(sourceCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let resizedCGImage = context.makeImage() else { return nil }
        let resizedRep = NSBitmapImageRep(cgImage: resizedCGImage)
        return resizedRep.representation(using: .png, properties: [:])
    }
}
