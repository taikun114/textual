import Foundation
import Testing

@testable import Textual

struct MarkdownBlockSplitterTests {
    @Test func splitsParagraphs() {
        let markdown = """
        これは最初の段落です。

        これは2つ目の段落です。
        """

        let blocks = MarkdownBlockSplitter.split(markdown)
        #expect(blocks.count == 2)
        #expect(blocks[0].kind == .other)
        #expect(blocks[0].markdown == "これは最初の段落です。")
        #expect(blocks[0].renderMarkdown == "これは最初の段落です。")
        #expect(blocks[1].kind == .other)
        #expect(blocks[1].markdown == "これは2つ目の段落です。")
    }

    @Test func detectsHeadersAndLists() {
        let markdown = """
        # 見出し1

        - リスト項目1
        - リスト項目2
        """

        let blocks = MarkdownBlockSplitter.split(markdown)
        #expect(blocks.count == 2)
        #expect(blocks[0].kind == .header)
        #expect(blocks[1].kind == .list)
    }

    @Test func autoClosesUnclosedCodeBlockDuringStreaming() {
        let markdown = """
        テキストの導入部分です。

        ```swift
        let x = 10
        print(x)
        """

        let blocks = MarkdownBlockSplitter.split(markdown, isStreaming: true)
        #expect(blocks.count == 2)
        #expect(blocks[0].kind == .other)
        #expect(blocks[1].kind == .codeBlock)
        #expect(blocks[1].isUnclosedCodeBlock == true)
        #expect(blocks[1].renderMarkdown.hasSuffix("\n```"))
        #expect(blocks[1].renderMarkdown.contains("let x = 10"))
    }

    @Test func handlesCompletedCodeBlock() {
        let markdown = """
        ```swift
        let x = 10
        ```
        """

        let blocks = MarkdownBlockSplitter.split(markdown)
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .codeBlock)
        #expect(blocks[0].isUnclosedCodeBlock == false)
        #expect(blocks[0].renderMarkdown == blocks[0].markdown)
    }

    @Test func handlesConsecutiveCodeBlocksWithoutBlankLines() {
        let markdown = """
        ```swift
        let a = 1
        ```
        ```python
        b = 2
        ```
        """

        let blocks = MarkdownBlockSplitter.split(markdown)
        #expect(blocks.count == 2)
        #expect(blocks[0].kind == .codeBlock)
        #expect(blocks[0].markdown.contains("let a = 1"))
        #expect(blocks[1].kind == .codeBlock)
        #expect(blocks[1].markdown.contains("b = 2"))
    }
}
