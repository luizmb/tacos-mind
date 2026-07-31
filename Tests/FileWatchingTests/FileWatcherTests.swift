import Foundation
import ReactiveConcurrency
import Testing

@testable import FileWatching

@Suite("FileWatcher")
struct FileWatcherTests {
    @Test("fires an event when the watched file is written")
    func firesOnWrite() async throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("filewatcher-test-\(UUID().uuidString).txt")
        try "initial".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let received = Box(0)
        let cancellable = FileWatcher.watch(url: url).sink { _ in received.increment() }

        try await Task.sleep(for: .milliseconds(200))
        try "changed".write(to: url, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(500))

        cancellable.cancel()
        #expect(received.value > 0, "expected at least one file-watch event after a write")
    }

    @Test("survives an atomic replace-via-rename save")
    func survivesAtomicReplace() async throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("filewatcher-atomic-test-\(UUID().uuidString).txt")
        try "initial".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let received = Box(0)
        let cancellable = FileWatcher.watch(url: url).sink { _ in received.increment() }

        try await Task.sleep(for: .milliseconds(200))
        // .atomically: true is itself a write-then-rename — the exact case the watcher
        // must survive by reopening the new inode.
        try "first atomic replace".write(to: url, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(400))
        try "second atomic replace".write(to: url, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(400))

        cancellable.cancel()
        #expect(received.value >= 2, "expected the watcher to survive across two atomic replaces, got \(received.value) events")
    }
}

private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int
    init(_ value: Int) { _value = value }
    func increment() {
        lock.lock()
        defer { lock.unlock() }
        _value += 1
    }
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
}
