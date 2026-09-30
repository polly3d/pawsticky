import AppIntents
import Foundation
import WidgetKit

/// Widget 内翻页（W5-1）：在便签间循环切换。
///
/// 点击后推进 WidgetPreferences.currentNoteIndex，Widget 重绘后显示下一条便签。
/// 到最后一条后循环回第一条。
public struct CycleNoteIntent: AppIntent {
    public static let title: LocalizedStringResource = "Next Note"
    public static let description: IntentDescription = "Show the next note in the widget"

    public init() {}

    public func perform() async throws -> some IntentResult {
        guard let store = SharedStore.cachedAppGroup() else {
            throw SharedStoreError.appGroupContainerUnavailable(PawItInfo.appGroupID)
        }

        let count = try store.countNotes()
        WidgetPreferences.advanceToNextNote(noteCount: count)

        return .result()
    }
}
