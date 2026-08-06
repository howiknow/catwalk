import AppKit

/// The view that actually draws the cat and reports drags.
final class CatView: NSView {
    var onDragBegan: (() -> Void)?
    var onDragMoved: ((NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onResizeBegan: (() -> Void)?
    var onResizeMoved: ((NSPoint) -> Void)?
    var onResizeEnded: (() -> Void)?

    /// What the current mouse-down grabbed, so the drag goes to the right handler.
    private enum Grab {
        case none
        case body
        case resize
    }

    private var grab = Grab.none

    private let spriteLayer = CALayer()
    private let sleepLayer = CATextLayer()

    /// Controls shrink with the cat so the side arrows never collide with the
    /// corner handle. Staying under a third of the height guarantees the gap.
    private var controlSize: CGFloat { max(14, min(26, bounds.height * 0.24)) }

    private let leftArrow = CALayer()
    private let rightArrow = CALayer()
    private let leftGlyph = CATextLayer()
    private let rightGlyph = CATextLayer()
    private let resizeHandle = CALayer()
    private let resizeGlyph = CALayer()
    private var arrowsVisible = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        spriteLayer.contentsGravity = .resizeAspect
        spriteLayer.magnificationFilter = .trilinear
        layer?.addSublayer(spriteLayer)

        sleepLayer.string = "💤"
        sleepLayer.fontSize = 18
        sleepLayer.alignmentMode = .center
        sleepLayer.contentsScale = 2
        sleepLayer.isHidden = true
        layer?.addSublayer(sleepLayer)

        for (badge, glyph, symbol) in [(leftArrow, leftGlyph, "‹"), (rightArrow, rightGlyph, "›")] {
            badge.backgroundColor = NSColor(white: 0, alpha: 0.6).cgColor
            badge.isHidden = true
            glyph.string = symbol
            glyph.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
            glyph.alignmentMode = .center
            glyph.foregroundColor = NSColor.white.cgColor
            glyph.contentsScale = 2
            badge.addSublayer(glyph)
            layer?.addSublayer(badge)
        }

        resizeHandle.backgroundColor = NSColor(white: 0, alpha: 0.6).cgColor
        resizeHandle.isHidden = true
        resizeGlyph.contents = CatView.resizeIcon()
        resizeGlyph.contentsGravity = .resizeAspect
        resizeHandle.addSublayer(resizeGlyph)
        layer?.addSublayer(resizeHandle)
    }

    /// White diagonal double-arrow, drawn once and reused by every cat.
    private static func resizeIcon() -> CGImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right",
                                   accessibilityDescription: "크기 조절")?
            .withSymbolConfiguration(config)
        else { return nil }

        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        var box = CGRect(origin: .zero, size: tinted.size)
        return tinted.cgImage(forProposedRect: &box, context: nil, hints: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        withoutAnimation {
            spriteLayer.frame = bounds
            sleepLayer.frame = CGRect(x: bounds.maxX - 26, y: bounds.maxY - 4, width: 30, height: 24)

            let side = controlSize
            let y = bounds.midY - side / 2
            leftArrow.frame = CGRect(x: 2, y: y, width: side, height: side)
            rightArrow.frame = CGRect(x: bounds.maxX - side - 2, y: y, width: side, height: side)
            resizeHandle.frame = CGRect(x: bounds.maxX - side - 2, y: 2, width: side, height: side)
            [leftArrow, rightArrow, resizeHandle].forEach { $0.cornerRadius = side / 2 }

            // CATextLayer draws from the top of its box, so shrink it to centre the glyph.
            let fontSize = (side * 0.66).rounded()
            let glyphBox = CGRect(x: 0, y: (side - fontSize * 1.18) / 2, width: side, height: fontSize * 1.18)
            for glyph in [leftGlyph, rightGlyph] {
                glyph.fontSize = fontSize
                glyph.frame = glyphBox
            }
            let inset = (side * 0.19).rounded()
            resizeGlyph.frame = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
        }
    }

    /// Shown while the pointer is over the cat, for flipping through the library.
    func setArrowsVisible(_ visible: Bool) {
        guard visible != arrowsVisible else { return }
        arrowsVisible = visible
        withoutAnimation {
            leftArrow.isHidden = !visible
            rightArrow.isHidden = !visible
            resizeHandle.isHidden = !visible
        }
    }

    func show(_ gif: GIFAnimation) {
        withoutAnimation {
            spriteLayer.removeAnimation(forKey: "frames")
            spriteLayer.contents = gif.frames.first
            if let animation = gif.keyframeAnimation() {
                spriteLayer.add(animation, forKey: "frames")
            }
        }
    }

    // The sprites are photographs, not sprite-sheet art: mirroring them to match the
    // walking direction reverses any text in the image, and rotating them for the
    // ceiling just looks like a bug. So the cat is always drawn the right way up.

    func setAsleep(_ asleep: Bool) {
        withoutAnimation {
            sleepLayer.isHidden = !asleep
            spriteLayer.opacity = asleep ? 0.75 : 1.0
        }
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    // MARK: - Mouse

    // Let a click land on the cat without first activating our app.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if arrowsVisible {
            let point = convert(event.locationInWindow, from: nil)
            // Slightly generous targets: on a small cat these badges shrink to 14pt.
            func hits(_ control: CALayer) -> Bool {
                control.frame.insetBy(dx: -4, dy: -4).contains(point)
            }
            // Handle first — it sits nearest the right arrow once the areas are grown.
            if hits(resizeHandle) {
                grab = .resize
                onResizeBegan?()
                return
            }
            if hits(leftArrow) { onPrevious?(); return }
            if hits(rightArrow) { onNext?(); return }
        }
        if event.clickCount == 2 {
            grab = .none
            onDoubleClick?()
            return
        }
        grab = .body
        onDragBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        switch grab {
        case .body: onDragMoved?(NSEvent.mouseLocation)
        case .resize: onResizeMoved?(NSEvent.mouseLocation)
        case .none: break
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch grab {
        case .body: onDragEnded?()
        case .resize: onResizeEnded?()
        case .none: break
        }
        grab = .none
    }
}

/// A borderless, transparent, always-on-top panel holding one cat.
final class CatWindow: NSPanel {
    let catView: CatView

    init(size: CGSize) {
        catView = CatView(frame: NSRect(origin: .zero, size: size))
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        // The sprites are alpha cut-outs now: a window shadow would trace their
        // outline and go stale on every animation frame.
        hasShadow = false
        level = .floating
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = catView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
