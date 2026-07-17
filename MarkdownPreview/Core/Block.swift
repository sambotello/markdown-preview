import Foundation

struct Block: Equatable {
    enum Kind: Equatable {
        case heading(level: Int, text: AttributedString)
        case paragraph(text: AttributedString)
        case codeBlock(code: String, language: String?)
        case list(items: [ListItem], isOrdered: Bool)
        case table(headers: [AttributedString], rows: [[AttributedString]])
        case image(url: URL, altText: String)
        case blockQuote(blocks: [Block])
        case thematicBreak
    }

    struct ListItem: Equatable {
        let content: AttributedString
        let children: [Block]
    }

    let kind: Kind
}
