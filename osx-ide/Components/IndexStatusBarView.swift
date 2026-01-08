import SwiftUI

struct IndexStatusBarView: View {
    @StateObject private var viewModel: IndexStatusBarViewModel

    init(codebaseIndexProvider: @escaping () -> CodebaseIndexProtocol?, eventBus: EventBusProtocol) {
        self._viewModel = StateObject(wrappedValue: IndexStatusBarViewModel(codebaseIndexProvider: codebaseIndexProvider, eventBus: eventBus))
    }

    @State private var isShowingMetricsInfo: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if viewModel.isIndexing {
                ProgressView()
                    .controlSize(.small)
            }

            Text(viewModel.statusText)
                .font(.caption)
                .lineLimit(1)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Text(viewModel.metricsText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Button {
                    isShowingMetricsInfo.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isShowingMetricsInfo, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Index Metrics")
                            .font(.headline)
                        Text("C = Classes")
                        Text("F = Functions")
                        Text("S = Total symbols")
                        Text("Q = Average quality score (0-100)")
                        Text("M = Memories (LT = Long-term)")
                        Text("DB = Database size")
                    }
                    .padding(12)
                    .frame(width: 260)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .top
        )
    }
}
