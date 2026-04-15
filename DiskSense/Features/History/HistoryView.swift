import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \CleanupHistory.executedAt, order: .reverse) private var history: [CleanupHistory]
    @Environment(\.modelContext) private var modelContext
    @State private var selected: CleanupHistory?

    private var totalFreed: Int64 { history.reduce(0) { $0 + $1.totalSizeFreed } }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if history.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 40)).foregroundStyle(.tertiary)
                        Text("아직 정리 기록이 없습니다").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    List(selection: $selected) {
                        ForEach(history) { h in
                            HistoryRow(entry: h).tag(h)
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 340)

            if let s = selected {
                HistoryDetailView(entry: s)
            } else {
                VStack {
                    Text("항목을 선택하세요").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("히스토리").font(.system(size: 28, weight: .bold, design: .rounded))
            Text("총 \(ByteFormatter.string(totalFreed)) 정리됨 · \(history.count)회 실행")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets { modelContext.delete(history[i]) }
        try? modelContext.save()
    }
}

private struct HistoryRow: View {
    let entry: CleanupHistory
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.executedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.callout.weight(.medium))
                Text("\(entry.itemCount)개 항목").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(ByteFormatter.string(entry.totalSizeFreed))
                .font(.callout.bold()).foregroundStyle(.green).monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

struct HistoryDetailView: View {
    let entry: CleanupHistory

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(entry.executedAt.formatted(date: .complete, time: .standard))
                    .font(.title3.bold())
                HStack(spacing: 20) {
                    stat("절약된 용량", ByteFormatter.string(entry.totalSizeFreed))
                    stat("정리 항목 수", "\(entry.itemCount)")
                }
                Divider()
                Text("정리 내역").font(.headline)
                ForEach(entry.suggestions) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.targetPaths.first ?? "—").font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                        Text(s.reason).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial))
                }
            }
            .padding(20)
        }
        .frame(minWidth: 380)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
        }
    }
}
