import Foundation
import Testing
@testable import Core

/// W3-5:ReminderManager 单测——经 FakeNotificationScheduler 注入,
/// 验证 syncReminder 的排程/取消决策（无 UNUserNotificationCenter 依赖）。
struct ReminderManagerTests {

    // MARK: - Fake

    final class FakeScheduler: NotificationScheduling, @unchecked Sendable {
        var scheduled: [(noteID: UUID, date: Date, body: String)] = []
        var cancelled: [UUID] = []
        var authResult = true

        func schedule(noteID: UUID, at date: Date, body: String) async throws {
            scheduled.append((noteID, date, body))
        }
        func cancel(noteID: UUID) async {
            cancelled.append(noteID)
        }
        func requestAuthorization() async throws -> Bool { authResult }
    }

    // MARK: - syncReminder

    @Test func syncReminderSchedulesWhenDueDateInFuture() async {
        let fake = FakeScheduler()
        let manager = ReminderManager(scheduler: fake)
        let future = Date.now.addingTimeInterval(3600)
        let note = Note(text: "Buy milk", dueDate: future)

        await manager.syncReminder(for: note)

        #expect(fake.scheduled.count == 1)
        #expect(fake.scheduled[0].noteID == note.id)
        #expect(fake.scheduled[0].date == future)
        #expect(fake.scheduled[0].body == "Buy milk")
        #expect(fake.cancelled.isEmpty)
    }

    @Test func syncReminderCancelsWhenDueDateIsNil() async {
        let fake = FakeScheduler()
        let manager = ReminderManager(scheduler: fake)
        let note = Note(text: "No deadline")

        await manager.syncReminder(for: note)

        #expect(fake.scheduled.isEmpty)
        #expect(fake.cancelled == [note.id])
    }

    @Test func syncReminderCancelsWhenDueDateIsInPast() async {
        let fake = FakeScheduler()
        let manager = ReminderManager(scheduler: fake)
        let past = Date.now.addingTimeInterval(-3600)
        let note = Note(text: "Expired", dueDate: past)

        await manager.syncReminder(for: note)

        #expect(fake.scheduled.isEmpty)
        #expect(fake.cancelled == [note.id])
    }

    @Test func syncReminderTruncatesLongBody() async {
        let fake = FakeScheduler()
        let manager = ReminderManager(scheduler: fake)
        let longText = String(repeating: "a", count: 500)
        let note = Note(text: longText, dueDate: Date.now.addingTimeInterval(3600))

        await manager.syncReminder(for: note)

        #expect(fake.scheduled[0].body.count == 200)
    }

    @Test func cancelReminderForwardsToScheduler() async {
        let fake = FakeScheduler()
        let manager = ReminderManager(scheduler: fake)
        let id = UUID()

        await manager.cancelReminder(noteID: id)

        #expect(fake.cancelled == [id])
    }

    @Test func ensureAuthorizationReturnsSchedulerResult() async {
        let fake = FakeScheduler()
        fake.authResult = false
        let manager = ReminderManager(scheduler: fake)

        let result = await manager.ensureAuthorization()
        #expect(result == false)
    }
}
