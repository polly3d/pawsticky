import Testing
import Foundation
import Observation
import os
@testable import Core

/// 手表端「快照仓」的行为钉子——App Review 2.1(a)「手表不同步便签」的回归测试。
///
/// 当时的现场（模拟器复现，见 `docs/launch-todo.md`）：快照已经到达并落盘，
/// 手表界面却仍停在「Open PawSticky on iPhone」——界面只在启动时读一次缓存，
/// 之后到达的数据谁也没通知它。所以这里守两件事：
/// 1. 快照到达后，界面依赖的状态**必须可观察**（不然 SwiftUI 不会重绘）；
/// 2. 乱序到达时，旧快照不能盖掉新快照（现在有 context 推送、消息应答、冷启动缓存三条来路）。
@MainActor
struct WatchSnapshotStoreTests {

    // MARK: - 夹具

    /// 每个用例独占一个 UserDefaults 域，互不污染。
    private func makeDefaults() -> UserDefaults {
        let name = "pawit-test-watchstore-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func payload(
        _ texts: [String], at seconds: TimeInterval, pet: String? = "cat"
    ) -> WatchPayload {
        WatchPayload(
            notes: texts.map {
                .init(id: UUID().uuidString, text: $0, done: false,
                      dueDate: nil, style: nil, items: [])
            },
            selectedPet: pet.map { .init(species: $0, displayName: "Tabby") },
            syncDate: Date(timeIntervalSinceReferenceDate: seconds)
        )
    }

    // MARK: - 启动

    @Test func startsEmptyWhenNothingWasEverSynced() {
        let store = WatchSnapshotStore(defaults: makeDefaults())
        #expect(store.payload == nil, "从没同步过 = nil，界面据此显示「等待同步」而不是「没有便签」")
    }

    @Test func startsFromTheCachedSnapshot() {
        let defaults = makeDefaults()
        let cached = payload(["牛奶"], at: 100)
        WatchSnapshotStore(defaults: defaults).apply(cached)

        // 手表 App 重启：第一帧就该有数据，不能再等一次同步
        #expect(WatchSnapshotStore(defaults: defaults).payload == cached)
    }

    // MARK: - 到达 → 界面（本次被拒的直接原因）

    @Test func arrivingSnapshotNotifiesObservers() {
        let store = WatchSnapshotStore(defaults: makeDefaults())
        // onChange 是 @Sendable 闭包，Swift 6 不允许它改捕获的 var——用锁包一个标志位
        let notified = OSAllocatedUnfairLock(initialState: false)

        // 与 SwiftUI 渲染 body 时做的事相同：读取 → 登记依赖 → 依赖变化时回调
        withObservationTracking {
            _ = store.payload
        } onChange: {
            notified.withLock { $0 = true }
        }

        store.apply(payload(["牛奶"], at: 100))

        #expect(notified.withLock { $0 }, "快照到达必须触发观察者——否则界面只会停在启动那一刻的样子")
        #expect(store.payload?.notes.map(\.text) == ["牛奶"])
    }

    // MARK: - 落盘（Watch Widget 与下次启动都靠它）

    @Test func appliedSnapshotIsPersistedInTheFormatTheWidgetReads() throws {
        let defaults = makeDefaults()
        let snapshot = payload(["牛奶", "快递"], at: 100)
        WatchSnapshotStore(defaults: defaults).apply(snapshot)

        // Watch Widget 用的是裸 JSONDecoder + 这个键（它那边是一份字面量，改键必须两边同步）
        let data = try #require(defaults.data(forKey: "com.pawit.watchPayload"))
        #expect(try JSONDecoder().decode(WatchPayload.self, from: data) == snapshot)
        #expect(WatchSnapshotStore.defaultsKey == "com.pawit.watchPayload")
    }

    // MARK: - 乱序

    @Test func olderSnapshotNeverOverwritesANewerOne() {
        let store = WatchSnapshotStore(defaults: makeDefaults())
        let newer = payload(["新"], at: 200)
        let older = payload(["旧"], at: 100)

        #expect(store.apply(newer))
        // 迟到的旧应答（例如先发出的拉取，晚于后发出的推送到达）必须被丢弃
        #expect(!store.apply(older), "旧快照应被拒收")
        #expect(store.payload == newer)
    }

    @Test func sameTimestampIsAcceptedSoColdStartContextIsIdempotent() {
        // 冷启动时「缓存」与「系统替我们存着的最新 context」是同一份快照：重复采纳应无害
        let store = WatchSnapshotStore(defaults: makeDefaults())
        let snapshot = payload(["牛奶"], at: 100)
        #expect(store.apply(snapshot))
        #expect(store.apply(snapshot))
        #expect(store.payload == snapshot)
    }

    @Test func newerSnapshotReplacesTheOldOneAndTheCache() {
        let defaults = makeDefaults()
        let store = WatchSnapshotStore(defaults: defaults)
        store.apply(payload(["旧"], at: 100))
        let newer = payload(["新"], at: 200)
        store.apply(newer)

        #expect(store.payload == newer)
        #expect(WatchSnapshotStore(defaults: defaults).payload == newer, "缓存也要跟着换")
    }

    // MARK: - 「没有便签」不等于「没同步过」

    @Test func syncedEmptyListIsDistinguishableFromNeverSynced() {
        let store = WatchSnapshotStore(defaults: makeDefaults())
        store.apply(payload([], at: 100))

        // iPhone 上确实一条便签都没有：这是「已同步、列表为空」，不是「还没同步」
        #expect(store.payload != nil)
        #expect(store.payload?.notes.isEmpty == true)
    }

    // MARK: - 手表 → iPhone：「把最新快照给我」

    @Test func snapshotRequestIsRecognisedAndOnlyThat() {
        #expect(WatchPayload.isSnapshotRequest(WatchPayload.snapshotRequest))
        #expect(!WatchPayload.isSnapshotRequest([:]))
        #expect(!WatchPayload.isSnapshotRequest(["request": "something-else"]))
        #expect(!WatchPayload.isSnapshotRequest(["watchPayload": "request"]))
    }

    @Test func snapshotRequestIsAValidWatchConnectivityPayload() {
        // WCSession 的消息字典只接受属性列表类型；不合法会在手表端直接发送失败
        #expect(PropertyListSerialization.propertyList(
            WatchPayload.snapshotRequest, isValidFor: .binary
        ))
    }
}
