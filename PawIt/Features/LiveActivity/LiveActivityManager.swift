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

    /// 所有当前活跃的钉住便签 ID。
    static func pinnedNoteIDs() -> [String] {
        Activity<NoteActivityAttributes>.activities.map(\.attributes.noteId)
    }

    // MARK: - Pin（启动 Live Activity）

    /// 将便签钉到锁屏。如果已钉则更新内容。
    static func pin(note: Note, items: [NoteItem], pet: PetProfile?) throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.warning("Live Activities 未授权，无法钉便签")
            return
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
            petName: pet.map { PetAsset.displayName(species: $0.species) } ?? "PawIt"
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

    // MARK: - Renew（App 回前台时自动续期）

    /// App 回到前台时调用：检查已过期/stale 的 Activity，自动重新启动。
    static func renewIfNeeded() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let store = SharedStore.cachedAppGroup() else { return }

        for activity in Activity<NoteActivityAttributes>.activities {
            guard activity.activityState == .ended || activity.activityState == .stale
            else { continue }

            let noteIdStr = activity.attributes.noteId
            guard let noteId = UUID(uuidString: noteIdStr),
                  let notes = try? store.allNotes(),
                  let note = notes.first(where: { $0.id == noteId })
            else { continue }

            let items = (try? store.noteItems(noteId: noteId)) ?? []
            let pet = try? store.selectedPet()

            // 先结束旧的
            let finalContent = ActivityContent(
                state: activity.content.state, staleDate: .now
            )
            Task {
                await activity.end(finalContent, dismissalPolicy: .immediate)
                // 重新启动
                try? Self.pin(note: note, items: items, pet: pet)
            }
            logger.info("自动续期钉住便签: \(noteIdStr)")
        }
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
