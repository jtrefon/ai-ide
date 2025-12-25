import XCTest
@testable import osx_ide

final class MarkdownParserTests: XCTestCase {
    func testParse_withPlainText_returnsSingleRichTextBlock() {
        let input = "Hello world"
        let document = MarkdownDocument.parse(input)

        XCTAssertEqual(document.blocks.count, 1)
        switch document.blocks[0].kind {
        case .richText(let text):
            XCTAssertEqual(text, input)
        case .code, .horizontalRule:
            XCTFail("Expected .richText block")
        }
    }

    func testParse_withSingleCodeBlockWithoutLanguage_returnsRichTextAndCode() {
        let input = "Before\n```\nprint(\"hi\")\n```\nAfter"
        let document = MarkdownDocument.parse(input)

        XCTAssertEqual(document.blocks.count, 3)

        switch document.blocks[0].kind {
        case .richText(let text):
            XCTAssertEqual(text, "Before\n")
        case .code, .horizontalRule:
            XCTFail("Expected first block to be .richText")
        }

        switch document.blocks[1].kind {
        case .code(let code, let language):
            XCTAssertNil(language)
            XCTAssertEqual(code, "print(\"hi\")")
        case .richText, .horizontalRule:
            XCTFail("Expected second block to be .code")
        }

        switch document.blocks[2].kind {
        case .richText(let text):
            XCTAssertEqual(text, "\nAfter")
        case .code, .horizontalRule:
            XCTFail("Expected third block to be .richText")
        }
    }

    func testParse_withSingleCodeBlockWithLanguage_extractsLanguage() {
        let input = "```swift\nlet x = 1\n```"
        let document = MarkdownDocument.parse(input)

        XCTAssertEqual(document.blocks.count, 1)
        switch document.blocks[0].kind {
        case .code(let code, let language):
            XCTAssertEqual(language, "swift")
            XCTAssertEqual(code, "let x = 1")
        case .richText, .horizontalRule:
            XCTFail("Expected .code block")
        }
    }

    func testParse_withMultipleCodeBlocks_preservesOrder() {
        let input = "A\n```swift\nlet a = 1\n```\nB\n```python\nprint('x')\n```\nC"
        let document = MarkdownDocument.parse(input)

        XCTAssertEqual(document.blocks.count, 5)

        switch document.blocks[0].kind {
        case .richText(let text):
            XCTAssertEqual(text, "A\n")
        case .code, .horizontalRule:
            XCTFail("Expected .richText")
        }

        switch document.blocks[1].kind {
        case .code(let code, let language):
            XCTAssertEqual(language, "swift")
            XCTAssertEqual(code, "let a = 1")
        case .richText, .horizontalRule:
            XCTFail("Expected .code")
        }

        switch document.blocks[2].kind {
        case .richText(let text):
            XCTAssertEqual(text, "\nB\n")
        case .code, .horizontalRule:
            XCTFail("Expected .richText")
        }

        switch document.blocks[3].kind {
        case .code(let code, let language):
            XCTAssertEqual(language, "python")
            XCTAssertEqual(code, "print('x')")
        case .richText, .horizontalRule:
            XCTFail("Expected .code")
        }

        switch document.blocks[4].kind {
        case .richText(let text):
            XCTAssertEqual(text, "\nC")
        case .code, .horizontalRule:
            XCTFail("Expected .richText")
        }
    }

    func testParse_withUnclosedCodeFence_treatsAsRichText() {
        let input = "Hello\n```swift\nlet x = 1"
        let document = MarkdownDocument.parse(input)

        XCTAssertEqual(document.blocks.count, 1)
        switch document.blocks[0].kind {
        case .richText(let text):
            XCTAssertEqual(text, input)
        case .code, .horizontalRule:
            XCTFail("Expected .richText")
        }
    }

    func testParse_withHorizontalRule_splitsIntoRuleBlock() {
        let input = "Top\n---\nBottom"
        let document = MarkdownDocument.parse(input)

        XCTAssertEqual(document.blocks.count, 3)

        switch document.blocks[0].kind {
        case .richText(let text):
            XCTAssertEqual(text, "Top")
        default:
            XCTFail("Expected first block to be rich text")
        }

        switch document.blocks[1].kind {
        case .horizontalRule:
            break
        default:
            XCTFail("Expected second block to be horizontal rule")
        }

        switch document.blocks[2].kind {
        case .richText(let text):
            XCTAssertEqual(text, "Bottom")
        default:
            XCTFail("Expected third block to be rich text")
        }
    }
}
