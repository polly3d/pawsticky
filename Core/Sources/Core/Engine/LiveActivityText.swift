import Foundation

// MARK: - LiveActivityText（Live Activity 文案）

/// Live Activity 文案的纯函数集合——放在 Core 里，才能用单测钉住口径。
public enum LiveActivityText {

    /// 便签正文的第一行非空文本（去掉首尾空白）；全是空白则返回 ""。
    ///
    /// 便签正文可能多行：清单便签的第一行就是标题，普通便签的第一行是“标题行”。
    /// 不做任何缩略——放得下放不下由各个版面自己决定。
    public static func firstLine(_ text: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? ""
    }

    /// 紧凑态（灵动岛药丸右端）的标题缩略。
    ///
    /// 旧写法是内联的 `noteText.prefix(12)`：把 "Test hello world" 硬切成 "Test hello w"
    /// ——没有省略号、还切在单词中间（Watch 智能叠放的截图里最显眼）。口径：
    /// 1. 只取第一行非空文本（见 `firstLine`）；
    /// 2. 不超过 `limit` 个字符就原样返回；
    /// 3. 超长时留 1 格给省略号，优先退回到最近的词边界，保证不出现半个单词；
    /// 4. 没有空格可退（单个长词 / 中日文）才按字符硬切；
    /// 5. 按 `Character`（字形簇）切，不会劈开 emoji；结果永不超过 `limit`。
    public static func compactTitle(_ text: String, limit: Int = 12) -> String {
        let line = firstLine(text)
        guard line.count > limit else { return line }

        // 省略号占 1 格；limit 过小时至少保留 1 个字符
        let head = line.prefix(max(limit - 1, 1))
        // `head` 与 `line` 共用下标；line.count > limit，所以 head 之后一定还有字符
        let followedByBoundary = line[head.endIndex].isWhitespace
        var kept = head
        if !followedByBoundary, let lastSpace = head.lastIndex(where: \.isWhitespace) {
            kept = head[..<lastSpace]
        }
        return kept.trimmingCharacters(in: .whitespaces) + "…"
    }
}
