import SwiftUI

struct AgentFeedView: View {
    let events: [AgentEvent]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(events) { event in
                        EventRow(event: event).id(event.id)
                    }
                    Color.clear.frame(height: 1).id("BOTTOM")
                }
                .padding(16)
            }
            .onChange(of: events.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("BOTTOM", anchor: .bottom)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 14).fill(.regularMaterial)
        }
    }
}

private struct EventRow: View {
    let event: AgentEvent

    var body: some View {
        switch event {
        case .thinking(_, let text):
            label(icon: "bubble.left.fill", color: .blue, title: "추론", body: text)
        case .toolCall(_, let name, let args):
            label(icon: "wrench.and.screwdriver.fill", color: .orange,
                  title: name, body: args, monospace: true, dimBody: true)
        case .toolResult(_, _, let summary, let isError):
            label(icon: isError ? "xmark.circle.fill" : "checkmark.circle.fill",
                  color: isError ? .red : .green,
                  title: isError ? "실패" : "결과", body: summary, monospace: true, dimBody: true)
        case .proposal(_, let s):
            proposalCard(s)
        case .finished(_, let text):
            label(icon: "flag.checkered", color: .purple, title: "완료", body: text)
        case .error(_, let message):
            label(icon: "exclamationmark.triangle.fill", color: .red, title: "에러", body: message)
        }
    }

    @ViewBuilder
    private func label(icon: String, color: Color, title: String, body: String,
                       monospace: Bool = false, dimBody: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).font(.system(size: 14))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(color)
                Text(body)
                    .font(monospace ? .caption.monospaced() : .callout)
                    .foregroundStyle(dimBody ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func proposalCard(_ s: AISuggestion) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill").foregroundStyle(.yellow).font(.system(size: 14))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("제안 추가").font(.caption.weight(.semibold)).foregroundStyle(.yellow)
                    Spacer()
                    Text(ByteFormatter.string(s.estimatedBytes))
                        .font(.callout.bold()).monospacedDigit()
                }
                Text(s.targetPaths.first ?? "")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Text(s.reason).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.08)))
    }
}
