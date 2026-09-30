import Foundation

extension UUID {

    /// 从存储 TEXT 列解析 UUID（W2-4 移交项⑧ DRY 收口）。
    /// 此前 Note.id、NoteItem.id、NoteItem.noteId 三处各有一份
    /// 「`UUID(uuidString:)` 失败抛 `SharedStoreError.corruptNoteID`」的拷贝，统一走本入口。
    /// - Throws: `SharedStoreError.corruptNoteID(raw)`——错误名沿用 w1 冻结的公开 API
    ///   值，语义是「应为 UUID 的 TEXT 列损坏」，**不限主键**（见该错误文档修正）。
    public static func parseStorage(_ raw: String) throws -> UUID {
        guard let id = UUID(uuidString: raw) else {
            throw SharedStoreError.corruptNoteID(raw)
        }
        return id
    }
}
