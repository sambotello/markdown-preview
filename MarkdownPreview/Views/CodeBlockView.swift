// MarkdownPreview/Views/CodeBlockView.swift
import SwiftUI
import Highlightr

struct CodeBlockView: View {
    let code: String
    let language: String?

    @Environment(\.colorScheme) private var colorScheme

    private static let highlightr = Highlightr()

    var body: some View {
        ScrollView(.horizontal) {
            Text(highlightedCode)
                .padding(8)
        }
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var themeName: String {
        colorScheme == .dark ? MarkdownTypography.codeThemeDark : MarkdownTypography.codeThemeLight
    }

    private var backgroundColor: Color {
        guard let highlightr = Self.highlightr, highlightr.setTheme(to: themeName) else {
            return Color.secondary.opacity(0.1)
        }
        return Color(nsColor: highlightr.theme.themeBackgroundColor)
    }

    private var highlightedCode: AttributedString {
        guard let highlightr = Self.highlightr, highlightr.setTheme(to: themeName) else {
            return AttributedString(code)
        }
        highlightr.theme.setCodeFont(.monospacedSystemFont(ofSize: MarkdownTypography.code, weight: .regular))
        guard let attributed = highlightr.highlight(code, as: language) else {
            return AttributedString(code)
        }
        return (try? AttributedString(attributed, including: \.appKit)) ?? AttributedString(code)
    }
}
