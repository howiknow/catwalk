import AppKit

enum CatState {
    case idle
    case walking
    case chasing
    case sleeping
    case falling
    case dragging
    case climbing   // clinging to a screen edge, heading up
    case hanging    // along the top of the screen
    case pinned     // parked where the user dropped it
}

/// One cat: a window, a position, and a small brain telling it what to do next.
final class Cat: NSObject {
    let window: CatWindow

    /// Called when the cat asks to be taken off screen from its own menu.
    var onDismiss: ((Cat) -> Void)?

    private var size: CGSize
    private var gifURL: URL
    private var spriteAspect: CGFloat

    private var resizeStartHeight: CGFloat = 0
    private var resizeStartMouseX: CGFloat = 0
    private var stateBeforeResize = CatState.idle

    private var position: CGPoint          // bottom-left, AppKit screen coordinates
    private var velocity = CGVector.zero
    private var facing: CGFloat = 1
    private var state: CatState = .falling
    private var stateTimer: Double = 0
    private var willStepOffLedges = false
    private var wall: CGFloat = -1          // -1 left edge, +1 right edge
    private var intendsToClimb = false

    private var dragOffset = CGSize.zero

    private let bubble = SpeechBubble()
    private var timeUntilSpeaking = Double.random(in: 4...18)
    private var speechRemaining = 0.0

    private let gravity: CGFloat = -1900
    private let walkSpeed: CGFloat
    private let runSpeed: CGFloat = 210
    private let climbSpeed: CGFloat = 130

    init(gif: GIFAnimation, url: URL, at point: CGPoint) {
        let height = CGFloat.random(in: 95...130).rounded()
        spriteAspect = Cat.aspect(of: gif)
        size = CGSize(width: Cat.fittedWidth(aspect: spriteAspect, height: height), height: height)
        gifURL = url
        walkSpeed = CGFloat.random(in: 45...75)

        position = point
        window = CatWindow(size: size)
        super.init()

        window.catView.show(gif)
        window.setFrameOrigin(position)
        window.orderFrontRegardless()

        window.catView.onDragBegan = { [weak self] in self?.beginDrag() }
        window.catView.onDragMoved = { [weak self] in self?.dragTo($0) }
        window.catView.onDragEnded = { [weak self] in self?.endDrag() }
        window.catView.onDoubleClick = { [weak self] in self?.unpin() }
        window.catView.onPrevious = { [weak self] in self?.stepSprite(-1) }
        window.catView.onNext = { [weak self] in self?.stepSprite(1) }
        window.catView.onResizeBegan = { [weak self] in self?.beginResize() }
        window.catView.onResizeMoved = { [weak self] in self?.resizeTo($0) }
        window.catView.onResizeEnded = { [weak self] in self?.endResize() }
        window.catView.menu = buildMenu()
    }

    static let minHeight: CGFloat = 55
    static let maxHeight: CGFloat = 340

    private static func aspect(of gif: GIFAnimation) -> CGFloat {
        gif.pixelSize.width / max(gif.pixelSize.height, 1)
    }

    /// Width for a given height. Very wide images are reined in, and very narrow
    /// ones get a floor so the hover controls still fit.
    private static func fittedWidth(aspect: CGFloat, height: CGFloat) -> CGFloat {
        max(height * min(aspect, 2.0), 72).rounded()
    }

    func remove() {
        bubble.close()
        window.orderOut(nil)
        window.close()
    }

    // MARK: - Talking

    /// Says something now, for a few seconds.
    func speak(_ line: String) {
        bubble.show(line)
        speechRemaining = Double.random(in: 3.0...4.5)
        bubble.reposition(above: window.frame, on: screen)
    }

    private func updateSpeech(dt: Double, screen: NSScreen) {
        if speechRemaining > 0 {
            speechRemaining -= dt
            if speechRemaining <= 0 {
                bubble.hide()
                timeUntilSpeaking = Double.random(in: 20...60)
            }
        } else {
            timeUntilSpeaking -= dt
            // A sleeping cat has its 💤 already; let it be.
            if timeUntilSpeaking <= 0, state != .sleeping, state != .dragging {
                speak(CatLines.random(from: CatLines.idle))
            }
        }
        bubble.reposition(above: window.frame, on: screen)
    }

