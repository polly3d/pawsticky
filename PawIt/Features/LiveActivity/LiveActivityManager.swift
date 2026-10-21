@preconcurrency import ActivityKit
import Foundation
import Core
import os

/// 便签 Live Activity 管理器——"钉便签到锁屏"的核心控制层。
///
/// 纯静态 API，不持有状态。所有状态来自 ActivityKit 运行时。
/// 无 `@MainActor` 约束——避免 Swift 6 将 Activity 值跨隔离域发送的编译错误。
///
/// 职责：
/// - 启动 Live Activity（pin）
/// - 更新内容（编辑便签后同步到锁屏）
/// - 结束 Activity（unpin）
/// - 查询当前钉住状态
/// - App 回前台时自动续期（12h 过期保护）
enum LiveActivityManager {

    private static let logger = Logger(subsystem: "com.pawit.app", category: "liveActivity")

    // MARK: - 查询

    /// 指定便签是否正在锁屏上钉着。
    static func isPinned(noteId: UUID) -> Bool {
        currentActivity(for: noteId) != nil
    }

    // MARK: - Pin（启动 Live Activity）

    /// 将便签钉到锁屏。如果已钉则更新内容。
    ///
    /// - Parameter activitiesEnabled: 授权探针，默认读系统真实状态，测试注入用。
    /// - Throws: `LiveActivityUnavailableError.activitiesDisabled`——Live Activities
    ///   被系统关闭（设置里关掉 / 低电量）。调用方必须把失败呈现给用户，不许再静默（C9）。
    static func pin(
        note: Note,
        items: [NoteItem],
        pet: PetProfile?,
        activitiesEnabled: () -> Bool = { ActivityAuthorizationInfo().areActivitiesEnabled }
    ) throws {
        guard activitiesEnabled() else {
            logger.warning("Live Activities 未授权，无法钉便签")
            throw LiveActivityUnavailableError.activitiesDisabled
        }

        let noteIdStr = note.id.uuidString
        let state = makeContentState(note: note, items: items)

        // 已有 Activity → 更新
        if let existing = currentActivity(for: note.id) {
            Task {
                await existing.update(
                    ActivityContent(state: state, staleDate: staleDate())
                )
            }
            logger.info("更新已钉便签 Live Activity: \(noteIdStr)")
            return
        }

        // 新建 Activity
        let attributes = NoteActivityAttributes(
            noteId: noteIdStr,
            petSpecies: pet?.species.rawValue ?? "cat",
            petName: pet.map { PetAsset.displayName(species: $0.species) } ?? "PawSticky"
        )
        let content = ActivityContent(state: state, staleDate: staleDate())

        _ = try Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
        logger.info("钉便签到锁屏: \(noteIdStr)")
    }

    // MARK: - Unpin（结束 Live Activity）

    /// 从锁屏取消钉住。
    static func unpin(noteId: UUID) {
        guard let activity = currentActivity(for: noteId) else { return }
        let finalContent = ActivityContent(
            state: activity.content.state, staleDate: .now
        )
        Task {
            await activity.end(finalContent, dismissalPolicy: .immediate)
        }
        logger.info("取消钉住: \(noteId.uuidString)")
    }

    /// 取消所有钉住。
    static func unpinAll() {
        for activity in Activity<NoteActivityAttributes>.activities {
            let finalContent = ActivityContent(
                state: activity.content.state, staleDate: .now
            )
            Task {
                await activity.end(finalContent, dismissalPolicy: .immediate)
            }
        }
        logger.info("取消所有钉住")
    }

    // MARK: - Update（便签编辑后同步到锁屏）

    /// 便签内容变更后，同步更新锁屏显示。
    static func updateIfPinned(note: Note, items: [NoteItem]) {
        guard let activity = currentActivity(for: note.id) else { return }
        let state = makeContentState(note: note, items: items)
        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: staleDate())
            )
        }
        logger.debug("同步更新钉住便签: \(note.id.uuidString)")
    }

    // MARK: - Refresh / Renew（App 回前台）

    /// App 回到前台时调用：对全部钉住便签做「补刷 + 续期」。
    /// * **active**：内容可能已被 widget intent 改脏（平台限制：Live Activity
    ///   只能由主 App 进程更新，widget 勾选无法实时刷新锁屏）——用库内最新
    ///   数据补刷，消除「widget 勾了、锁屏没划线」的可见不一致。
    /// * **stale/ended**：结束旧的并按最新数据重新 pin（12h 过期保护续期）。
    static func handleAppForeground() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        for activity in Activity<NoteActivityAttributes>.activities {
            let noteIdStr = activity.attributes.noteId
            guard let noteId = UUID(uuidString: noteIdStr) else { continue }

            switch activity.activityState {
            case .stale, .ended:
                guard let repo = NoteRepository.cachedAppGroup(),
                      let note = try? repo.note(id: noteId)
                else { continue }
                let items = (try? repo.noteItems(noteId: noteId)) ?? []
                let pet = try? SharedStore.cachedAppGroup()?.selectedPet()

                let finalContent = ActivityContent(
                    state: activity.content.state, staleDate: .now
                )
                Task {
                    await activity.end(finalContent, dismissalPolicy: .immediate)
                    try? Self.pin(note: note, items: items, pet: pet)
                }
                logger.info("自动续期钉住便签: \(noteIdStr)")
            default:
                refreshFromStore(noteId: noteId)
            }
        }
    }

    /// 用库内最新数据补刷指定便签的锁屏内容（未钉住则无操作）。
    /// 变更后同步锁屏的唯一入口——由 `NoteChangeCoordinator` 在每次便签
    /// 变更后调用，App 各调用点不再各自手抄读取逻辑。
    static func refreshFromStore(noteId: UUID) {
        guard currentActivity(for: noteId) != nil,
              let repo = NoteRepository.cachedAppGroup(),
              let note = try? repo.note(id: noteId)
        else { return }
        let items = (try? repo.noteItems(noteId: noteId)) ?? []
        updateIfPinned(note: note, items: items)
    }

    // MARK: - Private

    private static func currentActivity(
        for noteId: UUID
    ) -> Activity<NoteActivityAttributes>? {
        let idStr = noteId.uuidString
        return Activity<NoteActivityAttributes>.activities.first {
            $0.attributes.noteId == idStr && $0.activityState == .active
        }
    }

    private static func makeContentState(
        note: Note, items: [NoteItem]
    ) -> NoteActivityAttributes.ContentState {
        NoteActivityAttributes.ContentState(
            noteText: note.text,
            items: items.map { .init(text: $0.text, done: $0.done) },
            noteStyle: note.style,
            isDone: note.done
        )
    }

    /// 12 小时后标记为 stale。
    private static func staleDate() -> Date {
        Date.now.addingTimeInterval(12 * 3600)
    }
}
