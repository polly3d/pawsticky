import SwiftUI
import Core

@main
struct PawItWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase

    /// Watch 端 WCSession 管理器（App 生命周期持有）。
    private let sessionManager = WatchSessionManager.shared

    init() {
        sessionManager.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchNoteListView(store: sessionManager.store)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // 每次回到前台都向 iPhone 要一份最新快照：推送可能在手表 App 不在场时被错过
            // （App Review 2.1(a)：手表端晚于便签装好，没人补推，手表上永远是空的）。
            if newPhase == .active { sessionManager.requestSnapshot() }
        }
    }
}

// MARK: - Watch 便签列表（只读镜像）

/// Watch 主界面——显示从 iPhone 同步来的便签。
///
/// 读的是可观察的 `store`：快照什么时候到（冷启动后、后台推送、主动拉取的应答），界面就什么时候重绘。
/// 此前这里只在 `.task` 里读一次 UserDefaults，数据落盘后界面依然停在空状态。
struct WatchNoteListView: View {
    let store: WatchSnapshotStore

    var body: some View {
        NavigationStack {
            Group {
                if let payload = store.payload, !payload.notes.isEmpty {
                    noteList(payload)
                } else {
                    emptyState(synced: store.payload != nil)
                }
            }
            .navigationTitle("PawSticky")
        }
    }

    private func noteList(_ payload: WatchPayload) -> some View {
        List {
            if let pet = payload.selectedPet {
                HStack(spacing: 8) {
                    Image("pet-\(pet.species)-front")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30, height: 30)
                    Text(pet.displayName)
                        .font(.caption.bold())
                }
                .listRowBackground(Color.clear)
            }

            ForEach(payload.notes, id: \.id) { note in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(note.text.isEmpty ? "Untitled" : note.text)
                            .font(.subheadline)
                            .lineLimit(2)
                            .strikethrough(note.done)
                            .foregroundStyle(note.done ? .secondary : .primary)
                        Spacer()
                        if note.done {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }

                    if !note.items.isEmpty {
                        Text("\(note.items.doneCount)/\(note.items.count) items")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// - Parameter synced: 已经收到过 iPhone 的快照。区分两种空：
    ///   还没同步过（等同步）≠ 同步过了、iPhone 上确实一条便签都没有——
    ///   后者再说「Open PawSticky on iPhone」会让人以为同步坏了。
    private func emptyState(synced: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "pawprint.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(synced ? "No notes yet" : "Open PawSticky on iPhone")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(synced ? "Add one on iPhone" : "Notes sync automatically")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
