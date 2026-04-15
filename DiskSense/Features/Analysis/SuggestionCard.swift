import SwiftUI
import AppKit

struct SuggestionCard: View {
    @Binding var suggestion: AISuggestion
    @State private var hovering = false

    private var riskColor: Color {
        switch suggestion.risk {
        case .safe: return .green
        case .caution: return .yellow
        case .danger: return .red
        }
    }

    private var riskLabel: String {
        switch suggestion.risk {
        case .safe: return "안전"
        case .caution: return "주의"
        case .danger: return "위험"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Toggle("", isOn: $suggestion.isApproved)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(displayName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Circle().fill(riskColor).frame(width: 6, height: 6)
                        Text(riskLabel).font(.caption2).foregroundStyle(riskColor)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(riskColor.opacity(0.12), in: Capsule())
                    if suggestion.recoverable {
                        Text("복구 가능").font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.10), in: Capsule())
                    }
                    Spacer()
                    Text(ByteFormatter.string(suggestion.estimatedBytes))
                        .font(.callout.bold()).monospacedDigit()
                }

                Text(suggestion.reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(suggestion.targetPaths, id: \.self) { path in
                    Text(path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                }

                if hovering {
                    HStack(spacing: 10) {
                        Button("Finder에서 표시") {
                            if let first = suggestion.targetPaths.first {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: first)])
                            }
                        }.buttonStyle(.link).font(.caption)
                        Button("경로 복사") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(suggestion.targetPaths.joined(separator: "\n"), forType: .string)
                        }.buttonStyle(.link).font(.caption)
                    }
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(suggestion.isApproved ? riskColor.opacity(0.6) : .clear, lineWidth: 2)
        }
        .animation(.easeInOut(duration: 0.15), value: suggestion.isApproved)
        .onHover { hovering = $0 }
    }

    private var displayName: String {
        guard let first = suggestion.targetPaths.first else { return "항목" }
        let url = URL(fileURLWithPath: first)
        return url.lastPathComponent
    }
}
