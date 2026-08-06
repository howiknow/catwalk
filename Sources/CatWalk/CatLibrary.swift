import AppKit

/// Where downloaded cat GIFs live, and how they get decoded.
/// Drop your own .gif files into this folder and they show up too.
final class CatLibrary {
    static let shared = CatLibrary()

    let directory: URL
    private var cache: [URL: GIFAnimation] = [:]

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("CatWalk/cats", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var files: [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.filter { ["gif", "png"].contains($0.pathExtension.lowercased()) }
    }

    var isEmpty: Bool { files.isEmpty }

    func randomGIF() -> (url: URL, gif: GIFAnimation)? {
        guard let url = files.randomElement() else { return nil }
        if let cached = cache[url] { return (url, cached) }
        guard let gif = GIFAnimation.load(from: url) else { return nil }
        cache[url] = gif
        return (url, gif)
    }

    /// The GIF `offset` places along from `url` in alphabetical order, wrapping around.
    func neighbour(of url: URL, offset: Int) -> (url: URL, gif: GIFAnimation)? {
        let ordered = files.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !ordered.isEmpty else { return nil }

        let current = ordered.firstIndex(of: url) ?? 0
        let count = ordered.count
        let target = ordered[((current + offset) % count + count) % count]

        if let cached = cache[target] { return (target, cached) }
        guard let gif = GIFAnimation.load(from: target) else { return nil }
        cache[target] = gif
        return (target, gif)
    }

    /// Drops a GIF the user does not want to see again.
    func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        cache[url] = nil
    }

    func forgetCache() { cache.removeAll() }

    func revealInFinder() {
        NSWorkspace.shared.open(directory)
    }
}
