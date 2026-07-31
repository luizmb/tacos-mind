import FP
import Foundation
import NetworkServer
import ReactiveConcurrency

/// A tiny static-file server for the article preview (Cmd+R/Cmd+B). Generated HTML uses
/// root-absolute paths (`/style.css`, `/articles/x.html`) — a `file://` load resolves those
/// against the real filesystem root, not `dist/`, so Safari can't preview the site directly
/// off disk. Serving `dist/` over `http://127.0.0.1` gives those absolute paths a real origin
/// to resolve against, with zero changes to the generated HTML.
enum PreviewServer {
    static let port = 4676

    private static let lock = NSLock()
    // `nonisolated(unsafe)`: every access is guarded by `lock` below, so this is safe
    // despite being global mutable state — the compiler can't see the lock discipline.
    private static nonisolated(unsafe) var isStarted = false

    /// Idempotent — the first caller (whichever platform, whenever Cmd+R first fires) binds
    /// the port and starts serving `directory`; later calls are no-ops. There's no explicit
    /// shutdown: this is a personal dev-preview server meant to live for the app's process
    /// lifetime, same category as `confirmQuit`'s main-thread-blocking `NSAlert`.
    static func ensureStarted(servingDirectory directory: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard !isStarted else { return }
        isStarted = true

        let router = Router<Void> { request in
            Reader { _ in Publisher.future { serveFile(atRequestPath: request.path, from: directory) } }
        }
        Task.detached {
            _ = startServer(port: port, router: router).runReader(())
        }
    }

    private static func serveFile(atRequestPath path: String, from directory: URL) -> Result<Response, ResponseError> {
        let relativePath = path == "/" ? "index.html" : String(path.dropFirst())
        let fileURL = directory.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: fileURL) else {
            return .failure(.notFound)
        }
        return .success(Response(headers: [("Content-Type", contentType(for: fileURL))], body: data))
    }

    private static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html": "text/html; charset=utf-8"
        case "css": "text/css"
        case "ttf": "font/ttf"
        case "txt": "text/plain"
        default: "application/octet-stream"
        }
    }
}
