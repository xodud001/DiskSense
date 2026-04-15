import SwiftUI
import AppKit

struct TopItemsView: View {
    let items: [DiskItem]
    let filter: StorageCategory?
    let maxCount: Int

    private var filtered: [DiskItem] {
        let base = filter.map { f in items.filter { $0.category == f } } ?? items
        return Array(base.prefix(maxCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if filtered.isEmpty {
                Text("표시할 항목이 없습니다")
                    .font(.caption).foregroundStyle(.secondary).padding()
            } else {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, item in
                    ItemRow(item: item, rank: idx + 1)
                    if idx < filtered.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        }
    }
}

private struct ItemRow: View {
    let item: DiskItem
    let rank: Int
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 24, alignment: .trailing)

            ZStack {
                Circle()
                    .fill(item.category.color.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: item.category.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(item.category.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(contextLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteFormatter.string(item.sizeBytes))
                    .font(.callout.bold())
                    .monospacedDigit()
                Text(item.category.displayName)
                    .font(.caption2)
                    .foregroundStyle(item.category.color)
            }

            if hovering {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
                } label: {
                    Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Finder에서 표시")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(hovering ? Color.secondary.opacity(0.08) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Finder에서 표시") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            }
            Button("경로 복사") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.path, forType: .string)
            }
        }
    }

    private var contextLine: String {
        let relModified = item.modifiedDate.formatted(.relative(presentation: .named))
        var parts = [relModified, item.path]
        if item.isDirectory {
            parts.insert("폴더", at: 0)
        }
        return parts.joined(separator: " · ")
    }
}
