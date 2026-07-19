// MarkdownPreview/MarkdownPreviewApp.swift
import SwiftUI

@main
struct MarkdownPreviewApp: App {
    var body: some Scene {
        WindowGroup(id: "preview", for: URL.self) { $fileURL in
            PreviewWindowView(fileURL: $fileURL)
                .onOpenURL { url in
                    fileURL = url
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                NewWindowCommand()
                FileOpenCommand()
            }
        }
    }
}
