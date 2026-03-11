import Foundation

extension CodebaseIndex {
    /// Extracts code segments from indexed files for RAG retrieval
    /// Segments are high-signal code snippets (functions, classes, important blocks)
    public func extractSegments(from filePath: String, maxSegments: Int = 10) async throws -> [CodeSegment] {
        guard let fileContent = try? readIndexedFile(path: filePath) else {
            return []
        }
        
        let lines = fileContent.components(separatedBy: .newlines)
        var segments: [CodeSegment] = []
        
        // Extract function/method definitions
        segments.append(contentsOf: extractFunctionSegments(lines: lines, filePath: filePath))
        
        // Extract class/struct/enum definitions
        segments.append(contentsOf: extractTypeSegments(lines: lines, filePath: filePath))
        
        // Extract significant code blocks (if/switch/for with multiple lines)
        segments.append(contentsOf: extractBlockSegments(lines: lines, filePath: filePath))
        
        // Sort by significance and limit
        return Array(segments.sorted { $0.significance > $1.significance }.prefix(maxSegments))
    }
    
    /// Search for code segments matching a query
    /// Note: Simplified implementation for now - in production would use proper file indexing
    public func searchSegments(query: String, limit: Int = 20) async -> [CodeSegment] {
        // Simplified: return empty for now
        // Full implementation would query indexed files from database
        return []
    }
    
    // MARK: - Private Helpers
    
    private func extractFunctionSegments(lines: [String], filePath: String) -> [CodeSegment] {
        var segments: [CodeSegment] = []
        var currentFunction: (start: Int, name: String, lines: [String])? = nil
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Detect function start (Swift/Python/JS patterns)
            if trimmed.contains("func ") || trimmed.contains("def ") || 
               trimmed.contains("function ") || trimmed.contains("const ") && trimmed.contains("=>") {
                
                if let existing = currentFunction {
                    // Save previous function
                    segments.append(CodeSegment(
                        filePath: filePath,
                        lineStart: existing.start,
                        lineEnd: index - 1,
                        content: existing.lines.joined(separator: "\n"),
                        segmentType: .function,
                        name: existing.name,
                        significance: calculateFunctionSignificance(lines: existing.lines)
                    ))
                }
                
                currentFunction = (start: index, name: extractFunctionName(line: trimmed), lines: [line])
            } else if currentFunction != nil {
                currentFunction?.lines.append(line)
                
                // End function on closing brace at same indentation
                if trimmed == "}" && currentFunction!.lines.count > 1 {
                    segments.append(CodeSegment(
                        filePath: filePath,
                        lineStart: currentFunction!.start,
                        lineEnd: index,
                        content: currentFunction!.lines.joined(separator: "\n"),
                        segmentType: .function,
                        name: currentFunction!.name,
                        significance: calculateFunctionSignificance(lines: currentFunction!.lines)
                    ))
                    currentFunction = nil
                }
            }
        }
        
        return segments
    }
    
    private func extractTypeSegments(lines: [String], filePath: String) -> [CodeSegment] {
        var segments: [CodeSegment] = []
        var currentType: (start: Int, name: String, lines: [String], braceCount: Int)? = nil
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Detect type definition
            if trimmed.hasPrefix("class ") || trimmed.hasPrefix("struct ") || 
               trimmed.hasPrefix("enum ") || trimmed.hasPrefix("protocol ") ||
               trimmed.hasPrefix("interface ") {
                
                currentType = (start: index, name: extractTypeName(line: trimmed), lines: [line], braceCount: 0)
            } else if var current = currentType {
                current.lines.append(line)
                
                // Track brace depth
                current.braceCount += line.filter { $0 == "{" }.count
                current.braceCount -= line.filter { $0 == "}" }.count
                
                currentType = current
                
                // End type when braces balance
                if current.braceCount == 0 && current.lines.count > 1 {
                    segments.append(CodeSegment(
                        filePath: filePath,
                        lineStart: current.start,
                        lineEnd: index,
                        content: current.lines.joined(separator: "\n"),
                        segmentType: .type,
                        name: current.name,
                        significance: calculateTypeSignificance(lines: current.lines)
                    ))
                    currentType = nil
                }
            }
        }
        
        return segments
    }
    
    private func extractBlockSegments(lines: [String], filePath: String) -> [CodeSegment] {
        // Extract significant control flow blocks (simplified for now)
        // In production, this would use proper AST parsing
        return []
    }
    
    private func extractFunctionName(line: String) -> String {
        // Extract function name from declaration
        if let funcRange = line.range(of: "func ") {
            let afterFunc = line[funcRange.upperBound...]
            if let parenIndex = afterFunc.firstIndex(of: "(") {
                return String(afterFunc[..<parenIndex]).trimmingCharacters(in: .whitespaces)
            }
        }
        
        if let defRange = line.range(of: "def ") {
            let afterDef = line[defRange.upperBound...]
            if let parenIndex = afterDef.firstIndex(of: "(") {
                return String(afterDef[..<parenIndex]).trimmingCharacters(in: .whitespaces)
            }
        }
        
        return "unknown"
    }
    
    private func extractTypeName(line: String) -> String {
        let keywords = ["class ", "struct ", "enum ", "protocol ", "interface "]
        for keyword in keywords {
            if let range = line.range(of: keyword) {
                let afterKeyword = line[range.upperBound...]
                let components = afterKeyword.components(separatedBy: CharacterSet(charactersIn: " :{<"))
                if let name = components.first?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                    return name
                }
            }
        }
        return "unknown"
    }
    
    private func calculateFunctionSignificance(lines: [String]) -> Double {
        var score = 0.5 // Base score
        
        // Longer functions are more significant (up to a point)
        let lineCount = lines.count
        if lineCount > 5 { score += 0.1 }
        if lineCount > 10 { score += 0.1 }
        if lineCount > 20 { score += 0.1 }
        
        // Functions with documentation are more significant
        if lines.first?.contains("///") == true || lines.first?.contains("/**") == true {
            score += 0.2
        }
        
        return min(score, 1.0)
    }
    
    private func calculateTypeSignificance(lines: [String]) -> Double {
        var score = 0.6 // Types generally more significant than functions
        
        // Public types are more significant
        if lines.first?.contains("public ") == true {
            score += 0.2
        }
        
        // Types with documentation are more significant
        if lines.first?.contains("///") == true || lines.first?.contains("/**") == true {
            score += 0.2
        }
        
        return min(score, 1.0)
    }
    
    private func calculateSegmentRelevance(segment: CodeSegment, query: String) -> Double {
        let queryLower = query.lowercased()
        let contentLower = segment.content.lowercased()
        let nameLower = segment.name.lowercased()
        
        var score = 0.0
        
        // Name match is highly relevant
        if nameLower.contains(queryLower) {
            score += 0.5
        }
        
        // Content match
        if contentLower.contains(queryLower) {
            score += 0.3
        }
        
        // Boost by segment significance
        score += segment.significance * 0.2
        
        return score
    }
}

// MARK: - Models

public struct CodeSegment: Sendable {
    public let filePath: String
    public let lineStart: Int
    public let lineEnd: Int
    public let content: String
    public let segmentType: SegmentType
    public let name: String
    public let significance: Double
    
    public enum SegmentType: String, Sendable {
        case function
        case type
        case block
    }
}
