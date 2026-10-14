import Foundation
import Testing
import Core
@testable import PawIt

// MARK: - 口令策略

/// 导出口令的策略：空 = 明文备份；非空必须够长且两次输入一致。
/// 断言一律相对 `minimumLength` 书写——调整策略数字不应让测试失效。
struct BackupPassphrasePolicyTests {

    private var minimum: Int { BackupPassphrasePolicy.minimumLength }

    private func check(_ passphrase: String, _ confirmation: String? = nil) -> BackupPassphraseCheck {
        BackupPassphrasePolicy.check(passphrase, confirmation: confirmation ?? passphrase)
    }

    @Test func blankMeansAPlainBackup() {
        #expect(check("") == .blank)
    }

    @Test func passphrasesShorterThanTheMinimumAreRejected() {
        let tooShort = String(repeating: "a", count: minimum - 1)
        #expect(check(tooShort) == .tooShort(minimum: minimum))
    }

    @Test func aPassphraseOfExactlyTheMinimumLengthIsAccepted() {
        #expect(check(String(repeating: "a", count: minimum)) == .acceptable)
    }

    @Test func surroundingWhitespaceDoesNotCountTowardsTheLength() {
        // 看着够长，实际有效字符不足
        let padded = String(repeating: "a", count: minimum - 1) + " "
        #expect(check(padded) == .tooShort(minimum: minimum))
        #expect(check(String(repeating: " ", count: minimum)) == .tooShort(minimum: minimum))
    }

    @Test func lengthCountsCharactersNotBytes() {
        // 汉字每个 3 字节：按字节数会把 minimum - 1 个汉字误判为够长
        #expect(check(String(repeating: "猫", count: minimum - 1)) == .tooShort(minimum: minimum))
        #expect(check(String(repeating: "猫", count: minimum)) == .acceptable)
    }

    @Test func confirmationMustMatch() {
        let passphrase = String(repeating: "a", count: minimum)
        #expect(check(passphrase, passphrase + "b") == .mismatch)
        #expect(check(passphrase, "") == .mismatch)
    }
}

// MARK: - 失败文案

/// 把 Core / 文件层的 typed 错误翻成用户能看懂的英文（UI 文案一律英语）。
struct BackupFailureMessageTests {

    @Test func notABackupFile() {
        let expected = "This file isn't a PawSticky backup."
        #expect(BackupFailure.message(for: NoteRepositoryError.malformedEnvelope) == expected)
        #expect(BackupFailure.message(for: NoteRepositoryError.unsupportedFormat("other.app")) == expected)
    }

    @Test func newerVersionAsksForAnUpdate() {
        let expected = "This backup was made by a newer version of PawSticky. Update the app and try again."
        #expect(BackupFailure.message(for: NoteRepositoryError.unsupportedVersion(2)) == expected)
        #expect(BackupFailure.message(for: NoteRepositoryError.unknownSpecies("dragon")) == expected)
        #expect(BackupFailure.message(for: NoteRepositoryError.unsupportedKDF("scrypt")) == expected)
    }

