import Foundation
import Testing
import GRDB
@testable import Core

/// W2-4:HistoryLog(history_log)钉子——append-only 回滚日志的 schema、保留期与写入纪律。
/// 「零丢数据」承诺的存储半边:每次变更落整行快照,7 天保留窗内可回滚。
struct HistoryLogTests {

    /// 全新独立数据库路径(每次调用新临时目录,保证跨运行确定性)。
    private func makeDatabasePath() -> String {
        TestSupport.makeDatabasePath(prefix: "w24-log")
    }

    // MARK: - w2.v2 迁移:history_log 列集精确钉死(防范围蠕动,镜像 SchemaTests 风格)

    @Test func w2V2CreatesHistoryLogWithExactColumns() throws {
        let path = makeDatabasePath()
        _ = try SharedStore(databasePath: path)

        let rawPool = try DatabasePool(path: path)
        let columns = try rawPool.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info('history_log')").map { row -> String in
                row["name"]
            }
        }
        // PRAGMA table_info 按 schema 列序返回:显式钉住列序 = 迁移产物的字节级契约。
        #expect(columns == ["id", "entityType", "entityId", "payload", "changedAt"])
    }

    /// 迁移序列钉子:append-only 纪律——w3.v1 追加 style 列，第四步，已发布迁移永不改写。
    @Test func migrationSequencePinsW3V1AsFourthStep() throws {
        let path = makeDatabasePath()
        _ = try SharedStore(databasePath: path)

        let migrations = try DatabasePool(path: path).read { db in
            try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid")
        }
        #expect(migrations == ["w1.v1", "w2.v1", "w2.v2", "w3.v1"])
    }

    /// (entityType, entityId) 索引:history(for:) 按实体取数是唯一查询模式,免全表扫描。
    @Test func historyLogIndexCoversEntityTypeAndEntityId() throws {
        let path = makeDatabasePath()
        _ = try SharedStore(databasePath: path)

        let rawPool = try DatabasePool(path: path)
        let indexedColumns = try rawPool.read { db -> [[String]] in
            let indexNames = try Row.fetchAll(db, sql: "PRAGMA index_list('history_log')")
                .map { row -> String in row["name"] }
            return try indexNames.map { name in
                try Row.fetchAll(db, sql: "PRAGMA index_info('\(name)')")
                    .map { row -> String in row["name"] }
            }
        }
        #expect(indexedColumns.contains(["entityType", "entityId"]))
    }
}
