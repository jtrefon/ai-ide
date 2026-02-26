import SwiftUI
import Foundation

struct PlanOutlineView: View {
    let rawPlan: String
    var fontSize: Double
    var fontFamily: String

    @State private var expandedSectionTitles: Set<String> = []

    private var sections: [PlanSection] {
        PlanOutlineParser.parse(rawPlan)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sections.isEmpty {
                Text(rawPlan)
                    .font(.system(size: CGFloat(max(10, fontSize - 1))))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(sections) { section in
                    DisclosureGroup(
                        isExpanded: binding(for: section.title),
                        content: {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(section.steps.enumerated()), id: \.offset) { _, step in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(step.title)
                                            .font(.system(size: CGFloat(max(10, fontSize - 1)), weight: .medium))
                                            .foregroundColor(.primary)

                                        if !step.substeps.isEmpty {
                                            VStack(alignment: .leading, spacing: 2) {
                                                ForEach(Array(step.substeps.enumerated()), id: \.offset) { _, substep in
                                                    Text("• \(substep)")
                                                        .font(.system(size: CGFloat(max(9, fontSize - 2))))
                                                        .foregroundColor(.secondary)
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                }
                                            }
                                            .padding(.leading, 8)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.top, 4)
                        },
                        label: {
                            Text(section.title)
                                .font(.system(size: CGFloat(max(11, fontSize - 1)), weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    )
                }
            }
        }
        .onAppear {
            expandedSectionTitles = Set(sections.map(\.title))
        }
    }

    private func binding(for sectionTitle: String) -> Binding<Bool> {
        Binding(
            get: { expandedSectionTitles.contains(sectionTitle) },
            set: { isExpanded in
                if isExpanded {
                    expandedSectionTitles.insert(sectionTitle)
                } else {
                    expandedSectionTitles.remove(sectionTitle)
                }
            }
        )
    }
}

private struct PlanStep {
    let title: String
    let substeps: [String]
}

private struct PlanSection: Identifiable {
    let id = UUID()
    let title: String
    let steps: [PlanStep]
}

private enum PlanOutlineParser {
    static func parse(_ rawPlan: String) -> [PlanSection] {
        let lines = rawPlan
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }

        var sections: [PlanSection] = []
        var currentSectionTitle = "Plan"
        var currentSteps: [PlanStep] = []
        var currentStepTitle: String?
        var currentSubsteps: [String] = []

        func flushStep() {
            guard let currentStepTitle, !currentStepTitle.isEmpty else { return }
            currentSteps.append(PlanStep(title: currentStepTitle, substeps: currentSubsteps))
            currentSubsteps = []
        }

        func flushSection() {
            flushStep()
            guard !currentSteps.isEmpty else { return }
            sections.append(PlanSection(title: currentSectionTitle, steps: currentSteps))
            currentSteps = []
            currentStepTitle = nil
            currentSubsteps = []
        }

        for line in lines {
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#") {
                let title = line.trimmingCharacters(in: CharacterSet(charactersIn: "#")).trimmingCharacters(in: .whitespaces)
                flushSection()
                currentSectionTitle = title.isEmpty ? "Plan" : title
                continue
            }

            if isNumberedStep(line) {
                flushStep()
                currentStepTitle = stripNumbering(from: line)
                continue
            }

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                let substep = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if currentStepTitle == nil {
                    currentStepTitle = substep
                } else {
                    currentSubsteps.append(substep)
                }
                continue
            }

            if currentStepTitle == nil {
                currentStepTitle = line
            } else {
                currentSubsteps.append(line)
            }
        }

        flushSection()
        return sections
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
            return false
        }
        return false
    }

    private static func stripNumbering(from line: String) -> String {
        guard let dotIndex = line.firstIndex(of: ".") else { return line }
        return String(line[line.index(after: dotIndex)...]).trimmingCharacters(in: .whitespaces)
    }
}
