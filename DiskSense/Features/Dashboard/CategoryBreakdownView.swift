import SwiftUI

struct CategoryCard: View {
    let category: StorageCategory
    let bytes: Int64
    let totalBytes: Int64
    let isSelected: Bool
    let onTap: () -> Void

    private var percentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytes) / Double(totalBytes)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: category.systemImage)
                        .foregroundStyle(category.color)
                        .font(.system(size: 18, weight: .medium))
                    Text(category.displayName)
                        .font(.callout.weight(.medium))
                    Spacer()
                }
                Text(ByteFormatter.string(bytes))
                    .font(.title2.bold())
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.primary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(category.color.gradient)
                            .frame(width: geo.size.width * percentage, height: 6)
                    }
                }
                .frame(height: 6)
                Text("\(Int(percentage * 100))% of used")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? category.color : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

struct CategoryBreakdownView: View {
    let breakdown: [StorageCategory: Int64]
    let total: Int64
    @Binding var selected: StorageCategory?

    private var entries: [(StorageCategory, Int64)] {
        breakdown
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { ($0.key, $0.value) }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 12),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(entries, id: \.0) { (cat, bytes) in
                CategoryCard(
                    category: cat,
                    bytes: bytes,
                    totalBytes: total,
                    isSelected: selected == cat,
                    onTap: { selected = (selected == cat) ? nil : cat }
                )
            }
        }
    }
}
