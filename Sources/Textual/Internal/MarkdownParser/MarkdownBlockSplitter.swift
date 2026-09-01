import Foundation

extension StructuredText {
    public struct BlockInfo: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let markdown: String
        public let renderMarkdown: String
        public let kind: BlockKind
        public let isUnclosedCodeBlock: Bool
        public let attributedString: AttributedString

        public init(
            id: UUID = UUID(),
            markdown: String,
            renderMarkdown: String? = nil,
            kind: BlockKind,
            isUnclosedCodeBlock: Bool = false,
            attributedString: AttributedString = AttributedString()
        ) {
            self.id = id
            self.markdown = markdown
            self.renderMarkdown = renderMarkdown ?? markdown
            self.kind = kind
            self.isUnclosedCodeBlock = isUnclosedCodeBlock
            self.attributedString = attributedString
        }

        public static func == (lhs: BlockInfo, rhs: BlockInfo) -> Bool {
            lhs.markdown == rhs.markdown &&
            lhs.renderMarkdown == rhs.renderMarkdown &&
            lhs.kind == rhs.kind &&
            lhs.isUnclosedCodeBlock == rhs.isUnclosedCodeBlock &&
            lhs.attributedString == rhs.attributedString
        }
    }
    
    public enum BlockKind: Sendable, Equatable {
        case header, list, table, codeBlock, other
    }
}

enum MarkdownBlockSplitter {
    static func split(_ markdown: String, isStreaming: Bool = false) -> [StructuredText.BlockInfo] {
        var blocks: [StructuredText.BlockInfo] = []
        var currentBlockLines: [String] = []
        var inCodeBlock = false
        var codeBlockFence = ""
        
        let lines = markdown.components(separatedBy: "\n")
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = leadingIndentCount(line)
            let isFencePrefix = trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
            // インデントが4未満の場合のみトップレベルのフェンスコードブロック開始と判定
            let isTopLevelFenceStart = !inCodeBlock && indent < 4 && isFencePrefix
            
            if !inCodeBlock {
                if isTopLevelFenceStart {
                    // コードブロック開始直前にたまっていた通常テキストがあれば確定
                    if !currentBlockLines.isEmpty {
                        let text = currentBlockLines.joined(separator: "\n")
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            blocks.append(.init(
                                markdown: text,
                                renderMarkdown: text,
                                kind: guessKind(text, inCodeBlock: false),
                                isUnclosedCodeBlock: false
                            ))
                        }
                        currentBlockLines.removeAll()
                    }
                    inCodeBlock = true
                    codeBlockFence = String(trimmed.prefix(3))
                    currentBlockLines.append(line)
                } else if trimmed.isEmpty {
                    // 通常テキスト中の空行でブロック区切り
                    if !currentBlockLines.isEmpty {
                        let text = currentBlockLines.joined(separator: "\n")
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            blocks.append(.init(
                                markdown: text,
                                renderMarkdown: text,
                                kind: guessKind(text, inCodeBlock: false),
                                isUnclosedCodeBlock: false
                            ))
                        }
                        currentBlockLines.removeAll()
                    }
                } else {
                    currentBlockLines.append(line)
                }
            } else {
                // コードブロック内部
                currentBlockLines.append(line)
                if isFencePrefix && trimmed.hasPrefix(codeBlockFence) {
                    // コードブロック終了
                    inCodeBlock = false
                    let text = currentBlockLines.joined(separator: "\n")
                    let render = dedent(text)
                    blocks.append(.init(
                        markdown: text,
                        renderMarkdown: render,
                        kind: .codeBlock,
                        isUnclosedCodeBlock: false
                    ))
                    currentBlockLines.removeAll()
                    codeBlockFence = ""
                }
            }
        }
        
        // 末尾の残りを処理
        if !currentBlockLines.isEmpty {
            let text = currentBlockLines.joined(separator: "\n")
            if inCodeBlock {
                // 未完了のコードブロック
                let renderMarkdown = dedent(text) + "\n" + (codeBlockFence.isEmpty ? "```" : codeBlockFence)
                blocks.append(.init(
                    markdown: text,
                    renderMarkdown: renderMarkdown,
                    kind: .codeBlock,
                    isUnclosedCodeBlock: true
                ))
            } else {
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let kind = guessKind(text, inCodeBlock: false)
                    let render = (kind == .codeBlock) ? dedent(text) : text
                    blocks.append(.init(
                        markdown: text,
                        renderMarkdown: render,
                        kind: kind,
                        isUnclosedCodeBlock: false
                    ))
                }
            }
        }
        
        return blocks
    }
    
    private static func leadingIndentCount(_ line: String) -> Int {
        let spaces = line.prefix(while: { $0 == " " || $0 == "\t" })
        return spaces.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }
    
    private static func dedent(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let nonEmpties = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !nonEmpties.isEmpty else { return text }
        let minIndent = nonEmpties.map { leadingIndentCount($0) }.min() ?? 0
        guard minIndent > 0 else { return text }
        return lines.map { line in
            let spaces = line.prefix(while: { $0 == " " || $0 == "\t" })
            if leadingIndentCount(String(spaces)) >= minIndent {
                return String(line.dropFirst(minIndent))
            }
            return line
        }.joined(separator: "\n")
    }
    
    private static func guessKind(_ markdown: String, inCodeBlock: Bool) -> StructuredText.BlockKind {
        if inCodeBlock {
            return .codeBlock
        }
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
            return .codeBlock
        }
        if trimmed.hasPrefix("#") {
            return .header
        }
        if trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ") || trimmed.hasPrefix("+ ") || 
            (trimmed.first?.isNumber == true && trimmed.contains(". ")) {
            return .list
        }
        if trimmed.contains("|") && trimmed.contains("-") && trimmed.contains("\n") {
            return .table
        }
        return .other
    }
}