    var isPinned: Bool { state == .pinned }

    /// Lets a parked cat fall back to the ground and carry on roaming.
    func unpin() {
        guard state == .pinned else { return }
        state = .falling
        velocity = .zero
    }

    // MARK: - Changing the picture

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "다른 GIF로 바꾸기", action: #selector(changeSprite), keyEquivalent: "")
        menu.addItem(withTitle: "이 GIF 다시 안 보기", action: #selector(banSprite), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "이 고양이 없애기", action: #selector(dismissSelf), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        return menu
    }

    /// Swaps the picture without moving the cat, so a pinned spot survives.
    @objc func changeSprite() {
        guard let picked = CatLibrary.shared.randomGIF() else { return }
        adopt(picked)
    }

    /// Steps through the library in order — what the hover arrows drive.
    func stepSprite(_ offset: Int) {
        guard let picked = CatLibrary.shared.neighbour(of: gifURL, offset: offset) else { return }
        adopt(picked)
    }

    private func adopt(_ picked: (url: URL, gif: GIFAnimation)) {
        gifURL = picked.url
        spriteAspect = Cat.aspect(of: picked.gif)
        // Keep this cat's height so browsing the library does not resize it every step.
        applyHeight(size.height)
        window.catView.show(picked.gif)
    }

    /// Resizes around the feet and the horizontal centre, so the cat stays put.
    private func applyHeight(_ height: CGFloat) {
        let clamped = min(max(height, Cat.minHeight), Cat.maxHeight).rounded()
        let newSize = CGSize(width: Cat.fittedWidth(aspect: spriteAspect, height: clamped),
                             height: clamped)
        position.x += (size.width - newSize.width) / 2
        size = newSize

        window.setContentSize(newSize)
        window.catView.needsLayout = true
        applyToWindow()
    }

    // MARK: - Resizing

    private func beginResize() {
        resizeStartHeight = size.height
        resizeStartMouseX = NSEvent.mouseLocation.x
        stateBeforeResize = (state == .dragging) ? .idle : state
        state = .dragging
        window.catView.setAsleep(false)
    }

    /// Dragging the corner handle right grows the cat, left shrinks it.
    private func resizeTo(_ mouse: NSPoint) {
        let startWidth = Cat.fittedWidth(aspect: spriteAspect, height: resizeStartHeight)
        let scale = max((startWidth + (mouse.x - resizeStartMouseX)) / startWidth, 0.1)
        applyHeight(resizeStartHeight * scale)
    }

    private func endResize() {
        state = stateBeforeResize
        keepOnScreen()
        applyToWindow()
    }

    @objc private func banSprite() {
        CatLibrary.shared.delete(gifURL)
        changeSprite()
    }

    @objc private func dismissSelf() {
        onDismiss?(self)
    }

    private var centerX: CGFloat { position.x + size.width / 2 }

