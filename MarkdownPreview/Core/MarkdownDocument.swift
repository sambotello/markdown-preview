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
    private(set) var savedText: String?
    private(set) var saveError: String?
    private(set) var pendingExternalChange: String?
    private var watcher: FileWatcher?

    private static let supportedExtensions: Set<String> = ["md", "markdown"]

    var blocks: [Block]? {
        if case .loaded(let blocks) = state { blocks } else { nil }
    }

    var isDirty: Bool {
        rawText != nil && rawText != savedText
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
                    self.handleExternalChange()
                case .missing:
                    if !self.isDirty {
                        self.state = .fileMissing
                    }
                }
            }
        }
    }

    func close() {
        watcher = nil
        url = nil
        rawText = nil
        savedText = nil
        saveError = nil
        pendingExternalChange = nil
        state = .empty
    }

    func updateDraft(_ text: String) {
        guard let url else { return }
        rawText = text
        state = .loaded(blocks: MarkdownRenderer.render(markdown: text, baseURL: url.deletingLastPathComponent()))
    }

    func save() {
        guard let url, let rawText else { return }
        do {
            try rawText.write(to: url, atomically: true, encoding: .utf8)
            savedText = rawText
            saveError = nil
            pendingExternalChange = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    func dismissSaveError() {
        saveError = nil
    }

    func keepMyEdits() {
        pendingExternalChange = nil
    }

    func reloadFromDisk() {
        pendingExternalChange = nil
        reload()
    }

    private func handleExternalChange() {
        guard let url else { return }
        guard let newContent = try? String(contentsOf: url, encoding: .utf8) else {
            if !isDirty {
                reload()
            }
            return
        }
        if newContent == savedText {
            return
        }
        if isDirty {
            pendingExternalChange = newContent
        } else {
            reload()
        }
    }

    private func reload() {
        guard let url else { return }
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            let baseURL = url.deletingLastPathComponent()
            rawText = source
            savedText = source
            state = .loaded(blocks: MarkdownRenderer.render(markdown: source, baseURL: baseURL))
        } catch {
            rawText = nil
            savedText = nil
            state = .error(message: error.localizedDescription)
        }
    }
}
