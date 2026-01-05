import SwiftUI
import Foundation

struct CommandPaletteItem: Identifiable {
    let id: String
    let command: CommandID
    let title: String
    let subtitle: String
}

enum CommandPaletteScoring {
    static func score(candidate: String, query: String) -> Int {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if needle.isEmpty { return 0 }

        let hay = candidate.lowercased()
        if hay == needle { return 1_000 }
        if hay.hasPrefix(needle) { return 800 }
        if hay.contains(needle) { return 600 }

        // Substring match on last path component-ish segment (after '.')
        let lastSegment = hay.split(separator: ".").last.map(String.init) ?? hay
        if lastSegment == needle { return 700 }
        if lastSegment.hasPrefix(needle) { return 500 }
        if lastSegment.contains(needle) { return 350 }

        return 0
    }
}

struct CommandPaletteOverlayView: View {
    @Binding var isPresented: Bool

    @State private var query: String = ""
    @State private var items: [CommandPaletteItem] = []

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Command Palette")
                    .font(.headline)

                TextField("Type a command…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 520)
                    .onSubmit {
                        runFirstMatch()
                    }

                Button("Close") {
                    close()
                }
            }

            List {
                ForEach(items) { item in
                    Button(action: {
                        run(item.command)
                    }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .lineLimit(1)
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minWidth: 760, minHeight: 420)
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(12)
        .shadow(radius: 30)
        .onAppear {
            query = ""
            refreshItems()
        }
        .onChange(of: query) { _, _ in
            refreshItems()
        }
        .onExitCommand {
            close()
        }
    }

    private func refreshItems() {
        let all = CommandRegistry.shared.registeredCommandIDs()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            items = all.prefix(60).map { id in
                CommandPaletteItem(
                    id: id.value,
                    command: id,
                    title: prettyTitle(for: id.value),
                    subtitle: id.value
                )
            }
            return
        }

        var scored: [(CommandID, Int)] = []
        scored.reserveCapacity(all.count)

        for command in all {
            let s = CommandPaletteScoring.score(candidate: command.value, query: trimmed)
            if s > 0 {
                scored.append((command, s))
            }
        }

        scored.sort { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return a.0.value < b.0.value
        }

        items = scored.prefix(60).map { (cmd, _) in
            CommandPaletteItem(
                id: cmd.value,
                command: cmd,
                title: prettyTitle(for: cmd.value),
                subtitle: cmd.value
            )
        }
    }

    private func prettyTitle(for command: String) -> String {
        let parts = command.split(separator: ".")
        guard let last = parts.last else { return command }
        return last.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func runFirstMatch() {
        guard let first = items.first else { return }
        run(first.command)
    }

    private func run(_ command: CommandID) {
        Task {
            try? await CommandRegistry.shared.execute(command)
            close()
        }
    }

    private func close() {
        isPresented = false
        query = ""
        items = []
    }
}
