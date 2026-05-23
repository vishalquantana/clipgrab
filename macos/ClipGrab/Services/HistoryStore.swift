import Foundation
import SQLite3

class HistoryStore {
    private var db: OpaquePointer?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ClipGrab")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbPath = dir.appendingPathComponent("history.db").path
        if sqlite3_open(dbPath, &db) == SQLITE_OK { createTable() }
    }

    deinit { sqlite3_close(db) }

    private func createTable() {
        let sql = """
        CREATE TABLE IF NOT EXISTS downloads (
            id TEXT PRIMARY KEY,
            url TEXT NOT NULL UNIQUE,
            platform TEXT NOT NULL,
            title TEXT,
            status TEXT NOT NULL,
            media_type TEXT,
            file_path TEXT,
            thumbnail_path TEXT,
            file_size INTEGER,
            error_message TEXT,
            created_at REAL NOT NULL
        );
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    func save(_ item: DownloadItem) {
        let sql = """
        INSERT OR REPLACE INTO downloads
        (id, url, platform, title, status, media_type, file_path, thumbnail_path, file_size, error_message, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 2, item.url, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 3, item.platform, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 4, item.title, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 5, item.status.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 6, item.mediaType.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 7, item.filePath, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 8, item.thumbnailPath, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int64(stmt, 9, item.fileSize ?? 0)
        sqlite3_bind_text(stmt, 10, item.errorMessage, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_double(stmt, 11, item.createdAt.timeIntervalSince1970)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    func loadRecent(limit: Int) -> [DownloadItem] {
        let sql = "SELECT * FROM downloads ORDER BY created_at DESC LIMIT ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_int(stmt, 1, Int32(limit))
        var items: [DownloadItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let url = String(cString: sqlite3_column_text(stmt, 1))
            let platform = String(cString: sqlite3_column_text(stmt, 2))
            var item = DownloadItem(url: url, platform: platform)
            if let p = sqlite3_column_text(stmt, 3) { item.title = String(cString: p) }
            if let p = sqlite3_column_text(stmt, 4) { item.status = DownloadStatus(rawValue: String(cString: p)) ?? .complete }
            if let p = sqlite3_column_text(stmt, 5) { item.mediaType = MediaType(rawValue: String(cString: p)) ?? .video }
            if let p = sqlite3_column_text(stmt, 6) { item.filePath = String(cString: p) }
            if let p = sqlite3_column_text(stmt, 7) { item.thumbnailPath = String(cString: p) }
            item.fileSize = sqlite3_column_int64(stmt, 8)
            if let p = sqlite3_column_text(stmt, 9) { item.errorMessage = String(cString: p) }
            item.createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 10))
            items.append(item)
        }
        sqlite3_finalize(stmt)
        return items
    }

    func hasURL(_ url: String) -> Bool {
        // Strip query params for matching so ?s=20 doesn't bypass dedup
        // Only count successful downloads — failed ones should be retryable
        let baseURL = url.components(separatedBy: "?").first ?? url
        let sql = "SELECT COUNT(*) FROM downloads WHERE (url = ? OR url LIKE ? || '?%') AND status != 'failed';"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(stmt, 1, url, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 2, baseURL, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        var exists = false
        if sqlite3_step(stmt) == SQLITE_ROW { exists = sqlite3_column_int(stmt, 0) > 0 }
        sqlite3_finalize(stmt)
        return exists
    }
}
