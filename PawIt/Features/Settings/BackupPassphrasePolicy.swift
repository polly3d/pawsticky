import Foundation

/// 导出口令的检查结果：设置页据此显示提示、决定“保存”按钮能不能点。
enum BackupPassphraseCheck: Equatable {
    /// 没填口令：保存不加密的明文备份。
    case blank
    /// 太短。
    case tooShort(minimum: Int)
    /// 两次输入不一致。
    case mismatch
    /// 可以用。
    case acceptable
}

/// 备份口令策略。
///
/// 备份文件会被存进 iCloud Drive、发给别人，攻击者拿到文件后可以离线无限次猜口令——
/// 口令是唯一的屏障（PBKDF2 的 10 万轮只是放慢每一次猜测）。所以要有下限，
/// 但这是“防手滑”的门槛，不是强口令审查：口令留空就是明文备份，用户有选择权。
enum BackupPassphrasePolicy {

    /// 最少字符数（按 `Character` 计，不是字节：一个汉字算 1 位）。
    /// 想收紧 / 放宽，只改这一个数字——测试都是相对它书写的。
    static let minimumLength = 8

    static func check(_ passphrase: String, confirmation: String) -> BackupPassphraseCheck {
        if passphrase.isEmpty && confirmation.isEmpty { return .blank }

        // 首尾空白不计入长度（防止用空格凑数）；但口令本身一字不改地使用——
        // 绝不替用户“修剪”口令，否则恢复时输入的和加密时用的对不上。
        let effectiveLength = passphrase.trimmingCharacters(in: .whitespacesAndNewlines).count
        if effectiveLength < minimumLength { return .tooShort(minimum: minimumLength) }

        return passphrase == confirmation ? .acceptable : .mismatch
    }
}
