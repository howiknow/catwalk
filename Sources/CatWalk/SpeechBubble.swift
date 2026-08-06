import AppKit

/// What the cats say. Short lines read better in a small bubble.
enum CatLines {
    static let idle = [
        // 고양이다운 것
        "냐옹", "야옹~", "그르릉", "밥 줘", "간식은?", "놀아줘",
        "쓰다듬어", "여기 내 자리", "심심해", "졸려…", "왜 불러",
        "지금 바빠", "그거 내 거", "집사야",

        // 챙겨주는 말
        "아프지 마", "약 챙겨 먹어", "밥은 먹었어?", "물 좀 마셔",
        "무리하지 마", "잠 좀 자", "너무 애쓰지 마", "천천히 해도 돼",
        "눈 좀 쉬어", "허리 좀 펴", "따뜻하게 입어", "잘하고 있어",
        "오늘도 고생 많았어", "괜찮아, 다 잘될 거야", "숨 한 번 쉬고",
        "잠깐 쉬었다 해", "커피 그만 마셔", "퇴근 안 해?",
        "손 씻었어?", "스트레칭 한 번",
    ]

    static let pinned = [
        "여기 좋다", "자리 잡았다", "여기서 살래", "안 움직일 거야",
        "명당이네", "여기 찜", "딱 좋아", "여기 있을게",
        "고마워", "안녕", "응?", "뭐야",
    ]

    static func random(from lines: [String]) -> String {
        lines.randomElement() ?? "냐옹"
    }
}

/// Draws a rounded speech bubble with a tail pointing down at the cat.
private final class BubbleView: NSView {
    static let horizontalPadding: CGFloat = 11
    static let verticalPadding: CGFloat = 7
    static let tailHeight: CGFloat = 7
    static let cornerRadius: CGFloat = 11
    static let maximumTextWidth: CGFloat = 170

    var text = "" {
        didSet { needsDisplay = true }
    }

    static var textAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        return [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
    }

    /// Window size needed to hold `text`, tail included.
    static func size(for text: String) -> CGSize {
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: maximumTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: textAttributes
        )
        return CGSize(
            width: (bounds.width + horizontalPadding * 2).rounded(.up),
            height: (bounds.height + verticalPadding * 2 + tailHeight).rounded(.up)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        let body = NSRect(
            x: 0,
            y: BubbleView.tailHeight,
            width: bounds.width,
            height: bounds.height - BubbleView.tailHeight
        )

        let path = NSBezierPath(roundedRect: body,
                                xRadius: BubbleView.cornerRadius,
                                yRadius: BubbleView.cornerRadius)
        // Tail, pointing down towards the cat.
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: bounds.midX - 6, y: body.minY + 0.5))
        tail.line(to: NSPoint(x: bounds.midX, y: 0))
        tail.line(to: NSPoint(x: bounds.midX + 6, y: body.minY + 0.5))
        tail.close()
        path.append(tail)

        NSColor.textBackgroundColor.withAlphaComponent(0.96).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let textRect = body.insetBy(dx: BubbleView.horizontalPadding, dy: BubbleView.verticalPadding)
        (text as NSString).draw(with: textRect,
                                options: [.usesLineFragmentOrigin, .usesFontLeading],
                                attributes: BubbleView.textAttributes)
    }
}

/// A click-through panel that floats a line of dialogue above one cat.
final class SpeechBubble {
    private let panel: NSPanel
    private let view = BubbleView()
    private var size = CGSize.zero
    private var shown = false

    var isVisible: Bool { shown }

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // The bubble must never swallow clicks meant for the cat underneath.
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = view
    }

    func show(_ line: String) {
        size = BubbleView.size(for: line)
        view.text = line
        panel.setContentSize(size)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        shown = true
    }

    /// An accessory app's floating panel can survive `orderOut` on screen, so the
    /// alpha is what actually takes the bubble away.
    func hide() {
        guard shown else { return }
        shown = false
        panel.alphaValue = 0
        panel.orderOut(nil)
    }

    func close() {
        shown = false
        panel.alphaValue = 0
        panel.orderOut(nil)
        panel.close()
    }

    /// Centres the bubble just above `catFrame`, kept inside the screen.
    func reposition(above catFrame: CGRect, on screen: NSScreen) {
        guard shown else { return }
        let bounds = screen.visibleFrame
        let x = min(max(catFrame.midX - size.width / 2, bounds.minX + 4), bounds.maxX - size.width - 4)
        let y = min(catFrame.maxY + 3, bounds.maxY - size.height)
        panel.setFrameOrigin(CGPoint(x: x.rounded(), y: y.rounded()))
    }
}