    @Test func wrongPassphraseDoesNotRevealWhichPartFailed() {
        // Core 刻意不区分“口令错”与“密文被篡改”（防探测），文案同样不区分
        #expect(
            BackupFailure.message(for: NoteRepositoryError.decryptionFailed)
                == "That passphrase didn't work, or the backup file is damaged."
        )
    }

    @Test func encryptedBackupWithoutAPassphrase() {
        let expected = "This backup is encrypted. Enter its passphrase."
        #expect(BackupFailure.message(for: NoteRepositoryError.passphraseRequired) == expected)
        #expect(BackupFailure.message(for: NoteRepositoryError.emptyPassphrase) == expected)
    }

    @Test func structurallyBrokenBackup() {
        let expected = "The backup file is damaged or incomplete."
        #expect(BackupFailure.message(for: NoteRepositoryError.orphanedNoteItem(noteId: "x")) == expected)
        #expect(BackupFailure.message(for: NoteRepositoryError.growthStateWithoutPet(petId: "x")) == expected)
        #expect(BackupFailure.message(for: NoteRepositoryError.malformedEntityID("x")) == expected)
        #expect(BackupFailure.message(for: NoteRepositoryError.duplicateEntityInImport("note")) == expected)
        // 信封合法、内容读不出来：是“我们的文件但坏了”，不是“选错了文件”
        #expect(BackupFailure.message(for: NoteRepositoryError.malformedPayload) == expected)
    }

    @Test func fileLevelProblems() {
        #expect(BackupFailure.message(for: BackupError.tooLarge) == "That file is too large to be a PawSticky backup.")
        #expect(BackupFailure.message(for: BackupError.unreadable) == "Couldn't read that file.")
        #expect(
            BackupFailure.message(for: BackupError.storageUnavailable)
                == "PawSticky's storage isn't available right now."
        )
    }

    @Test func anythingElseFallsBackToAGenericMessage() {
        struct Unexpected: Error {}
        #expect(BackupFailure.message(for: Unexpected()) == "Something went wrong.")
    }
}

// MARK: - 文件名与读取

struct BackupFileTests {

    private func writeTemp(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pawsticky-backupfile-\(UUID().uuidString).json")
        try data.write(to: url)
        return url
    }

    @Test func defaultNameCarriesTheLocalDate() throws {
        let noonUTC = try #require(ISO8601DateFormatter().date(from: "2026-10-14T12:00:00Z"))
        let utc = try #require(TimeZone(identifier: "UTC"))
        // 奥克兰此刻已是 10-15 01:00：文件名用的是用户本地的“今天”，不是 UTC 的
        let auckland = try #require(TimeZone(identifier: "Pacific/Auckland"))

        #expect(BackupFile.defaultName(for: noonUTC, timeZone: utc) == "PawSticky Backup 2026-10-14")
        #expect(BackupFile.defaultName(for: noonUTC, timeZone: auckland) == "PawSticky Backup 2026-10-15")
    }

    @Test func readsAFileUpToTheLimit() throws {
        let url = try writeTemp(Data("abcd".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try BackupFile.read(from: url, maximumSize: 4) == Data("abcd".utf8))
    }

    @Test func rejectsAFileOverTheLimit() throws {
        let url = try writeTemp(Data("abcde".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: BackupError.tooLarge) {
            try BackupFile.read(from: url, maximumSize: 4)
        }
    }

    @Test func aMissingFileIsUnreadable() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("pawsticky-missing-\(UUID().uuidString).json")

        #expect(throws: BackupError.unreadable) {
            try BackupFile.read(from: missing)
        }
    }
}

// MARK: - 备份服务（真实临时库）

struct BackupServiceTests {

    /// 一个独立的临时库：返回库与仓库两个入口（养成数据只能走 store）。
    private func makeDatabase(_ tag: String) throws -> (store: SharedStore, repository: NoteRepository) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("pawsticky-backup-\(tag)-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("pawit.sqlite3").path
        let store = try SharedStore(databasePath: path)
        return (store, NoteRepository(store: store))
    }

    /// 种子：两条便签（一条带清单项）+ 一只选中的宠物及其养成态。
    @discardableResult
    private func seed(_ database: (store: SharedStore, repository: NoteRepository)) async throws -> [Note] {
        let groceries = try await database.repository.createNote(text: "Buy cat food")
        _ = try await database.repository.addItem(to: groceries.id, text: "Salmon pate")
        let vet = try await database.repository.createNote(
            text: "Call the vet", dueDate: Date(timeIntervalSince1970: 1_900_000_000)
        )
        try await database.store.upsertPet(
            PetProfile(id: "cat", species: .cat, displayName: "Tabby", isSelected: true)
        )
        try await database.store.upsertGrowthState(GrowthState(petId: "cat", fedLevel: 3, streakDays: 5))
        return [groceries, vet]
    }

