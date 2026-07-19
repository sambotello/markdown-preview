// MarkdownPreview/Core/MarkdownDocument.swift
import Foundation
import Observation

@MainActor
@Observable
final class MarkdownDocument {
    enum State: Equatable {
        case empty
        case loaded(blocks: [Block])
        case fileMissing
        case unsupportedFile
        case error(message: String)
    }

    private(set) var state: State = .empty
    private(set) var url: URL?
    private(set) var rawText: String?
    private var watcher: FileWatcher?

    private static let supportedExtensions: Set<String> = ["md", "markdown"]

    var blocks: [Block]? {
        if case .loaded(let blocks) = state { blocks } else { nil }
    }

    func load(url: URL) {
        guard Self.supportedExtensions.contains(url.pathExtension.lowercased()) else {
            watcher = nil
            self.url = nil
            state = .unsupportedFile
            return
        }
        self.url = url
        reload()
        watcher = FileWatcher(url: url) { [weak self] event in
            DispatchQueue.main.async {
                guard let self else { return }
                switch event {
                case .changed:
                    self.reload()
                case .missing:
                    self.state = .fileMissing
                }
            }
        }
    }

    func close() {
        watcher = nil
        url = nil
        rawText = nil
        state = .empty
    }

    private func reload() {
        guard let url else { return }
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            let baseURL = url.deletingLastPathComponent()
            rawText = source
            state = .loaded(blocks: MarkdownRenderer.render(markdown: source, baseURL: baseURL))
        } catch {
            rawText = nil
            state = .error(message: error.localizedDescription)
        }
    }
}
