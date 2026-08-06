import AppKit
import ImageIO
import UniformTypeIdentifiers

// Turns any photo into a macOS-style app icon: centre-cropped to a square,
// clipped to a rounded square, and inset the way Apple's icon grid expects.
//
//   swift Tools/MakeIcon.swift <source image> <output.iconset directory>

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write("사용법: MakeIcon.swift <입력 이미지> <출력 .iconset 폴더>\n".data(using: .utf8)!)
    exit(1)
}

let sourceURL = URL(fileURLWithPath: arguments[1])
let iconsetURL = URL(fileURLWithPath: arguments[2])

guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let original = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    FileHandle.standardError.write("이미지를 읽을 수 없습니다: \(sourceURL.path)\n".data(using: .utf8)!)
    exit(1)
}

// Centre-crop to a square so nothing is squashed.
let side = min(original.width, original.height)
let cropped = original.cropping(to: CGRect(
    x: (original.width - side) / 2,
    y: (original.height - side) / 2,
    width: side,
    height: side
)) ?? original

/// Draws the artwork at `canvas` points, inset and rounded like a macOS icon.
func renderIcon(canvas: Int) -> CGImage? {
    guard let context = CGContext(
        data: nil,
        width: canvas,
        height: canvas,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.interpolationQuality = .high

    // Apple's grid: the rounded square fills roughly 80% of the canvas.
    let size = CGFloat(canvas)
    let inset = (size * 0.1).rounded()
    let box = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = box.width * 0.2237

    context.beginPath()
    context.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    context.draw(cropped, in: box)

    return context.makeImage()
}

try? FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

// (point size, scale) pairs that iconutil expects.
let variants: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                              (256, 1), (256, 2), (512, 1), (512, 2)]

for (points, scale) in variants {
    let pixels = points * scale
    guard let image = renderIcon(canvas: pixels) else { continue }
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    let url = iconsetURL.appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { continue }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print("  \(name)  \(pixels)x\(pixels)")
}

print("원본 \(original.width)x\(original.height) → 정사각 \(side)x\(side) 크롭 후 10개 크기 생성")
