import Foundation

/// Pulls cat GIFs from TheCatAPI into the local library.
/// Keyless public endpoint; images already on disk are skipped.
///
/// These are unedited photographs of actual cats. They come with opaque
/// rectangular backgrounds — the transparent alternative (Giphy stickers) turned
/// out to be mostly meme edits, which is not what this app wants.
enum CatCrawler {
    private struct Entry: Decodable {
        let id: String
        let url: String
    }

    enum CrawlError: LocalizedError {
        case badResponse

        var errorDescription: String? {
            "고양이 목록을 받아오지 못했습니다. 네트워크 상태를 확인해 주세요."
        }
    }

    /// Downloads up to `limit` GIFs. Completion runs on the main queue with the
    /// number of newly saved files.
    static func download(limit: Int = 100, completion: @escaping (Result<Int, Error>) -> Void) {
        let endpoint = URL(string: "https://api.thecatapi.com/v1/images/search?mime_types=gif&limit=\(limit)")!

        URLSession.shared.dataTask(with: endpoint) { data, response, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let entries = try? JSONDecoder().decode([Entry].self, from: data)
            else {
                DispatchQueue.main.async { completion(.failure(CrawlError.badResponse)) }
                return
            }
            fetchImages(entries, completion: completion)
        }.resume()
    }

    private static func fetchImages(_ entries: [Entry], completion: @escaping (Result<Int, Error>) -> Void) {
        let library = CatLibrary.shared
        let existing = Set(library.files.map { $0.deletingPathExtension().lastPathComponent })

        let wanted = entries.filter { !existing.contains($0.id) }
        guard !wanted.isEmpty else {
            DispatchQueue.main.async { completion(.success(0)) }
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var saved = 0

        for entry in wanted {
            guard let source = URL(string: entry.url) else { continue }
            group.enter()
            URLSession.shared.dataTask(with: source) { data, _, _ in
                defer { group.leave() }
                guard let data, !data.isEmpty else { return }

                // Cut the cat out so it walks around without a rectangle behind
                // it. If Vision finds no subject, keep the photo as it came.
                let cutout = BackgroundRemover.cutout(from: data)
                let destination = library.directory.appendingPathComponent(
                    "\(entry.id).\(cutout != nil ? "png" : "gif")"
                )
                guard (try? (cutout ?? data).write(to: destination)) != nil else { return }
                lock.lock()
                saved += 1
                lock.unlock()
            }.resume()
        }

        group.notify(queue: .main) {
            library.forgetCache()
            completion(.success(saved))
        }
    }
}
