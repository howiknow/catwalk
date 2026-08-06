import AppKit
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Checks the appcast on launch and shows the "새 버전이 있습니다" prompt.
    private let updater = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private var statusItem: NSStatusItem!
    private var cats: [Cat] = []
    private let surfaces = Surfaces()
    private var ticker: Timer?
    private var lastTick = Date.timeIntervalSinceReferenceDate

    private var chaseCursor = UserDefaults.standard.object(forKey: "chaseCursor") as? Bool ?? true
    private var rideWindows = UserDefaults.standard.object(forKey: "rideWindows") as? Bool ?? true

    private let chaseItem = NSMenuItem(title: "커서 따라다니기", action: #selector(toggleChase), keyEquivalent: "")
    private let rideItem = NSMenuItem(title: "창 위에 올라타기", action: #selector(toggleRide), keyEquivalent: "")
    private let countItem = NSMenuItem(title: "고양이 0마리", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        surfaces.ridesWindows = rideWindows
        buildStatusItem()
        startTicking()

        if CatLibrary.shared.isEmpty {
            downloadCats(thenSpawn: 1)
        } else {
            let restored = UserDefaults.standard.object(forKey: "catCount") as? Int ?? 1
            for _ in 0..<max(restored, 1) { addCat() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        UserDefaults.standard.set(cats.count, forKey: "catCount")
    }

    // MARK: - Menu

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let icon = NSImage(systemSymbolName: "cat", accessibilityDescription: "예나캣") {
            statusItem.button?.image = icon
        } else {
            statusItem.button?.title = "🐱"
        }

        let menu = NSMenu()
        countItem.isEnabled = false
        menu.addItem(countItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "고양이 추가", action: #selector(addCatFromMenu), keyEquivalent: "n")
        menu.addItem(withTitle: "한 마리 내보내기", action: #selector(removeCat), keyEquivalent: "w")
        menu.addItem(withTitle: "전부 내보내기", action: #selector(removeAllCats), keyEquivalent: "")
        menu.addItem(withTitle: "다른 고양이로 바꾸기", action: #selector(rerollCats), keyEquivalent: "r")
        menu.addItem(withTitle: "고정 전부 풀기", action: #selector(unpinCats), keyEquivalent: "u")
        menu.addItem(.separator())
        menu.addItem(chaseItem)
        menu.addItem(rideItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "고양이 GIF 더 받기…", action: #selector(downloadMore), keyEquivalent: "")
        menu.addItem(withTitle: "GIF 폴더 열기", action: #selector(openFolder), keyEquivalent: "")
        menu.addItem(.separator())
        let updateItem = NSMenuItem(title: "업데이트 확인…",
                                    action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                                    keyEquivalent: "")
        updateItem.target = updater
        menu.addItem(updateItem)
        menu.addItem(withTitle: "종료", action: #selector(quit), keyEquivalent: "q")

        // The update item already points at Sparkle's controller; leave it alone.
        for item in menu.items where item.action != nil && item.target == nil {
            item.target = self
        }
        chaseItem.state = chaseCursor ? .on : .off
        rideItem.state = rideWindows ? .on : .off
        statusItem.menu = menu
        refreshCount()
    }

    private func refreshCount() {
        countItem.title = "고양이 \(cats.count)마리"
    }

    // MARK: - Actions

    @objc private func addCatFromMenu() {
        guard !CatLibrary.shared.isEmpty else {
            downloadCats(thenSpawn: 1)
            return
        }
        addCat()
    }

    private func addCat() {
        guard let picked = CatLibrary.shared.randomGIF() else { return }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let start = CGPoint(
            x: CGFloat.random(in: screen.frame.minX + 60...max(screen.frame.maxX - 220, screen.frame.minX + 61)),
            y: screen.visibleFrame.maxY - 40
        )
        let cat = Cat(gif: picked.gif, url: picked.url, at: start)
        cat.onDismiss = { [weak self] cat in self?.remove(cat) }
        cats.append(cat)
        refreshCount()
    }

    private func remove(_ cat: Cat) {
        guard let index = cats.firstIndex(where: { $0 === cat }) else { return }
        cats.remove(at: index).remove()
        refreshCount()
    }

    @objc private func removeCat() {
        guard let last = cats.popLast() else { return }
        last.remove()
        refreshCount()
    }

    @objc private func removeAllCats() {
        cats.forEach { $0.remove() }
        cats.removeAll()
        refreshCount()
    }

    @objc private func unpinCats() {
        cats.forEach { $0.unpin() }
    }

    /// Swaps in different GIFs when the ones on screen are duds. The cats keep
    /// their positions, so a pinned spot is not lost.
    @objc private func rerollCats() {
        if cats.isEmpty {
            addCat()
        } else {
            cats.forEach { $0.changeSprite() }
        }
    }

    @objc private func toggleChase() {
        chaseCursor.toggle()
        chaseItem.state = chaseCursor ? .on : .off
        UserDefaults.standard.set(chaseCursor, forKey: "chaseCursor")
    }

    @objc private func toggleRide() {
        rideWindows.toggle()
        rideItem.state = rideWindows ? .on : .off
        surfaces.ridesWindows = rideWindows
        UserDefaults.standard.set(rideWindows, forKey: "rideWindows")
    }

    @objc private func downloadMore() {
        downloadCats(thenSpawn: 0)
    }

    @objc private func openFolder() {
        CatLibrary.shared.revealInFinder()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func downloadCats(thenSpawn spawnCount: Int) {
        statusItem.button?.appearsDisabled = true
        CatCrawler.download { [weak self] result in
            guard let self else { return }
            self.statusItem.button?.appearsDisabled = false
            switch result {
            case .success(let saved):
                for _ in 0..<spawnCount { self.addCat() }
                if saved == 0, spawnCount == 0 {
                    self.notify("새로 받을 고양이가 없습니다", "이미 전부 받아두셨어요.")
                }
            case .failure(let error):
                self.notify("다운로드 실패", error.localizedDescription)
            }
        }
    }

    private func notify(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Loop

    private func startTicking() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common keeps the cats moving while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        let now = Date.timeIntervalSinceReferenceDate
        let dt = min(now - lastTick, 1.0 / 20.0)   // clamp so a stall does not teleport cats
        lastTick = now

        surfaces.refreshIfNeeded(now: now)
        for cat in cats {
            cat.update(dt: dt, surfaces: surfaces, chaseCursor: chaseCursor)
        }
    }
}