    @Test func plainBackupRoundTripsNotesItemsAndPets() async throws {
        let source = try makeDatabase("plain-src")
        let seeded = try await seed(source)
        let target = try makeDatabase("plain-dst")
        _ = try await target.repository.createNote(text: "Local note that will be replaced")

        let data = try await BackupService(repository: source.repository).makeBackup(passphrase: nil)
        _ = try await BackupService(repository: target.repository).restore(data, passphrase: nil)

        let restored = try target.repository.allNotes()
        #expect(Set(restored.map(\.id)) == Set(seeded.map(\.id)))
        #expect(restored.map(\.text).sorted() == ["Buy cat food", "Call the vet"])
        let groceries = try #require(restored.first { $0.text == "Buy cat food" })
        #expect(try target.repository.noteItems(noteId: groceries.id).map(\.text) == ["Salmon pate"])
        #expect(try target.store.selectedPet()?.id == "cat")
        #expect(try target.store.growthState(petId: "cat")?.fedLevel == 3)
    }

    @Test func passphraseBackupIsEncryptedAndRoundTrips() async throws {
        let source = try makeDatabase("sealed-src")
        try await seed(source)
        let target = try makeDatabase("sealed-dst")

        let data = try await BackupService(repository: source.repository)
            .makeBackup(passphrase: "correct horse battery")

        #expect(try NoteRepository.inspectExport(data) == .passphrase)
        #expect(!String(decoding: data, as: UTF8.self).contains("Buy cat food"))  // 明文不得出现在加密备份里
        _ = try await BackupService(repository: target.repository)
            .restore(data, passphrase: "correct horse battery")
        #expect(try target.repository.allNotes().count == 2)
    }

    @Test func blankPassphraseProducesAPlainBackup() async throws {
        let source = try makeDatabase("blank")
        try await seed(source)

        let data = try await BackupService(repository: source.repository).makeBackup(passphrase: "")

        #expect(try NoteRepository.inspectExport(data) == .plaintext)
    }

    @Test func restoreReportsWhatItReplaced() async throws {
        let source = try makeDatabase("report-src")
        let seeded = try await seed(source)
        let target = try makeDatabase("report-dst")
        let local = try await target.repository.createNote(text: "Local")
        let data = try await BackupService(repository: source.repository).makeBackup(passphrase: nil)

        let result = try await BackupService(repository: target.repository).restore(data, passphrase: nil)

        #expect(result.previousNoteIds == [local.id])
        #expect(Set(result.restoredNotes.map(\.id)) == Set(seeded.map(\.id)))
    }

    @Test func aWrongPassphraseFailsAndLeavesTheDatabaseUntouched() async throws {
        let source = try makeDatabase("wrong-src")
        try await seed(source)
        let target = try makeDatabase("wrong-dst")
        let local = try await target.repository.createNote(text: "Local")
        let data = try await BackupService(repository: source.repository)
            .makeBackup(passphrase: "correct horse battery")

        await #expect(throws: NoteRepositoryError.decryptionFailed) {
            try await BackupService(repository: target.repository).restore(data, passphrase: "wrong horse battery")
        }

        #expect(try target.repository.allNotes().map(\.id) == [local.id])  // 按 id 比：createdAt 入库会截到毫秒，整体 == 会误报
    }

    @Test func composedAndDecomposedSpellingsAreTheSamePassphrase() async throws {
        // 不同键盘 / 设备对 “é” 可能输出预组合（NFC）或分解（NFD）两种字节序列，
        // 肉眼一样、字节不同——不规整的话，换机后会“口令正确却解不开”。
        let composed = "caf\u{00E9} au lait!"
        let decomposed = "cafe\u{0301} au lait!"
        #expect(Array(composed.utf8) != Array(decomposed.utf8))

        let source = try makeDatabase("nfc-src")
        try await seed(source)
        let target = try makeDatabase("nfc-dst")
        let data = try await BackupService(repository: source.repository).makeBackup(passphrase: composed)

        _ = try await BackupService(repository: target.repository).restore(data, passphrase: decomposed)

        #expect(try target.repository.allNotes().count == 2)
    }
}

// MARK: - 结果文案

