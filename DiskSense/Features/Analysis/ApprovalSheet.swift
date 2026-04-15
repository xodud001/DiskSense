import SwiftUI

struct ApprovalSheet: View {
    let suggestions: [AISuggestion]
    let mode: CleanupMode
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var approved: [AISuggestion] { suggestions.filter { $0.isApproved } }
    private var totalBytes: Int64 { approved.reduce(0) { $0 + $1.estimatedBytes } }
    private var totalPaths: Int { approved.reduce(0) { $0 + $1.targetPaths.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: mode == .permanent ? "exclamationmark.triangle.fill" : "trash.fill")
                    .font(.largeTitle)
                    .foregroundStyle(mode == .permanent ? .red : .orange)
                VStack(alignment: .leading) {
                    Text("최종 확인").font(.title2.bold())
                    Text(mode == .permanent ? "영구 삭제 (복구 불가)" : "휴지통으로 이동")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                row("정리할 항목", "\(totalPaths)개")
                row("절약 예상", ByteFormatter.string(totalBytes), bold: true)
            }

            if mode == .permanent {
                GroupBox {
                    Text("⚠️ 영구 삭제는 되돌릴 수 없습니다. 휴지통 모드를 권장합니다.")
                        .font(.callout).foregroundStyle(.red)
                }
            }

            HStack {
                Button("취소", role: .cancel, action: onCancel)
                Spacer()
                Button(mode == .permanent ? "영구 삭제" : "휴지통으로 이동", role: .destructive, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(approved.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold(bold).monospacedDigit()
        }
    }
}
