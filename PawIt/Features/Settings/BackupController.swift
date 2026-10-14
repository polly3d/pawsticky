import SwiftUI
import Core

/// 备份 / 恢复流程的状态机：设置页的视图只负责绑定状态、转发点击，所有“下一步该发生什么”都在这里，
/// 因此可以不依赖 UI 直接单测（真实临时库，见 `BackupTests`）。
///
/// 为什么结果用页面内联的状态行、而不是弹窗：文件选择器 / 存储面板刚关闭的瞬间立刻弹 alert，
/// 在 SwiftUI 里有“弹不出来”的老毛病；内联状态没有任何呈现冲突，对 VoiceOver 也更稳。
@MainActor
@Observable
final class BackupController {

    // MARK: - 状态类型

    /// 选好备份文件之后、真正动手之前，等用户做的决定。
    enum Prompt: Equatable {
        /// 明文备份：只需确认“这会替换现有的全部数据”。
        case confirmReplace
        /// 加密备份：确认的同时还要输入口令。
        case passphrase
    }

    /// 一次“保存备份”的结果。
    enum ExportOutcome: Equatable {
        case saved(encrypted: Bool)
        case failed(reason: String)

        var isSuccess: Bool {
            if case .saved = self { return true }
            return false
        }

        var message: String {
            switch self {
            case .saved(encrypted: false):
                return String(localized: "Backup saved.")
            case .saved(encrypted: true):
                return String(localized: "Backup saved. Keep your passphrase safe — it can't be recovered.")
            case .failed(let reason):
                return String(localized: "Couldn't back up your notes. \(reason)")
            }
        }
    }

    /// 一次“从备份恢复”的结果。
    enum RestoreOutcome: Equatable {
        case restored(noteCount: Int)
        case failed(reason: String)

        var isSuccess: Bool {
            if case .restored = self { return true }
            return false
        }

        var message: String {
            switch self {
            case .restored(let noteCount):
                return noteCount == 1
                    ? String(localized: "Restored 1 note.")
                    : String(localized: "Restored \(noteCount) notes.")
            case .failed(let reason):
                // import 是单事务 + 先校验后写入：任何失败都不会留下半截数据，这句承诺是真的
                return String(localized: "\(reason) Nothing was changed.")
            }
        }
    }

    // MARK: - 视图读取的状态

    /// 非 nil 时视图弹出系统“存储到文件”面板。
    var document: BackupDocument?
    /// 非 nil 时设置页显示“待确认的恢复”卡片。
    private(set) var prompt: Prompt?
    /// 待恢复文件的名字（给确认卡片展示，让用户知道自己选的是哪个）。
    private(set) var stagedFileName: String?
    var exportOutcome: ExportOutcome?
    var restoreOutcome: RestoreOutcome?
    private(set) var isWorking = false

    // MARK: - 内部

    private let service: BackupService?
    /// 恢复成功后对齐库外状态（提醒 / 锁屏 / Watch / 小组件）。可注入，测试里只记录调用。
    @ObservationIgnored
    private let afterRestore: @MainActor (RestoreResult) async -> Void
    @ObservationIgnored
    private var staged: (data: Data, encryption: ExportEncryption)?
    @ObservationIgnored
    private var exportIsEncrypted = false

    init(
        service: BackupService?,
        afterRestore: @escaping @MainActor (RestoreResult) async -> Void = {
            await NoteChangeCoordinator.storeReplaced($0)
        }
    ) {
        self.service = service
        self.afterRestore = afterRestore
    }

    // MARK: - 导出

    /// 生成备份并交给视图弹出“存储到文件”。口令为空 = 明文备份（口令强度由视图层的
    /// `BackupPassphrasePolicy` 把关，这里不重复校验）。
    func startExport(passphrase: String) async {
        exportOutcome = nil
        guard let service else {
            exportOutcome = .failed(reason: BackupFailure.message(for: BackupError.storageUnavailable))
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let data = try await service.makeBackup(passphrase: passphrase)
            exportIsEncrypted = !passphrase.isEmpty
            document = BackupDocument(data: data)
        } catch {
            exportOutcome = .failed(reason: BackupFailure.message(for: error))
        }
    }

    /// “存储到文件”面板的回调。用户取消不算失败，保持静默。
    func exportFinished(_ result: Result<URL, any Error>) {
        document = nil
        switch result {
        case .success:
            exportOutcome = .saved(encrypted: exportIsEncrypted)
        case .failure(let error):
            if Self.isCancellation(error) { return }
            exportOutcome = .failed(reason: BackupFailure.message(for: error))
        }
    }

    // MARK: - 恢复

    /// 文件选择器的回调：读入、校验信封、暂存，然后等用户确认。**这一步不碰库。**
    func filePicked(_ result: Result<URL, any Error>) async {
        restoreOutcome = nil
        discardStagedBackup()

        guard service != nil else {
            restoreOutcome = .failed(reason: BackupFailure.message(for: BackupError.storageUnavailable))
            return
        }
        switch result {
        case .failure(let error):
            if Self.isCancellation(error) { return }
            restoreOutcome = .failed(reason: BackupFailure.message(for: error))
        case .success(let url):
            do {
                let data = try BackupFile.read(from: url)
                // 在问口令之前就拒掉“不是备份”的文件，而不是等用户输完口令才告诉他选错了
                let encryption = try NoteRepository.inspectExport(data)
                staged = (data, encryption)
                stagedFileName = url.lastPathComponent
                prompt = encryption == .passphrase ? .passphrase : .confirmReplace
            } catch {
                restoreOutcome = .failed(reason: BackupFailure.message(for: error))
            }
        }
    }

    /// 用户确认“替换”。没有暂存的备份时是空操作。
    func confirmRestore(passphrase: String) async {
        guard let staged, let service else {
            discardStagedBackup()
            return
        }
        restoreOutcome = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await service.restore(
                staged.data,
                passphrase: staged.encryption == .passphrase ? passphrase : nil
            )
            discardStagedBackup()
            await afterRestore(result)
            restoreOutcome = .restored(noteCount: result.restoredNotes.count)
        } catch let error as NoteRepositoryError
            where error == .decryptionFailed || error == .passphraseRequired || error == .emptyPassphrase {
            // 口令输错是最常见的失败：保留暂存，让用户在原地重输，不必重新选文件
            restoreOutcome = .failed(reason: BackupFailure.message(for: error))
        } catch {
            discardStagedBackup()
            restoreOutcome = .failed(reason: BackupFailure.message(for: error))
        }
    }

    /// 用户放弃：丢掉暂存的备份。
    func cancelRestore() {
        discardStagedBackup()
    }

    // MARK: - 私有

    private func discardStagedBackup() {
        staged = nil
        stagedFileName = nil
        prompt = nil
    }

    /// 系统面板的“取消”有时以 `.userCancelled` 错误回调——那是用户的选择，不是故障。
    private static func isCancellation(_ error: any Error) -> Bool {
        (error as? CocoaError)?.code == .userCancelled
    }
}
