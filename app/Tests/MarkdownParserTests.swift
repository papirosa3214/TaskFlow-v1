import XCTest
@testable import TaskFlow

final class MarkdownParserTests: XCTestCase {

    // MARK: - Базовое

    func testEmptyStringYieldsSingleParagraph() {
        let blocks = MarkdownParser.parse("")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .paragraph)
        XCTAssertTrue(blocks[0].runs.isEmpty)
    }

    func testWhitespaceOnlyYieldsSingleParagraph() {
        let blocks = MarkdownParser.parse("   \n\n  ")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .paragraph)
    }

    // MARK: - Заголовки

    func testHeadingsH1H2H3() {
        let blocks = MarkdownParser.parse("# Заголовок 1\n## Заголовок 2\n### Заголовок 3")
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].kind, .heading(level: 1))
        XCTAssertEqual(blocks[0].runs.first?.text, "Заголовок 1")
        XCTAssertEqual(blocks[1].kind, .heading(level: 2))
        XCTAssertEqual(blocks[2].kind, .heading(level: 3))
    }

    func testH4ClampedToH3() {
        let blocks = MarkdownParser.parse("#### Глубоко")
        XCTAssertEqual(blocks[0].kind, .heading(level: 3))
    }

    // MARK: - Параграфы и разделители

    func testBlankLinesSeparateParagraphs() {
        let blocks = MarkdownParser.parse("Первый абзац\n\nВторой абзац")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].kind, .paragraph)
        XCTAssertEqual(blocks[0].runs.first?.text, "Первый абзац")
        XCTAssertEqual(blocks[1].runs.first?.text, "Второй абзац")
    }

    func testParagraphStopsAtHeading() {
        let blocks = MarkdownParser.parse("Обычный текст\n# Внезапный заголовок")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].kind, .paragraph)
        XCTAssertEqual(blocks[1].kind, .heading(level: 1))
    }

    func testParagraphStopsAtBlockquote() {
        let blocks = MarkdownParser.parse("Текст\n> Цитата")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].kind, .paragraph)
        XCTAssertEqual(blocks[1].kind, .blockquote)
    }

    // MARK: - Горизонтальная линия

    func testHorizontalRuleDashes() {
        let blocks = MarkdownParser.parse("---")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .horizontalRule)
    }

    func testHorizontalRuleStarsAndUnderscores() {
        XCTAssertEqual(MarkdownParser.parse("***").first?.kind, .horizontalRule)
        XCTAssertEqual(MarkdownParser.parse("___").first?.kind, .horizontalRule)
    }

    // MARK: - Код-блок

    func testCodeBlockWithoutLanguage() {
        let blocks = MarkdownParser.parse("```\nlet x = 1\nlet y = 2\n```")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .codeBlock(language: nil))
        XCTAssertEqual(blocks[0].runs.first?.text, "let x = 1\nlet y = 2")
    }

    func testCodeBlockWithLanguage() {
        let blocks = MarkdownParser.parse("```swift\nlet x = 1\n```")
        XCTAssertEqual(blocks[0].kind, .codeBlock(language: "swift"))
    }

    func testUnclosedCodeFallsBackToParagraph() {
        let blocks = MarkdownParser.parse("```\nlet x = 1")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .paragraph)
    }

    // MARK: - Списки

    func testBulletList() {
        let blocks = MarkdownParser.parse("- раз\n- два\n- три")
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks.map(\.kind), [.bulletItem, .bulletItem, .bulletItem])
        XCTAssertEqual(blocks.map(\.level), [0, 0, 0])
    }

    func testOrderedList() {
        let blocks = MarkdownParser.parse("1. раз\n2. два")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks.map(\.kind), [.orderedItem, .orderedItem])
    }

    func testTaskListCheckedAndUnchecked() {
        let blocks = MarkdownParser.parse("- [ ] сделанное\n- [x] готовое\n- [X] ТОЖЕ")
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].kind, .taskItem(checked: false))
        XCTAssertEqual(blocks[1].kind, .taskItem(checked: true))
        XCTAssertEqual(blocks[2].kind, .taskItem(checked: true))
    }

    func testNestedBulletByIndent() {
        let blocks = MarkdownParser.parse("- верх\n  - вложен\n- снова верх")
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].level, 0)
        XCTAssertEqual(blocks[1].level, 1)
        XCTAssertEqual(blocks[2].level, 0)
    }

    // MARK: - Цитата

    func testBlockquoteSingleLine() {
        let blocks = MarkdownParser.parse("> Цитата")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .blockquote)
        XCTAssertEqual(blocks[0].runs.first?.text, "Цитата")
    }

    func testConsecutiveBlockquoteLinesMerge() {
        let blocks = MarkdownParser.parse("> первая\n> вторая")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .blockquote)
    }

    // MARK: - Инлайн: марки

    func testInlineBold() {
        let blocks = MarkdownParser.parse("Это **жирный** текст")
        XCTAssertEqual(blocks.count, 1)
        let runs = blocks[0].runs
        XCTAssertEqual(runs.count, 3)
        XCTAssertEqual(runs[0].text, "Это ")
        XCTAssertEqual(runs[1].text, "жирный")
        XCTAssertTrue(runs[1].bold)
        XCTAssertEqual(runs[2].text, " текст")
    }

    func testInlineItalic() {
        let blocks = MarkdownParser.parse("Это *курсив*")
        let runs = blocks[0].runs
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0].text, "Это ")
        XCTAssertEqual(runs[1].text, "курсив")
        XCTAssertTrue(runs[1].italic)
    }

    func testInlineStrike() {
        let blocks = MarkdownParser.parse("Это ~~зачёркнутый~~")
        XCTAssertEqual(blocks[0].runs[1].text, "зачёркнутый")
        XCTAssertTrue(blocks[0].runs[1].strike)
    }

    func testInlineCode() {
        let blocks = MarkdownParser.parse("Это `код`")
        XCTAssertEqual(blocks[0].runs[1].text, "код")
        XCTAssertTrue(blocks[0].runs[1].code)
    }

    func testInlineLink() {
        let blocks = MarkdownParser.parse("См [доку](https://example.com)")
        let linkRun = blocks[0].runs.first { $0.linkHref != nil }
        XCTAssertEqual(linkRun?.text, "доку")
        XCTAssertEqual(linkRun?.linkHref, "https://example.com")
    }

    func testInlineEscapedCharacters() {
        let blocks = MarkdownParser.parse("Звёздочка \\* и скобка \\[")
        XCTAssertEqual(blocks[0].runs.first?.text, "Звёздочка * и скобка [")
    }

    // MARK: - Комплекс

    func testMixedDocument() {
        let md = """
        # Заголовок

        Обычный **жирный** и *курсивный* текст.

        - пункт 1
        - [x] задача

        > цитата с [ссылкой](https://x.ru)

        ```
        let x = 1
        ```
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 6)
        XCTAssertEqual(blocks[0].kind, .heading(level: 1))
        XCTAssertEqual(blocks[1].kind, .paragraph)
        XCTAssertEqual(blocks[2].kind, .bulletItem)
        XCTAssertEqual(blocks[3].kind, .taskItem(checked: true))
        XCTAssertEqual(blocks[4].kind, .blockquote)
        XCTAssertEqual(blocks[5].kind, .codeBlock(language: nil))
    }
}
