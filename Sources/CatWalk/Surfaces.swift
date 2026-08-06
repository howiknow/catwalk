import AppKit

/// A horizontal ledge a cat can stand on: the bottom of a screen, or the top edge of a window.
struct Ledge {
    let y: CGFloat
    let minX: CGFloat
    let maxX: CGFloat

    func covers(_ x: CGFloat) -> Bool { x >= minX && x <= maxX }
}

/// Finds the ledges available right now. Window ledges are refreshed on a timer,
/// because scanning the window list every frame is wasteful.
final class Surfaces {
    private var windowLedges: [Ledge] = []
    private var lastScan: TimeInterval = 0
    private let rescanInterval: TimeInterval = 0.5

    /// When false, only screen floors are used.
    var ridesWindows = true

    func refreshIfNeeded(now: TimeInterval) {
        guard ridesWindows else {
            windowLedges = []
            return
        }
        guard now - lastScan >= rescanInterval else { return }
        lastScan = now
        windowLedges = Surfaces.scanWindowTops()
    }

    /// Highest ledge at or below `feetY` under the given x. Always finds something,
    /// because the screen floor is a ledge too.
    func support(x: CGFloat, feetY: CGFloat, on screen: NSScreen) -> CGFloat {
        let floor = screen.visibleFrame.minY
        var best = floor
        // A little slack so a cat resting exactly on a ledge still sees it.
        let ceiling = feetY + 2

        for ledge in windowLedges where ledge.covers(x) {
            if ledge.y <= ceiling && ledge.y > best {
                best = ledge.y
            }
        }
        return best
    }

    /// The lowest ledge within jumping reach above the cat, if any.
    func ledgeAbove(x: CGFloat, feetY: CGFloat, maxRise: CGFloat) -> Ledge? {
        windowLedges
            .filter { $0.covers(x) && $0.y > feetY + 40 && $0.y <= feetY + maxRise }
            .min { $0.y < $1.y }
    }

    /// True if there is standing ground at this x — used to detect walking off an edge.
    func hasGround(x: CGFloat, feetY: CGFloat, on screen: NSScreen) -> Bool {
        if abs(feetY - screen.visibleFrame.minY) < 2 {
            return x >= screen.frame.minX && x <= screen.frame.maxX
        }
        return windowLedges.contains { ledge in
            ledge.covers(x) && abs(ledge.y - feetY) < 3
        }
    }

    // MARK: - Window scanning

    /// Top edges of ordinary on-screen windows, front to back, with occluded ones dropped.
    /// Uses only window bounds, which needs no Screen Recording permission.
    private static func scanWindowTops() -> [Ledge] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]],
              let mainScreen = NSScreen.screens.first
        else { return [] }

        let flipHeight = mainScreen.frame.height
        let ownPID = ProcessInfo.processInfo.processIdentifier

        var ledges: [Ledge] = []
        var occluders: [CGRect] = []

        for info in infos {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict)
            else { continue }

            // Convert from CoreGraphics (top-left origin, y down) to AppKit screen space.
            let rect = CGRect(
                x: cgRect.minX,
                y: flipHeight - cgRect.maxY,
                width: cgRect.width,
                height: cgRect.height
            )
            guard rect.width >= 120, rect.height >= 60 else { continue }

            // The list is front to back, so anything already seen sits on top of this.
            let topEdge = CGRect(x: rect.minX, y: rect.maxY - 1, width: rect.width, height: 2)
            let hidden = occluders.contains { $0.contains(topEdge) }
            occluders.append(rect)
            guard !hidden else { continue }

            ledges.append(Ledge(y: rect.maxY, minX: rect.minX, maxX: rect.maxX))
        }
        return ledges
    }
}
