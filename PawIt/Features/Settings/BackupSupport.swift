import SwiftUI
import UniformTypeIdentifiers
import Core

// MARK: - 错误与文案

/// 备份流程在 App 层产生的错误（Core 的 typed 错误之外）。
enum BackupError: Error, Equatable {
    /// 文件超过 `BackupFile.maximumSize`。
    case tooLarge
    /// 文件读不出来（不存在 / 无权限 / 被系统回收）。
    case unreadable
    /// App Group 容器不可用——没有仓库可操作。
    case storageUnavailable
}

/// 把错误翻成给用户看的英文。UI 文案一律英语，经 `String(localized:)` 留好多语言入口。
enum BackupFailure {

    static func message(for error: Error) -> String {
        if let error = error as? BackupError {
            switch error {
            case .tooLarge:
                return String(localized: "That file is too large to be a PawSticky backup.")
            case .unreadable:
                return String(localized: "Couldn't read that file.")
            case .storageUnavailable:
                return String(localized: "PawSticky's storage isn't available right now.")
            }
        }
        if let error = error as? NoteRepositoryError {
            switch error {
            case .malformedEnvelope, .unsupportedFormat:
                return String(localized: "This file isn't a PawSticky backup.")
            case .unsupportedVersion, .unknownSpecies, .unsupportedKDF:
                return String(localized: "This backup was made by a newer version of PawSticky. Update the app and try again.")
            case .decryptionFailed:
                // Core 刻意不区分“口令错”与“密文被篡改”（防探测），文案同样不区分
                return String(localized: "That passphrase didn't work, or the backup file is damaged.")
            case .passphraseRequired, .emptyPassphrase:
                return String(localized: "This backup is encrypted. Enter its passphrase.")
            case .malformedPayload, .orphanedNoteItem, .growthStateWithoutPet,
                 .malformedEntityID, .duplicateEntityInImport:
                return String(localized: "The backup file is damaged or incomplete.")
            default:
                break
            }
        }
        return String(localized: "Something went wrong.")
    }
}

// MARK: - 文件

enum BackupFile {

    /// 备份文件大小上限。真实备份是 KB~MB 量级的文本；超限基本是选错了文件，
    /// 直接拒绝，免得把一个巨大的文件整个读进内存。
    static let maximumSize = 20 * 1024 * 1024

    /// “存储到文件”面板的默认文件名（不含扩展名，系统按 `.json` 类型补齐）。
    /// 日期取用户本地的“今天”，不是 UTC 的。
    static func defaultName(for date: Date = .now, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "PawSticky Backup %04ld-%02ld-%02ld",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
        )
    }

    /// 读取用户选的备份文件。
    ///
    /// 文件选择器给出的是 security-scoped URL，读取前后必须成对 start / stop。
    static func read(from url: URL, maximumSize: Int = BackupFile.maximumSize) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            // 多读 1 字节就能判断“是否超限”，不必把超大文件读完
            data = try handle.read(upToCount: maximumSize + 1) ?? Data()
        } catch {
            throw BackupError.unreadable
        }
        guard data.count <= maximumSize else { throw BackupError.tooLarge }
        return data
    }
}

/// `.fileExporter` 需要的文档包装：内容就是 Core 生成的备份信封 JSON。
struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - 服务

/// 一次恢复的结果：UI 层据此把库外状态（提醒 / 锁屏 / Watch）对齐到新数据。
struct RestoreResult: Equatable, Sendable {
    /// 恢复前库里的便签 id——这些便签已被整体替换。
    let previousNoteIds: Set<UUID>
    /// 恢复后库里的便签。
    let restoredNotes: [Note]
}

/// 备份 / 恢复的业务入口：口令规整 + 恢复前后的便签快照，其余全部委托 Core。
struct BackupService: Sendable {
    let repository: NoteRepository

    /// 生成备份。口令为空 / nil → 明文备份。
    func makeBackup(passphrase: String?) async throws -> Data {
        try await repository.export(passphrase: Self.normalized(passphrase))
    }

    /// 用备份**整体替换**当前库（Core 的 `import` 是单事务 replace-all，失败零改动）。
    func restore(_ data: Data, passphrase: String?) async throws -> RestoreResult {
        let previous = Set(try repository.allNotes().map(\.id))
        try await repository.`import`(data: data, passphrase: Self.normalized(passphrase))
        return RestoreResult(previousNoteIds: previous, restoredNotes: try repository.allNotes())
    }

    /// 口令规整：空 → nil（明文）；其余统一成 NFC 预组合形式。
    ///
    /// 不同键盘 / 设备对 “é” 之类的字符可能输出预组合（NFC）或分解（NFD）两种字节序列，
    /// 肉眼一样、UTF-8 字节不同，派生出的密钥也就不同——不规整的话，换机后会“口令正确却解不开”。
    /// 导出与恢复两侧都走这里，规整结果恒等。
    static func normalized(_ passphrase: String?) -> String? {
        guard let passphrase, !passphrase.isEmpty else { return nil }
        return passphrase.precomposedStringWithCanonicalMapping
    }
}
