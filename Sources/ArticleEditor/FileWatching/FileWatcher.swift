import Foundation
import ReactiveConcurrency

public enum FileWatchEvent: Sendable, Equatable {
    case changed
}

/// Watches a single open file for on-disk changes via `DispatchSourceFileSystemObject`
/// bound to that file's own descriptor — the right granularity for "this one open
/// document," unlike `FSEventStreamCreate`'s directory-scoped, batched/coalesced events.
public enum FileWatcher {
    public static func watch(url: URL) -> Publisher<FileWatchEvent, Never> {
        Publisher { continuation in
            let box = Box()
            box.arm(path: url.path, yield: { continuation.yield(.changed) }, finish: { continuation.finish() })
            await continuation.suspendUntilCancelled()
            box.teardown()
        }
    }

    /// Holds the mutable fd/source pair a watch needs across re-arms. Every mutation
    /// happens on `queue`, a dedicated serial queue — this is the discipline that makes
    /// `@unchecked Sendable` safe here: the event handler, the re-arm-after-atomic-save
    /// path, and teardown all serialize through the same queue, so there is no point
    /// where two of them touch `fd`/`source` concurrently.
    private final class Box: @unchecked Sendable {
        private let queue = DispatchQueue(label: "ios.lu.FileWatching.FileWatcher")
        private var fd: Int32 = -1
        private var source: DispatchSourceFileSystemObject?

        func arm(path: String, yield: @escaping @Sendable () -> Void, finish: @escaping @Sendable () -> Void) {
            queue.async { [self] in
                fd = open(path, O_EVTONLY)
                guard fd >= 0 else {
                    finish()
                    return
                }
                let newSource = DispatchSource.makeFileSystemObjectSource(
                    fileDescriptor: fd,
                    eventMask: [.write, .delete, .rename, .extend],
                    queue: queue
                )
                newSource.setEventHandler { [self] in
                    let flags = newSource.data
                    // Always notify: a delete/rename IS a change (the old inode is gone,
                    // replaced by something new), not merely bookkeeping to hide from
                    // the subscriber.
                    yield()
                    if flags.contains(.delete) || flags.contains(.rename) {
                        // Atomic saves (this app's own writes, and most editors/git)
                        // replace-via-rename, which unlinks the fd we're watching.
                        // Close it and reopen the same path to pick up the new inode,
                        // so the watch keeps following the file rather than a
                        // now-orphaned descriptor.
                        newSource.cancel()
                        close(fd)
                        arm(path: path, yield: yield, finish: finish)
                    }
                }
                source = newSource
                newSource.activate()
            }
        }

        func teardown() {
            queue.sync {
                source?.cancel()
                if fd >= 0 { close(fd) }
            }
        }
    }
}
