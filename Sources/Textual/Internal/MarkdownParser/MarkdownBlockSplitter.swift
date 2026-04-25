import Foundation

extension StructuredText {
    struct BlockInfo: Equatable, Sendable {
        let markdown: String
        let kind: BlockKind
    }
    
    enum BlockKind: Sendable {
        case list, table, header, other
    }
}

enum MarkdownBlockSplitter {
    static func split(_ markdown: String) -> [StructuredText.BlockInfo] {
        var blocks: [StructuredText.BlockInfo] = []
        var currentBlock = ""
        var inCodeBlock = false
        
        let lines = markdown.components(separatedBy: "\n")
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCodeBlock.toggle()
            }
            
            if trimmed.isEmpty && !inCodeBlock {
                if !currentBlock.isEmpty {
                    blocks.append(.init(markdown: currentBlock, kind: guessKind(currentBlock)))
                    currentBlock = ""
                }
            } else {
                if !currentBlock.isEmpty {
                    currentBlock += "\n"
                }
                currentBlock += line
            }
        }
        
        if !currentBlock.isEmpty {
            blocks.append(.init(markdown: currentBlock, kind: guessKind(currentBlock)))
        }
        
        return blocks
    }
    
    private static func guessKind(_ markdown: String) -> StructuredText.BlockKind {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
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
