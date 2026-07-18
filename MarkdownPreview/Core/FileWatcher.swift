import Foundation

// The app target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which would
// otherwise make this a MainActor-isolated type by default. That's semantically wrong:
// `FileWatcher`'s thread-safety comes from its own private serial `queue`, not from the
// main actor — every dispatch-source event handler, the delayed grace-period check, and
// the directory-watch fallback all run on `queue` and mutate `source`/`directorySource`/
// `missingWorkItem` there, never on the main actor. Mark the type `nonisolated` to opt out
// of the inferred isolation explicitly. (Consumers like `MarkdownDocument` are unaffected:
// it's `@MainActor` itself and already hops back to `DispatchQueue.main.async` before
// touching its own state inside the `onEvent` callback.)
nonisolated final class FileWatcher {
    enum Event {
        case changed
        case missing
    }

    private let url: URL
    private let gracePeriod: TimeInterval
    private let onEvent: (Event) -> Void
    private let queue = DispatchQueue(label: "com.sambotello.MarkdownPreview.FileWatcher")
    private var source: DispatchSourceFileSystemObject?
    private var missingWorkItem: DispatchWorkItem?
    /// Fallback watcher used once the file has been confirmed missing (i.e. after
    /// `scheduleMissingCheck`'s grace-period check has already fired `.missing`).
    /// Since there's no file descriptor to hold open on a path that doesn't exist,
    /// this watches the *parent directory* for writes (directory entries changing
    /// triggers `.write` on the directory itself) and, on each such event, checks
    /// whether the watched file has reappeared.
    private var directorySource: DispatchSourceFileSystemObject?

    init(url: URL, gracePeriod: TimeInterval = 0.5, onEvent: @escaping (Event) -> Void) {
        self.url = url
        self.gracePeriod = gracePeriod
        self.onEvent = onEvent
        start()
    }

    deinit {
        source?.cancel()
        directorySource?.cancel()
    }

    private func start() {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            scheduleMissingCheck()
            return
        }
        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: queue
        )
        newSource.setEventHandler { [weak self, weak newSource] in
            guard let self, let newSource else { return }
            self.handleEvent(source: newSource)
        }
        newSource.setCancelHandler {
            close(descriptor)
        }
        newSource.resume()
        source = newSource
    }

    private func handleEvent(source: DispatchSourceFileSystemObject) {
        let flags = source.data
        if flags.contains(.delete) || flags.contains(.rename) {
            source.cancel()
            self.source = nil
            scheduleMissingCheck()
        } else {
            missingWorkItem?.cancel()
            onEvent(.changed)
        }
    }

    private func scheduleMissingCheck() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if FileManager.default.fileExists(atPath: self.url.path) {
                self.start()
                self.onEvent(.changed)
            } else {
                self.onEvent(.missing)
                self.watchParentDirectoryForReappearance()
            }
        }
        missingWorkItem = workItem
        queue.asyncAfter(deadline: .now() + gracePeriod, execute: workItem)
    }

    /// Called once, right after `.missing` has been reported, to keep watching for
    /// the file's eventual reappearance beyond the grace period. Does nothing if a
    /// directory watch is already active (so it's only ever created once per
    /// "confirmed missing" episode).
    private func watchParentDirectoryForReappearance() {
        guard directorySource == nil else { return }

        let directoryPath = url.deletingLastPathComponent().path
        let descriptor = open(directoryPath, O_EVTONLY)
        guard descriptor >= 0 else {
            // Nothing more we can do without an open descriptor to watch (e.g. the
            // parent directory itself doesn't exist). Stay dormant, as before.
            return
        }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write],
            queue: queue
        )
        newSource.setEventHandler { [weak self] in
            self?.handleDirectoryEvent()
        }
        newSource.setCancelHandler {
            close(descriptor)
        }
        newSource.resume()
        directorySource = newSource
    }

    /// Fires on every change to the parent directory's contents while the watched
    /// file is confirmed missing. Only acts once the file has genuinely reappeared;
    /// otherwise it just keeps waiting on the existing directory watch (no repeated
    /// `.missing` events).
    private func handleDirectoryEvent() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        directorySource?.cancel()
        directorySource = nil
        start()
        onEvent(.changed)
    }
}