/// 结果行的英文文案（设置页的内联状态行与 VoiceOver 播报共用同一份）。
struct BackupOutcomeMessageTests {

    @Test func exportMessages() {
        #expect(BackupController.ExportOutcome.saved(encrypted: false).message == "Backup saved.")
        #expect(
            BackupController.ExportOutcome.saved(encrypted: true).message
                == "Backup saved. Keep your passphrase safe — it can't be recovered."
        )
        #expect(
            BackupController.ExportOutcome.failed(reason: "Something went wrong.").message
                == "Couldn't back up your notes. Something went wrong."
        )
    }

    @Test func restoreMessagesAgreeInNumber() {
        #expect(BackupController.RestoreOutcome.restored(noteCount: 0).message == "Restored 0 notes.")
        #expect(BackupController.RestoreOutcome.restored(noteCount: 1).message == "Restored 1 note.")
        #expect(BackupController.RestoreOutcome.restored(noteCount: 3).message == "Restored 3 notes.")
    }

    @Test func aFailedRestoreAlwaysSaysNothingChanged() {
        // import 是单事务 + 先校验后写入：任何失败都不会留下半截数据——文案可以放心承诺
        #expect(
            BackupController.RestoreOutcome.failed(reason: "This file isn't a PawSticky backup.").message
                == "This file isn't a PawSticky backup. Nothing was changed."
        )
    }

    @Test func successAndFailureAreDistinguishable() {
        #expect(BackupController.ExportOutcome.saved(encrypted: false).isSuccess)
        #expect(!BackupController.ExportOutcome.failed(reason: "x").isSuccess)
        #expect(BackupController.RestoreOutcome.restored(noteCount: 1).isSuccess)
        #expect(!BackupController.RestoreOutcome.failed(reason: "x").isSuccess)
    }
}

// MARK: - 备份控制器（导出 / 恢复流程状态机）

@MainActor
private final class EffectLog {
    var results: [RestoreResult] = []
}

@MainActor
struct BackupControllerTests {

    private func makeDatabase(_ tag: String) throws -> (store: SharedStore, repository: NoteRepository) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("pawsticky-ctl-\(tag)-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("pawit.sqlite3").path
        let store = try SharedStore(databasePath: path)
        return (store, NoteRepository(store: store))
    }

    private func makeController(_ repository: NoteRepository, log: EffectLog) -> BackupController {
        BackupController(service: BackupService(repository: repository)) { log.results.append($0) }
    }

    /// 写出一份真实备份文件（来自另一个库）：返回文件 URL。
    private func makeBackupFile(passphrase: String?) async throws -> URL {
        let source = try makeDatabase("file-src")
        _ = try await source.repository.createNote(text: "From the backup")
        let data = try await BackupService(repository: source.repository).makeBackup(passphrase: passphrase)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pawsticky-ctl-\(UUID().uuidString).json")
        try data.write(to: url)
        return url
    }

    @Test func pickingAPlainBackupAsksForConfirmationOnly() async throws {
        let target = try makeDatabase("pick-plain")
        let controller = makeController(target.repository, log: EffectLog())
        let url = try await makeBackupFile(passphrase: nil)

        await controller.filePicked(.success(url))

        #expect(controller.prompt == .confirmReplace)
        #expect(controller.stagedFileName == url.lastPathComponent)
        #expect(controller.restoreOutcome == nil)
        #expect(try target.repository.allNotes().isEmpty)  // 只是暂存，库一个字节没动
    }

    @Test func pickingAnEncryptedBackupAsksForThePassphrase() async throws {
        let controller = makeController(try makeDatabase("pick-sealed").repository, log: EffectLog())
        let url = try await makeBackupFile(passphrase: "correct horse battery")

        await controller.filePicked(.success(url))

        #expect(controller.prompt == .passphrase)
    }

