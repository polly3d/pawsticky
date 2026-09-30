import SwiftUI
import Core

@main
struct PawItWatchApp: App {
    /// Watch 端 WCSession 管理器（App 生命周期持有）。
    private let sessionManager = WatchSessionManager.shared

    init() {
        sessionManager.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchNoteListView()
        }
    }
}

// MARK: - Watch 便签列表（只读镜像）

/// Watch 主界面——显示从 iPhone 同步来的便签。
struct WatchNoteListView: View {
    @State private var payload: WatchPayload?

    var body: some View {
        NavigationStack {
            Group {
                if let payload, !payload.notes.isEmpty {
                    noteList(payload)
                } else {
                    emptyState
                }
            }
            .navigationTitle("PawIt")
        }
        .task { loadPayload() }
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
                        let done = note.items.filter(\.done).count
                        Text("\(done)/\(note.items.count) items")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "pawprint.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Open PawIt on iPhone")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Notes sync automatically")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func loadPayload() {
        payload = WatchSessionManager.cachedPayload()
    }
}
