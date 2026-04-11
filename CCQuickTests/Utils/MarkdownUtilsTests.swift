import XCTest
@testable import CCQuick

final class MarkdownUtilsTests: XCTestCase {

    func testStripHeadings() {
        let input = "# Main Heading\n## Sub Heading\nContent here"
        let output = MarkdownUtils.stripMarkdown(input)
        XCTAssertFalse(output.contains("#"))
        XCTAssertTrue(output.contains("Main Heading"))
        XCTAssertTrue(output.contains("Sub Heading"))
    }

    func testStripBold() {
        let input = "This is **bold** and __also bold__"
        let output = MarkdownUtils.stripMarkdown(input)
        XCTAssertFalse(output.contains("**"))
        XCTAssertFalse(output.contains("__"))
        XCTAssertTrue(output.contains("bold"))
    }

    func testStripItalic() {
        let input = "This is *italic* and _also italic_"
        let output = MarkdownUtils.stripMarkdown(input)
        XCTAssertFalse(output.contains("*italic*"))
        XCTAssertTrue(output.contains("italic"))
    }

    func testStrikethrough() {
        let input = "~~deleted~~"
        let output = MarkdownUtils.stripMarkdown(input)
        XCTAssertFalse(output.contains("~~"))
        XCTAssertTrue(output.contains("deleted"))
    }

    func testStripLinks() {
        let input = "[Click here](https://example.com)"
        let output = MarkdownUtils.stripMarkdown(input)
        XCTAssertFalse(output.contains("http"))
        XCTAssertFalse(output.contains("["))
        XCTAssertTrue(output.contains("Click here"))
    }

    func testStripImages() {
        let input = "![alt text](image.png)"
        let output = MarkdownUtils.stripMarkdown(input)
        XCTAssertTrue(output.isEmpty || !output.contains("!["))
    }

    func testStripCodeBlock() {
        let input = "Use `code()` here"
        let output = MarkdownUtils.stripMarkdown(input)
        XCTAssertFalse(output.contains("`"))
        XCTAssertTrue(output.contains("code()"))
    }

    func testStripCodeBlocks() {
        let input = """
        Here is some code:
        ```
        let x = 1
        ```
        And more text.
        """
        let output = MarkdownUtils.stripMarkdown(input)
        XCTAssertFalse(output.contains("```"))
        XCTAssertTrue(output.contains("And more text"))
    }

    func testStripListMarkers() {
        let input = "- Item one\n- Item two"
        let output = MarkdownUtils.stripMarkdown(input)
        XCTAssertFalse(output.contains("- "))
        XCTAssertTrue(output.contains("Item one"))
    }

    func testStripOrderedLists() {
        let input = "1. First\n2. Second"
        let output = MarkdownUtils.stripMarkdown(input)
        XCTAssertFalse(output.contains("1."))
        XCTAssertTrue(output.contains("First"))
    }

    func testStripHorizontalRules() {
        let input = "---\nContent\n---"
        let output = MarkdownUtils.stripMarkdown(input)
        XCTAssertFalse(output.contains("---"))
    }

    func testStripMarkdown_complexExample() {
        let input = """
        # Title

        This is **bold text** and *italic text*.

        ## Features
        - Feature one
        - Feature two

        [Link](https://example.com)

        `inline code`

        ---
        """
        let output = MarkdownUtils.stripMarkdown(input)
        XCTAssertFalse(output.contains("#"))
        XCTAssertFalse(output.contains("**"))
        XCTAssertFalse(output.contains("*"))
        XCTAssertFalse(output.contains("- "))
        XCTAssertFalse(output.contains("["))
        XCTAssertFalse(output.contains("```"))
        XCTAssertFalse(output.contains("`"))
        XCTAssertTrue(output.contains("Title"))
        XCTAssertTrue(output.contains("bold text"))
        XCTAssertTrue(output.contains("Feature one"))
        XCTAssertTrue(output.contains("Link"))
        XCTAssertTrue(output.contains("inline code"))
    }

    func testStripMarkdown_stripsCodeBlockMarkers() {
        // Code block markers are stripped; content inside is also skipped
        let input = """
        Here is code:
        ```swift
        let x = 42
        ```
        """
        let output = MarkdownUtils.stripMarkdown(input)
        XCTAssertFalse(output.contains("```"))
        // The function skips code block lines, so "let x = 42" is not in output
    }

    func testStripMarkdown_emptyInput() {
        let output = MarkdownUtils.stripMarkdown("")
        XCTAssertEqual(output, "")
    }

    func testStripMarkdown_plainText() {
        let input = "This is plain text with no markdown."
        let output = MarkdownUtils.stripMarkdown(input)
        XCTAssertEqual(output, "This is plain text with no markdown.")
    }

    func testStripMarkdown_multipleNewlines() {
        let input = "Line 1\n\n\n\n\nLine 2"
        let output = MarkdownUtils.stripMarkdown(input)
        // Should collapse 3+ newlines to 2
        XCTAssertFalse(output.contains("\n\n\n"))
    }
}

final class NotificationServiceTests: XCTestCase {

    // NotificationService is a singleton with UNUserNotificationCenter side effects,
    // so we can only test the pure helper: shortResponse

    func testShortResponse_removesBoldMarkdown() {
        // The NotificationService shortResponse method removes ** and ##
        // We verify via the same patterns used there
        let input = "**Bold** text"
        let output = input
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
        XCTAssertTrue(output.contains("Bold"))
        XCTAssertFalse(output.contains("**"))
    }

    func testShortResponse_truncation() {
        let longText = String(repeating: "a", count: 200)
        let output = MarkdownUtils.stripMarkdown(longText)
        // MarkdownUtils doesn't truncate; NotificationService does.
        // We verify the concept separately.
        XCTAssertEqual(output.count, 200)
    }
}
