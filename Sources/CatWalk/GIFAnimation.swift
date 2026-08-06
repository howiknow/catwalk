import AppKit
import ImageIO

/// A decoded GIF: the frames plus how long each one is shown.
struct GIFAnimation {
    let frames: [CGImage]
    let delays: [Double]
    let pixelSize: CGSize

    var duration: Double { max(delays.reduce(0, +), 0.05) }

    static func load(from url: URL) -> GIFAnimation? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        var frames: [CGImage] = []
        var delays: [Double] = []
        for index in 0..<count {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(frame)
            delays.append(delay(of: source, at: index))
        }
        guard let first = frames.first else { return nil }
        return GIFAnimation(
            frames: frames,
            delays: delays,
            pixelSize: CGSize(width: first.width, height: first.height)
        )
    }

    /// Frame duration for either a GIF or an APNG, whose timings live in
    /// different property dictionaries.
    private static func delay(of source: CGImageSource, at index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        else { return 0.1 }

        var raw: Double?
        if let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            raw = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif[kCGImagePropertyGIFDelayTime] as? Double)
        } else if let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any] {
            raw = (png[kCGImagePropertyAPNGUnclampedDelayTime] as? Double)
                ?? (png[kCGImagePropertyAPNGDelayTime] as? Double)
        }

        // Browsers treat sub-20ms delays as "as fast as possible"; match that.
        guard let raw, raw >= 0.02 else { return 0.1 }
        return raw
    }

    /// Layer animation that cycles the frames forever.
    func keyframeAnimation() -> CAKeyframeAnimation? {
        guard frames.count > 1 else { return nil }
        let total = duration
        var keyTimes: [NSNumber] = [0]
        var elapsed = 0.0
        for delay in delays {
            elapsed += delay
            keyTimes.append(NSNumber(value: elapsed / total))
        }

        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.keyTimes = keyTimes
        animation.calculationMode = .discrete
        animation.duration = total
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        return animation
    }
}
