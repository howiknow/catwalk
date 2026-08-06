import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Cuts the cat out of a downloaded animation so it walks around without a
/// rectangle behind it. Runs entirely on device via Vision's subject lifting.
///
/// The result is an APNG: GIF can only store on/off transparency, which leaves
/// jagged edges once the sprite is composited over the desktop.
enum BackgroundRemover {
    /// True when this macOS can lift subjects at all.
    static var isAvailable: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    /// Returns APNG data with the background removed, or nil if no subject was
    /// found — callers should then keep the original image.
    static func cutout(from data: Data) -> Data? {
        guard #available(macOS 14.0, *) else { return nil }
        guard let (frames, delays) = decode(data) else { return nil }

        var lifted: [CGImage] = []
        var keptDelays: [Double] = []
        for (frame, delay) in zip(frames, delays) {
            guard let subject = liftSubject(from: frame) else { continue }
            lifted.append(subject)
            keptDelays.append(delay)
        }
        // Losing most frames means Vision never really found the cat.
        guard lifted.count >= max(1, frames.count / 2) else { return nil }

        trimTransparentMargin(&lifted)
        return encodeAPNG(frames: lifted, delays: keptDelays)
    }

    // MARK: - Steps

    @available(macOS 14.0, *)
    private static func liftSubject(from image: CGImage) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              !observation.allInstances.isEmpty,
              let buffer = try? observation.generateMaskedImage(
                  ofInstances: observation.allInstances,
                  from: handler,
                  croppedToInstancesExtent: false
              )
        else { return nil }

        let ciImage = CIImage(cvPixelBuffer: buffer)
        return CIContext().createCGImage(ciImage, from: ciImage.extent)
    }

    /// Crops every frame to one shared box, so the cat fills the sprite without
    /// the animation jittering.
    private static func trimTransparentMargin(_ frames: inout [CGImage]) {
        var union: CGRect?
        for frame in frames {
            guard let box = opaqueBounds(of: frame) else { continue }
            union = union.map { $0.union(box) } ?? box
        }
        guard let box = union, let first = frames.first else { return }
        let canvas = CGRect(x: 0, y: 0, width: first.width, height: first.height)
        let padded = box.insetBy(dx: -2, dy: -2).intersection(canvas)
        let cropped = frames.compactMap { $0.cropping(to: padded) }
        if cropped.count == frames.count { frames = cropped }
    }

    private static func opaqueBounds(of image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let bitmap = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // Bitmap rows run top-down, matching CGImage.cropping's origin.
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    // MARK: - Image IO

    private static func decode(_ data: Data) -> (frames: [CGImage], delays: [Double])? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        var frames: [CGImage] = []
        var delays: [Double] = []
        for index in 0..<count {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(frame)

            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let raw = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double)
                ?? 0.1
            delays.append(raw < 0.02 ? 0.1 : raw)
        }
        return frames.isEmpty ? nil : (frames, delays)
    }

    private static func encodeAPNG(frames: [CGImage], delays: [Double]) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, frames.count, nil
        ) else { return nil }

        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]
        ] as CFDictionary)

        for (frame, delay) in zip(frames, delays) {
            CGImageDestinationAddImage(destination, frame, [
                kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: delay]
            ] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
