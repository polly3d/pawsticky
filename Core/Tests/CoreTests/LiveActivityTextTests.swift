import Testing
@testable import Core

/// Live Activity 紧凑态（灵动岛药丸右端）标题缩略的行为钉子。
///
/// 起因（Watch 智能叠放截图）：旧实现是 `noteText.prefix(12)`——把 "Test hello world"
/// 硬切成 "Test hello w"，没有省略号、还切在单词中间。这里钉住新的口径：
/// 取第一行 → 超长时优先在词边界断开 → 带省略号 → 结果永不超过 limit（省略号占 1 格）。
struct LiveActivityTextTests {

    // MARK: - 不需要缩略

    @Test func shortTitleIsKeptAsIs() {
        #expect(LiveActivityText.compactTitle("Buy milk") == "Buy milk")
    }

    @Test func titleExactlyAtTheLimitIsKept() {
        // "Call the vet" 恰好 12 个字符
        #expect(LiveActivityText.compactTitle("Call the vet") == "Call the vet")
    }

    // MARK: - 在词边界断开

    @Test func longTitleIsCutAtTheLastWholeWord() {
        // 旧行为 "Test hello w"（切在单词中间、无省略号）正是截图里的缺陷
        #expect(LiveActivityText.compactTitle("Test hello world") == "Test hello…")
    }

    @Test func partialWordAtTheCutIsDropped() {
        // 前 11 个字符是 "Buy milk an"，"and" 不完整 → 退回 "Buy milk"
        #expect(LiveActivityText.compactTitle("Buy milk and eggs") == "Buy milk…")
    }

    @Test func wordEndingExactlyAtTheCutIsKept() {
        // 前 11 个字符 "Hello there" 后面紧跟空格 → 两个词都是完整的
        #expect(LiveActivityText.compactTitle("Hello there more text") == "Hello there…")
    }

    @Test func customLimitIsRespected() {
        // limit 8 → 前 7 个字符 "Buy mil"，退回到 "Buy"
        #expect(LiveActivityText.compactTitle("Buy milk and eggs", limit: 8) == "Buy…")
    }

    // MARK: - 没有词边界可用时硬切

    @Test func singleLongWordIsHardCut() {
        #expect(LiveActivityText.compactTitle("Supercalifragilistic") == "Supercalifr…")
    }

    @Test func textWithoutSpacesIsHardCut() {
        // 中日文没有空格——只能按字符数硬切
        #expect(LiveActivityText.compactTitle("明天下午三点开会讨论产品路线图") == "明天下午三点开会讨论产…")
    }

    @Test func graphemeClustersAreNeverSplit() {
        // 家庭 emoji 是 ZWJ 连接的单个字符；按 Character 切才不会劈开它
        let family = "👨‍👩‍👧‍👦"
        let result = LiveActivityText.compactTitle(String(repeating: family, count: 14))
        #expect(result == String(repeating: family, count: 11) + "…")
    }

    // MARK: - 取第一行 + 清理空白

    @Test func onlyTheFirstLineIsUsed() {
        #expect(LiveActivityText.compactTitle("Groceries\nMilk\nEggs") == "Groceries")
    }

    @Test func leadingBlankLinesAndWhitespaceAreSkipped() {
        #expect(LiveActivityText.compactTitle("\n\n  Milk run  \nsecond") == "Milk run")
    }

    @Test func blankInputGivesEmptyString() {
        #expect(LiveActivityText.compactTitle("") == "")
        #expect(LiveActivityText.compactTitle("  \n \t ") == "")
    }

    // MARK: - firstLine（小卡片取标题 / 普通便签取首行）

    @Test func firstLineKeepsALongTitleWhole() {
        // 与 compactTitle 的区别：不缩略——小卡片的版面（行数 / 缩放）自己决定怎么放
        #expect(LiveActivityText.firstLine("Call mom at 6pm and ask about the weekend trip\nsecond")
                == "Call mom at 6pm and ask about the weekend trip")
    }

    @Test func firstLineSkipsLeadingBlankLinesAndTrims() {
        #expect(LiveActivityText.firstLine("\n\n  Milk run  \nsecond") == "Milk run")
    }

    @Test func firstLineOfBlankInputIsEmpty() {
        #expect(LiveActivityText.firstLine("") == "")
        #expect(LiveActivityText.firstLine("  \n \t ") == "")
    }

    // MARK: - 不变式

    @Test func resultNeverExceedsTheLimit() {
        let samples = [
            "Test hello world", "Buy milk and eggs", "Supercalifragilistic",
            "明天下午三点开会讨论产品路线图", "A B C D E F G H I J K L M N O P",
            String(repeating: "🐱", count: 40), "Hello there more text",
        ]
        for limit in [4, 8, 12, 20] {
            for text in samples {
                let result = LiveActivityText.compactTitle(text, limit: limit)
                #expect(result.count <= limit, "\"\(text)\" @\(limit) → \"\(result)\"")
            }
        }
    }
}
