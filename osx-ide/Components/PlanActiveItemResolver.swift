import Foundation

struct PlanActiveItem {
    let stepTitle: String
    let substepTitle: String?
}

enum PlanActiveItemResolver {
    static func activeItem(in rawPlan: String) -> PlanActiveItem? {
        let lines = rawPlan
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }

        var currentStepTitle: String?
        var firstStepTitle: String?

        func activeItem(from line: String) -> PlanActiveItem? {
            guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
            let content = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)

            if content.lowercased().hasPrefix("[x]") {
                return nil
            }

            guard content.hasPrefix("[ ]") else { return nil }
            let substep = content.dropFirst(3).trimmingCharacters(in: .whitespaces)
            let normalizedSubstep = substep.isEmpty ? nil : substep
            if let currentStepTitle {
                return PlanActiveItem(
                    stepTitle: currentStepTitle,
                    substepTitle: normalizedSubstep
                )
            } else {
                return PlanActiveItem(
                    stepTitle: normalizedSubstep ?? "Implementation Plan",
                    substepTitle: nil
                )
            }
        }

        for line in lines {
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#") {
                continue
            }

            if isNumberedStep(line) {
                let title = stripNumbering(from: line)
                if firstStepTitle == nil {
                    firstStepTitle = title
                }
                currentStepTitle = title
                continue
            }

            if let item = activeItem(from: line) {
                return item
            }
        }

        if let firstStepTitle {
            return PlanActiveItem(stepTitle: firstStepTitle, substepTitle: nil)
        }

        return nil
    }

    private static func isNumberedStep(_ line: String) -> Bool {
        var foundDigit = false
        for character in line {
            if character.isNumber {
                foundDigit = true
                continue
            }
            if foundDigit && character == "." {
                return true
            }
            if foundDigit && !character.isWhitespace {
                return false
            }
        }
        return false
    }

    private static func stripNumbering(from line: String) -> String {
        guard let dotIndex = line.firstIndex(of: ".") else { return line }
        let afterDot = line.index(after: dotIndex)
        return line[afterDot...].trimmingCharacters(in: .whitespaces)
    }
}
