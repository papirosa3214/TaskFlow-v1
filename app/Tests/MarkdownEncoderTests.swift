import XCTest
@testable import TaskFlow

final class MarkdownEncoderTests: XCTestCase {

    // MARK: - Базовые блоки

    func testEmptyBlocksYieldsEmptyString() {
        XCTAssertEqual(MarkdownEncoder.encode([]), "")
    }

    func testSingleParagraph() {
        let blocks = [NoteBlock(kind: .paragraph, runs: [RichRun(text: "Привет")])]
        XCTAssertEqual(MarkdownEncoder.encode(blocks), "Привет")
    }

    func testHeadings() {
        let blocks = [
            NoteBlock(kind: .heading(level: 1), runs: [RichRun(text: "Один")]),
            NoteBlock(kind: .heading(level: 2), runs: [RichRun(text: "Два")]),
            NoteBlock(kind: .heading(level: 3), runs: [RichRun(text: "Три")]),
        ]
        let md = MarkdownEncoder.encode(blocks)
        XCTAssertEqual(md, "# Один\n\n## Два\n\n### Три")
    }

    func testHeadingLevelClampedToThree() {
        // AST может прийти с level=4..6 от старого TipTap; кодер не должен
        // выпускать «####» — клампим, чтобы парсер при обратном чтении
        // тоже увидел H3.
        let blocks = [NoteBlock(kind: .heading(level: 5), runs: [RichRun(text: "Глубоко")])]
        XCTAssertEqual(MarkdownEncoder.encode(blocks), "### Глубоко")
    }

    func testHorizontalRule() {
        let blocks = [NoteBlock(kind: .horizontalRule)]
        XCTAssertEqual(MarkdownEncoder.encode(blocks), "---")
    }

    // MARK: - Списки

    func testBulletListFlat() {
        let blocks = [
            NoteBlock(kind: .bulletItem, level: 0, runs: [RichRun(text: "раз")]),
            NoteBlock(kind: .bulletItem, level: 0, runs: [RichRun(text: "два")]),
        ]
        XCTAssertEqual(MarkdownEncoder.encode(blocks), "- раз\n\n- два")
    }

    func testBulletListNested() {
        let blocks = [
            NoteBlock(kind: .bulletItem, level: 0, runs: [RichRun(text: "верх")]),
            NoteBlock(kind: .bulletItem, level: 1, runs: [RichRun(text: "вложен")]),
        ]
        XCTAssertEqual(MarkdownEncoder.encode(blocks), "- верх\n\n  - вложен")
    }

    func testOrderedAndTaskLists() {
        let blocks = [
            NoteBlock(kind: .orderedItem, level: 0, runs: [RichRun(text: "шаг")]),
            NoteBlock(kind: .taskItem(checked: false), level: 0, runs: [RichRun(text: "todo")]),
            NoteBlock(kind: .taskItem(checked: true), level: 0, runs: [RichRun(text: "готово")]),
        ]
        XCTAssertEqual(MarkdownEncoder.encode(blocks), "1. шаг\n\n- [ ] todo\n\n- [x] готово")
    }

    // MARK: - Цитата и код

    func testBlockquote() {
        let blocks = [NoteBlock(kind: .blockquote, runs: [RichRun(text: "мысль")])]
        XCTAssertEqual(MarkdownEncoder.encode(blocks), "> мысль")
    }

    func testCodeBlockWithLanguage() {
        let blocks = [
            NoteBlock(kind: .codeBlock(language: "swift"), runs: [RichRun(text: "let x = 1")])
        ]
        XCTAssertEqual(MarkdownEncoder.encode(blocks), "```swift\nlet x = 1\n```")
    }

    // MARK: - Инлайн

    func testInlineBold() {
        let runs = [RichRun(text: "Это "), RichRun(text: "жирный", bold: true), RichRun(text: " текст")]
        let blocks = [NoteBlock(kind: .paragraph, runs: runs)]
        XCTAssertEqual(MarkdownEncoder.encode(blocks), "Это **жирный** текст")
    }

    func testInlineItalicStrikeCodeLink() {
        let runs = [
            RichRun(text: "a"),
            RichRun(text: "b", italic: true),
            RichRun(text: "c", strike: true),
            RichRun(text: "k", code: true),
            RichRun(text: "site", linkHref: "https://x.ru"),
        ]
        let blocks = [NoteBlock(kind: .paragraph, runs: runs)]
        let md = MarkdownEncoder.encode(blocks)
        XCTAssertTrue(md.contains("*b*"), md)
        XCTAssertTrue(md.contains("~~c~~"), md)
        XCTAssertTrue(md.contains("`k`"), md)
        XCTAssertTrue(md.contains("[site](https://x.ru)"), md)
    }

    func testSpecialCharsEscapedInPlainText() {
        // Звёздочка в обычном тексте должна экранироваться — иначе парсер
        // при обратном чтении решит, что это начало разметки.
        let blocks = [NoteBlock(kind: .paragraph, runs: [RichRun(text: "a * b")])]
        XCTAssertEqual(MarkdownEncoder.encode(blocks), "a \\* b")
    }

    func testSpecialCharsNotEscapedInsideCode() {
        let runs = [RichRun(text: "let x = a * b", code: true)]
        let blocks = [NoteBlock(kind: .paragraph, runs: runs)]
        XCTAssertEqual(MarkdownEncoder.encode(blocks), "`let x = a * b`")
    }

    // MARK: - Round-trip (encode → parse → equal)

    func testRoundTripSimpleDocument() {
        let original = """
        # Заголовок

        Текст **жирным** и *курсивом*.

        - пункт
        - [x] задача
        """
        let parsed = MarkdownParser.parse(original)
        let encoded = MarkdownEncoder.encode(parsed)
        let reparsed = MarkdownParser.parse(encoded)
        XCTAssertEqual(parsed.count, reparsed.count)
        for (a, b) in zip(parsed, reparsed) {
            XCTAssertEqual(a.kind, b.kind)
            XCTAssertEqual(a.level, b.level)
        }
    }
}