    @Test func pickingSomethingThatIsNotABackupExplainsWhyAndStagesNothing() async throws {
        let target = try makeDatabase("pick-junk")
        let local = try await target.repository.createNote(text: "Local")
        let log = EffectLog()
        let controller = makeController(target.repository, log: log)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pawsticky-ctl-\(UUID().uuidString).json")
        try Data("not a backup".utf8).write(to: url)

        await controller.filePicked(.success(url))
        await controller.confirmRestore(passphrase: "")  // 没有暂存 → 必须是空操作

        #expect(controller.prompt == nil)
        #expect(controller.stagedFileName == nil)
        #expect(controller.restoreOutcome == .failed(reason: "This file isn't a PawSticky backup."))
        #expect(try target.repository.allNotes().map(\.id) == [local.id])  // 按 id 比：createdAt 入库会截到毫秒，整体 == 会误报
        #expect(log.results.isEmpty)
    }

    @Test func confirmingReplacesEverythingAndRunsTheSideEffectsOnce() async throws {
        let target = try makeDatabase("confirm")
        let local = try await target.repository.createNote(text: "Local")
        let log = EffectLog()
        let controller = makeController(target.repository, log: log)
        let url = try await makeBackupFile(passphrase: nil)

        await controller.filePicked(.success(url))
        await controller.confirmRestore(passphrase: "")

        #expect(try target.repository.allNotes().map(\.text) == ["From the backup"])
        #expect(controller.restoreOutcome == .restored(noteCount: 1))
        #expect(controller.prompt == nil)
        #expect(controller.stagedFileName == nil)
        #expect(controller.isWorking == false)
        #expect(log.results.count == 1)
        #expect(log.results.first?.previousNoteIds == [local.id])
    }

