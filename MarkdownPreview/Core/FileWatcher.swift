import Foundation

final class FileWatcher {
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

    init(url: URL, gracePeriod: TimeInterval = 0.5, onEvent: @escaping (Event) -> Void) {
        self.url = url
        self.gracePeriod = gracePeriod
        self.onEvent = onEvent
        start()
    }

    deinit {
        source?.cancel()
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
            }
        }
        missingWorkItem = workItem
        queue.asyncAfter(deadline: .now() + gracePeriod, execute: workItem)
    }
}