    private var screen: NSScreen {
        let probe = CGPoint(x: centerX, y: position.y + 1)
        return NSScreen.screens.first { $0.frame.contains(probe) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: - Simulation

    func update(dt: Double, surfaces: Surfaces, chaseCursor: Bool) {
        let screen = self.screen
        // Driven from the tick rather than a tracking area, because the cat walks out
        // from under a stationary pointer and tracking areas miss that.
        window.catView.setArrowsVisible(state != .dragging && window.frame.contains(NSEvent.mouseLocation))
        // Ahead of the switch below, so a pinned cat still chats.
        updateSpeech(dt: dt, screen: screen)

        switch state {
        case .dragging, .pinned:
            return
        case .climbing:
            climb(dt: dt, screen: screen)
        case .hanging:
            hang(dt: dt, screen: screen)
        default:
            let ground = surfaces.support(x: centerX, feetY: position.y, on: screen)

            if position.y > ground + 1 {
                if state != .falling {
                    state = .falling
                    velocity.dy = 0
                }
            } else if state != .falling {
                // Stay glued to the ledge, which may have shifted since the last frame.
                position.y = ground
            }

            switch state {
            case .falling:
                fall(dt: dt, ground: ground)
            case .idle, .sleeping:
                stateTimer -= dt
                if stateTimer <= 0 { pickGroundState(surfaces: surfaces, screen: screen, chaseCursor: chaseCursor) }
            case .walking:
                walk(dt: dt, speed: walkSpeed, surfaces: surfaces, screen: screen)
                // walk() may have handed off to climbing; only age a still-walking cat.
                if state == .walking {
                    stateTimer -= dt
                    if stateTimer <= 0 { pickGroundState(surfaces: surfaces, screen: screen, chaseCursor: chaseCursor) }
                }
            case .chasing:
                chase(dt: dt, surfaces: surfaces, screen: screen, chaseCursor: chaseCursor)
            default:
                break
            }
        }

        applyToWindow()
    }

    private func fall(dt: Double, ground: CGFloat) {
        velocity.dy += gravity * CGFloat(dt)
        position.y += velocity.dy * CGFloat(dt)
        position.x += velocity.dx * CGFloat(dt)
        velocity.dx *= 0.985

        // Only land on the way down, so a jump can pass its take-off height.
        if velocity.dy <= 0, position.y <= ground {
            position.y = ground
            velocity = .zero
            state = .idle
            stateTimer = Double.random(in: 0.6...1.6)
            window.catView.setAsleep(false)
        }
        clampHorizontally()
    }

    // MARK: - Walls and ceiling

    private func startClimbing(wall: CGFloat, screen: NSScreen) {
        self.wall = wall
        intendsToClimb = false
        state = .climbing
        position.x = wall < 0 ? screen.frame.minX : screen.frame.maxX - size.width
        velocity = .zero
        facing = wall

        // Budget enough time to actually reach the top, but sometimes give up partway.
        let toCeiling = (screen.visibleFrame.maxY - size.height - position.y) / climbSpeed
        stateTimer = Double(toCeiling) * Double.random(in: 0.55...1.3)
    }

    /// Sets off on a long walk to the nearest screen edge, intending to climb it.
    private func headToWall(screen: NSScreen) {
        let bounds = screen.frame
        let toLeft = position.x - bounds.minX
        let toRight = bounds.maxX - (position.x + size.width)

        facing = toLeft < toRight ? -1 : 1
        intendsToClimb = true
        willStepOffLedges = false
        state = .walking
        stateTimer = Double(min(toLeft, toRight) / walkSpeed) + 1.5
    }

    private func climb(dt: Double, screen: NSScreen) {
        stateTimer -= dt
        position.y += climbSpeed * CGFloat(dt)
        position.x = wall < 0 ? screen.frame.minX : screen.frame.maxX - size.width

        let ceiling = screen.visibleFrame.maxY - size.height
        if position.y >= ceiling {
            position.y = ceiling
            state = .hanging
            stateTimer = Double.random(in: 3...9)
            facing = -wall
            return
        }
        if stateTimer <= 0 { letGo() }
    }

    private func hang(dt: Double, screen: NSScreen) {
        stateTimer -= dt
        position.y = screen.visibleFrame.maxY - size.height

        let step = facing * walkSpeed * CGFloat(dt)
        let nextX = position.x + step
        if nextX < screen.frame.minX || nextX + size.width > screen.frame.maxX {
            turnAround()
        } else {
            position.x = nextX
        }
        if stateTimer <= 0 { letGo() }
    }

    private func letGo() {
        state = .falling
        velocity = .zero
    }

    private func walk(dt: Double, speed: CGFloat, surfaces: Surfaces, screen: NSScreen) {
        let step = facing * speed * CGFloat(dt)
        let nextX = position.x + step
        let nextCenter = centerX + step
        let bounds = screen.frame

        // Keep the whole cat on screen rather than letting it hang off the edge.
        if nextX < bounds.minX || nextX + size.width > bounds.maxX {
            if intendsToClimb || Double.random(in: 0..<1) < 0.4 {
                startClimbing(wall: nextX < bounds.minX ? -1 : 1, screen: screen)
            } else {
                turnAround()
            }
            return
        }
        if !surfaces.hasGround(x: nextCenter, feetY: position.y, on: screen) {
            if willStepOffLedges {
                state = .falling
                velocity = CGVector(dx: facing * speed, dy: 0)
            } else {
                turnAround()
            }
            return
        }
        position.x += step
    }

    private func chase(dt: Double, surfaces: Surfaces, screen: NSScreen, chaseCursor: Bool) {
        stateTimer -= dt
        let targetX = NSEvent.mouseLocation.x
        let distance = targetX - centerX

        if !chaseCursor || stateTimer <= 0 || abs(distance) < 30 {
            state = .idle
            stateTimer = Double.random(in: 0.8...2.0)
            return
        }
        facing = distance > 0 ? 1 : -1
        walk(dt: dt, speed: runSpeed, surfaces: surfaces, screen: screen)
    }

    private func turnAround() {
        facing *= -1
    }

    /// Decides what a cat standing on solid ground does next.
    private func pickGroundState(surfaces: Surfaces, screen: NSScreen, chaseCursor: Bool) {
        window.catView.setAsleep(false)
        intendsToClimb = false
        let roll = Double.random(in: 0..<1)

        // Rolled separately so a reachable ledge does not crowd out the other choices.
        if Double.random(in: 0..<1) < 0.35,
           let target = surfaces.ledgeAbove(x: centerX, feetY: position.y, maxRise: 280) {
            jump(to: target)
            return
        }
        if roll < 0.25 {
            headToWall(screen: screen)
            return
        }
        if chaseCursor, roll < 0.38 {
            state = .chasing
            stateTimer = Double.random(in: 2.0...5.0)
            return
        }
        if roll < 0.52 {
            state = .sleeping
            stateTimer = Double.random(in: 6...16)
            window.catView.setAsleep(true)
            return
        }
        if roll < 0.68 {
            state = .idle
            stateTimer = Double.random(in: 1.0...3.0)
            return
        }
        state = .walking
        stateTimer = Double.random(in: 1.5...4.0)
        willStepOffLedges = Double.random(in: 0..<1) < 0.25
        facing = Bool.random() ? 1 : -1
    }

    /// Hops straight up with just enough speed to clear the ledge.
    private func jump(to ledge: Ledge) {
        let rise = ledge.y - position.y + 30
        state = .falling
        velocity = CGVector(dx: 0, dy: (2 * -gravity * rise).squareRoot())
        window.catView.setAsleep(false)
    }

    private func clampHorizontally() {
        guard let union = NSScreen.screens.map(\.frame).reduce(nil, unionOptional) else { return }
        position.x = min(max(position.x, union.minX), union.maxX - size.width)
    }

    private func applyToWindow() {
        window.setFrameOrigin(CGPoint(x: position.x.rounded(), y: position.y.rounded()))
    }

    // MARK: - Dragging

    private func beginDrag() {
        state = .dragging
        velocity = .zero
        window.catView.setAsleep(false)
        let mouse = NSEvent.mouseLocation
        dragOffset = CGSize(width: mouse.x - position.x, height: mouse.y - position.y)
    }

    private func dragTo(_ mouse: NSPoint) {
        position = CGPoint(x: mouse.x - dragOffset.width, y: mouse.y - dragOffset.height)
        applyToWindow()
    }

    /// Dropping a cat parks it exactly where it was left. Double-click to release it.
    private func endDrag() {
        state = .pinned
        velocity = .zero
        keepOnScreen()
        applyToWindow()
        // Only now and then: speaking on every single drop gets repetitive fast.
        if Double.random(in: 0..<1) < 0.3 {
            speak(CatLines.random(from: CatLines.pinned))
        }
    }

    /// A pinned cat never falls, so a drop past the edge would strand it out of reach.
    private func keepOnScreen() {
        guard let union = NSScreen.screens.map(\.frame).reduce(nil, unionOptional) else { return }
        let visible: CGFloat = 40
        position.x = min(max(position.x, union.minX - size.width + visible), union.maxX - visible)
        position.y = min(max(position.y, union.minY - size.height + visible), union.maxY - visible)
    }
}

private func unionOptional(_ lhs: CGRect?, _ rhs: CGRect) -> CGRect? {
    guard let lhs else { return rhs }
    return lhs.union(rhs)
}