    @Test func aWrongPassphraseExplainsAndChangesNothing() async throws {
        let target = try makeDatabase("wrong-pass")
        let local = try await target.repository.createNote(text: "Local")
        let log = EffectLog()
        let controller = makeController(target.repository, log: log)
        let url = try await makeBackupFile(passphrase: "correct horse battery")

        await controller.filePicked(.success(url))
        await controller.confirmRestore(passphrase: "wrong horse battery")

        #expect(controller.restoreOutcome == .failed(
            reason: "That passphrase didn't work, or the backup file is damaged."
        ))
        #expect(try target.repository.allNotes().map(\.id) == [local.id])  // 按 id 比：createdAt 入库会截到毫秒，整体 == 会误报
        #expect(log.results.isEmpty)  // 失败不得触发库外副作用（提醒 / 锁屏 / Watch）
        #expect(controller.isWorking == false)
    }

    @Test func aWrongPassphraseCanBeRetriedWithoutPickingTheFileAgain() async throws {
        let target = try makeDatabase("retry")
        let log = EffectLog()
        let controller = makeController(target.repository, log: log)
        let url = try await makeBackupFile(passphrase: "correct horse battery")

        await controller.filePicked(.success(url))
        await controller.confirmRestore(passphrase: "wrong horse battery")

        // 口令打错是最常见的失败：卡片还在，用户原地重输即可
        #expect(controller.prompt == .passphrase)
        #expect(controller.stagedFileName == url.lastPathComponent)

        await controller.confirmRestore(passphrase: "correct horse battery")

        #expect(try target.repository.allNotes().map(\.text) == ["From the backup"])
        #expect(controller.restoreOutcome == .restored(noteCount: 1))
        #expect(controller.prompt == nil)
        #expect(log.results.count == 1)
    }

    @Test func aDamagedBackupDropsTheCardBecauseRetryingCannotHelp() async throws {
        let target = try makeDatabase("damaged")
        let controller = makeController(target.repository, log: EffectLog())
        // 信封合法（能过 inspect）、内容却是坏的：重试同一个文件永远不会成功
        let envelope = ExportEnvelope(format: "pawit.export", version: 1, salt: nil, kdf: nil, payload: "{}")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pawsticky-ctl-\(UUID().uuidString).json")
        try JSONEncoder().encode(envelope).write(to: url)

        await controller.filePicked(.success(url))
        #expect(controller.prompt == .confirmReplace)
        await controller.confirmRestore(passphrase: "")

        #expect(controller.prompt == nil)
        #expect(controller.stagedFileName == nil)
        #expect(controller.restoreOutcome == .failed(reason: "The backup file is damaged or incomplete."))
    }

    @Test func cancellingDropsTheStagedBackup() async throws {
        let target = try makeDatabase("cancel")
        let local = try await target.repository.createNote(text: "Local")
        let log = EffectLog()
        let controller = makeController(target.repository, log: log)
        let url = try await makeBackupFile(passphrase: nil)

        await controller.filePicked(.success(url))
        controller.cancelRestore()
        await controller.confirmRestore(passphrase: "")  // 暂存已丢弃 → 空操作

        #expect(controller.prompt == nil)
        #expect(controller.stagedFileName == nil)
        #expect(try target.repository.allNotes().map(\.id) == [local.id])  // 按 id 比：createdAt 入库会截到毫秒，整体 == 会误报
        #expect(log.results.isEmpty)
    }

    @Test func aNewPickClearsTheOldResultLine() async throws {
        let target = try makeDatabase("clear-old")
        let controller = makeController(target.repository, log: EffectLog())
        let url = try await makeBackupFile(passphrase: nil)
        await controller.filePicked(.success(url))
        await controller.confirmRestore(passphrase: "")
        #expect(controller.restoreOutcome == .restored(noteCount: 1))

        await controller.filePicked(.success(url))

        #expect(controller.restoreOutcome == nil)  // 上一次的“已恢复”不能和新一轮暂存同屏
        #expect(controller.prompt == .confirmReplace)
    }

    @Test func exportWithoutAPassphraseStagesAPlainDocument() async throws {
        let source = try makeDatabase("export-plain")
        _ = try await source.repository.createNote(text: "Export me")
        let controller = makeController(source.repository, log: EffectLog())

        await controller.startExport(passphrase: "")

        let document = try #require(controller.document)
        #expect(try NoteRepository.inspectExport(document.data) == .plaintext)

        controller.exportFinished(.success(URL(fileURLWithPath: "/tmp/ignored.json")))
        #expect(controller.document == nil)
        #expect(controller.exportOutcome == .saved(encrypted: false))
    }

    @Test func exportWithAPassphraseIsEncryptedAndSaysSo() async throws {
        let source = try makeDatabase("export-sealed")
        _ = try await source.repository.createNote(text: "Export me")
        let controller = makeController(source.repository, log: EffectLog())

        await controller.startExport(passphrase: "correct horse battery")

        let document = try #require(controller.document)
        #expect(try NoteRepository.inspectExport(document.data) == .passphrase)

        controller.exportFinished(.success(URL(fileURLWithPath: "/tmp/ignored.json")))
        #expect(controller.exportOutcome == .saved(encrypted: true))
    }

    @Test func aFailedSaveIsReported() throws {
        let controller = makeController(try makeDatabase("export-fail").repository, log: EffectLog())

        controller.exportFinished(.failure(BackupError.unreadable))

        #expect(controller.exportOutcome == .failed(reason: "Couldn't read that file."))
    }

    @Test func cancellingThePickersIsSilent() async throws {
        let controller = makeController(try makeDatabase("silent").repository, log: EffectLog())

        controller.exportFinished(.failure(CocoaError(.userCancelled)))
        await controller.filePicked(.failure(CocoaError(.userCancelled)))

        #expect(controller.exportOutcome == nil)
        #expect(controller.restoreOutcome == nil)
        #expect(controller.document == nil)
        #expect(controller.prompt == nil)
    }

    @Test func missingStorageIsReportedInsteadOfCrashing() async {
        let controller = BackupController(service: nil) { _ in }

        await controller.startExport(passphrase: "")
        await controller.filePicked(.success(URL(fileURLWithPath: "/tmp/ignored.json")))

        #expect(controller.document == nil)
        #expect(controller.prompt == nil)
        let unavailable = "PawSticky's storage isn't available right now."
        #expect(controller.exportOutcome == .failed(reason: unavailable))
        #expect(controller.restoreOutcome == .failed(reason: unavailable))
    }
}
