import AppKit
import ImageIO
import UniformTypeIdentifiers
import Vision

// Cuts the subject out of every frame of an animated image and writes the result
// as an APNG, which keeps soft edges (GIF only has on/off transparency).
//
//   swift Tools/RemoveBackground.swift <input dir> <output dir> [limit]

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write("사용법: RemoveBackground.swift <입력 폴더> <출력 폴더> [개수]\n".data(using: .utf8)!)
    exit(1)
}

let inputDirectory = URL(fileURLWithPath: arguments[1])
let outputDirectory = URL(fileURLWithPath: arguments[2])
let limit = arguments.count > 3 ? Int(arguments[3]) ?? Int.max : Int.max

try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let context = CIContext()

/// Runs subject lifting on one frame. Returns nil when Vision finds no subject.
func liftSubject(from image: CGImage) -> CGImage? {
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
    return context.createCGImage(ciImage, from: ciImage.extent)
}

/// Bounding box of the non-transparent pixels, or nil when the frame is empty.
func opaqueBounds(of image: CGImage) -> CGRect? {
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
    // Bitmap rows run top-down, and CGImage.cropping uses the same top-left origin.
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

/// Frame images plus their durations, for either GIF or APNG input.
func readFrames(_ url: URL) -> (frames: [CGImage], delays: [Double])? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
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

func writeAPNG(frames: [CGImage], delays: [Double], to url: URL) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, frames.count, nil
    ) else { return false }

    CGImageDestinationSetProperties(destination, [
        kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]
    ] as CFDictionary)

    for (frame, delay) in zip(frames, delays) {
        CGImageDestinationAddImage(destination, frame, [
            kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: delay]
        ] as CFDictionary)
    }
    return CGImageDestinationFinalize(destination)
}

let files = ((try? FileManager.default.contentsOfDirectory(
    at: inputDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
)) ?? [])
    .filter { ["gif", "png"].contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
    .prefix(limit)

var succeeded = 0, skipped = 0

for file in files {
    guard let (frames, delays) = readFrames(file) else {
        print("읽기 실패: \(file.lastPathComponent)")
        skipped += 1
        continue
    }

    var cut: [CGImage] = []
    var keptDelays: [Double] = []
    for (frame, delay) in zip(frames, delays) {
        guard let lifted = liftSubject(from: frame) else { continue }
        cut.append(lifted)
        keptDelays.append(delay)
    }

    // Trim the transparent margin, using one box for every frame so the
    // animation does not jitter. Without this the cat keeps the photo's
    // dimensions and ends up tiny once scaled to sprite size.
    var union: CGRect?
    for frame in cut {
        guard let box = opaqueBounds(of: frame) else { continue }
        union = union.map { $0.union(box) } ?? box
    }
    if let box = union, let first = cut.first {
        let canvas = CGRect(x: 0, y: 0, width: first.width, height: first.height)
        let padded = box.insetBy(dx: -2, dy: -2).intersection(canvas)
        cut = cut.compactMap { $0.cropping(to: padded) }
    }

    // A frame or two can miss; losing most of them means Vision found no cat.
    guard cut.count >= max(1, frames.count / 2) else {
        print("피사체 인식 실패 (\(cut.count)/\(frames.count) 프레임): \(file.lastPathComponent)")
        skipped += 1
        continue
    }

    let output = outputDirectory.appendingPathComponent(
        file.deletingPathExtension().lastPathComponent + ".png"
    )
    if writeAPNG(frames: cut, delays: keptDelays, to: output) {
        succeeded += 1
        print("완료 \(succeeded): \(file.lastPathComponent) — \(cut.count)/\(frames.count) 프레임")
    } else {
        skipped += 1
        print("쓰기 실패: \(file.lastPathComponent)")
    }
}

print("\n성공 \(succeeded)개 / 실패·제외 \(skipped)개 / 전체 \(files.count)개")
