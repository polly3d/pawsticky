import AppIntents
import Foundation

/// Widget 内勾选（W5-0 升级版）：翻转当前展示便签的 done 标记。
///
/// W1 PoC 版 toggleFirstItem → W5 按 WidgetPreferences.currentNoteIndex 定位目标便签。
/// Widget 进程直写 SharedStore（不走 NoteRepository、不落历史——W2-4 移交项④既定决策）。
public struct ToggleItemIntent: AppIntent {
    public static let title: LocalizedStringResource = "Toggle Note"
    public static let description: IntentDescription = "Mark the current note as done or not done"

    public init() {}

    public func perform() async throws -> some IntentResult {
        guard let store = SharedStore.cachedAppGroup() else {
            throw SharedStoreError.appGroupContainerUnavailable(PawItInfo.appGroupID)
        }

        let notes = try store.allNotes()
        guard !notes.isEmpty else { return .result() }

        let index = WidgetPreferences.clampedIndex(noteCount: notes.count)
        let targetNote = notes[index]

        let nowDone = try await store.toggleNote(id: targetNote.id)

        // 与 App 内勾选同一喂养语义(P0-5):widget 完成便签同样喂养宠物——
        // 此前 growth 只在 App 前台路径生效,跨表面语义分叉。
        // 喂养走 store.feedPet 单事务原子读-改-写,与 App 前台并发不丢更新;
        // 喂养失败不拖垮勾选(try?)。锁屏 Live Activity 平台限制只能由主 App
        // 进程更新——App 回前台时 handleAppForeground 会补刷。
        if nowDone, GrowthSettings.isEnabled,
           let pet = try? store.selectedPet() {
            // 返回的 GrowthState 在这里用不上，显式丢弃（与 App 内 NoteListView 的同类调用一致）。
            _ = try? await store.feedPet(petId: pet.id)
        }
        return .result()
    }
}
