import Markdown

enum MarkdownParser {
    static func parse(_ source: String) -> Document {
        Document(parsing: source)
    }
}
