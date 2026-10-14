import SwiftUI

/// 删除后的撤销条：持有撤销所需的全部信息。
///
/// 清单项 id 必须在**删除前**读出来放进这里——历史按实体存、不记父子关系，
/// `NoteRepository.undoDeleteNote` 要靠这份 id 列表才能把清单项一并找回。
struct PendingUndo: Identifiable, Equatable {
    let id = UUID()
    let noteId: UUID
    let itemIds: [UUID]
}

/// 屏幕底部的 “Note deleted · Undo” 小条（几秒后由调用方自动收起）。
struct UndoBanner: View {
    let message: LocalizedStringKey
    let actionTitle: LocalizedStringKey
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.white)

            Spacer(minLength: 8)

            Button(action: onAction) {
                Text(actionTitle)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(.vertical, 4)
                    .padding(.leading, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .fill(Color.black.opacity(0.85))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        )
        .accessibilityElement(children: .contain)
    }
}
