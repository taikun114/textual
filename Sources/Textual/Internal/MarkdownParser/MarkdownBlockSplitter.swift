import Foundation

enum MarkdownBlockSplitter {
    static func split(_ markdown: String) -> [String] {
        var blocks: [String] = []
        var currentBlock = ""
        var inCodeBlock = false
        
        // Use a simple scanner to find blocks while respecting code blocks
        let lines = markdown.components(separatedBy: "\n")
        
        for line in lines {
            // Check for code block toggle
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCodeBlock.toggle()
            }
            
            // Split at empty line if not in a code block
            if trimmed.isEmpty && !inCodeBlock {
                if !currentBlock.isEmpty {
                    blocks.append(currentBlock)
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
            blocks.append(currentBlock)
        }
        
        return blocks
    }
}
