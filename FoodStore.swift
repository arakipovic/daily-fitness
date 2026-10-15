import Foundation
import SQLite3

// MARK: - FoodStore

/// SQLite-backed food database with FTS5 full-text search.
/// On first launch, copies the pre-built `foods.db` bundle resource.
/// Supports bulk JSON import via `importJSON(from:)` and custom food entries via `insertCustomFood(_:)`.
actor FoodStore {
    static let shared = FoodStore()

    private var db: OpaquePointer?
    private let path: String
    private var isReady = false

    /// Total number of foods in the database. 0 until setup() completes.
    private(set) var count: Int = 0

    private init(path: String = FoodStore.defaultPath()) {
        self.path = path
    }

    // MARK: - Factory

    /// Creates an isolated in-memory store for unit testing.
    static func ephemeral() -> FoodStore { FoodStore(path: ":memory:") }

    /// Creates a file-based store at a specific path for unit testing.
    static func forTesting(path: String) -> FoodStore { FoodStore(path: path) }

    /// Checkpoints the WAL into the main database file.
    /// Call this before copying the database file to ensure all committed rows
    /// are in the main file rather than only in the WAL journal.
    func checkpoint() {
        guard let db, isReady else { return }
        sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
    }

    // MARK: - Custom Foods (user-scoped)

    /// Inserts or replaces a user-specific custom food into the `custom_foods` table.
    /// The stored row ID is `template.customFoodID`, or a newly generated UUID if nil.
    func insertCustomFood(_ template: FoodTemplate, userID: UUID) {
        guard isReady, let db else { return }
        let foodID = template.customFoodID ?? UUID()
        let sql = """
            INSERT OR REPLACE INTO custom_foods
              (id, user_id, name, category, kcal, protein, carbs, fat,
               fiber, sugar, sat_fat, sodium, cholesterol, serving_g, serving_label, created_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,strftime('%s','now'))
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt!, 1, foodID.uuidString)
        bind(stmt!, 2, userID.uuidString)
        bind(stmt!, 3, template.name)
        bind(stmt!, 4, template.category.rawValue)
        sqlite3_bind_double(stmt!, 5, template.kcal)
        sqlite3_bind_double(stmt!, 6, template.protein)
        sqlite3_bind_double(stmt!, 7, template.carbs)
        sqlite3_bind_double(stmt!, 8, template.fat)
        sqlite3_bind_double(stmt!, 9, template.fiber)
        sqlite3_bind_double(stmt!, 10, template.sugar)
        sqlite3_bind_double(stmt!, 11, template.saturatedFat)
        sqlite3_bind_double(stmt!, 12, template.sodium)
        sqlite3_bind_double(stmt!, 13, template.cholesterol)
        sqlite3_bind_int(stmt!, 14, Int32(template.defaultServingG))
        bindOpt(stmt!, 15, template.servingLabel)
        sqlite3_step(stmt)
    }

    /// Deletes a custom food owned by `userID`. No-op if not found or owned by another user.
    func deleteCustomFood(id: UUID, userID: UUID) {
        guard isReady, let db else { return }
        let sql = "DELETE FROM custom_foods WHERE id = ? AND user_id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt!, 1, id.uuidString)
        bind(stmt!, 2, userID.uuidString)
        sqlite3_step(stmt)
    }

    /// Returns all custom foods for `userID`, newest first.
    func customFoods(for userID: UUID) -> [FoodTemplate] {
        guard isReady, let db else { return [] }
        let sql = """
            SELECT id, name, category, kcal, protein, carbs, fat,
                   fiber, sugar, sat_fat, sodium, cholesterol, serving_g, serving_label
            FROM custom_foods WHERE user_id = ? ORDER BY created_at DESC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(stmt!, 1, userID.uuidString)
        return collectCustomRows(stmt!)
    }

    // MARK: - Setup

    /// Opens or creates the database and creates the schema.
    /// On first launch, copies the pre-built `foods.db` from the app bundle if present.
    /// If the runtime DB is a small stub (<10 k foods), replaces it with the bundle copy.
    /// Pass `seeding` to seed from explicit templates (tests only). Safe to call multiple times.
    func setup(seeding templates: [FoodTemplate]? = nil, bundleURL: URL? = Bundle.main.url(forResource: "foods", withExtension: "db")) async {
        guard !isReady else { return }

        if path != ":memory:" {
            let dir = (path as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(
                atPath: dir, withIntermediateDirectories: true, attributes: nil)

            if !FileManager.default.fileExists(atPath: path) {
                // Fresh install: copy bundle DB instead of seeding row-by-row.
                if let bundleURL {
                    removeWALSidecars(at: path)
                    try? FileManager.default.copyItem(at: bundleURL, to: URL(fileURLWithPath: path))
                }
            } else if let bundleURL {
                // Existing DB: if it's a small stub (seeded from code only), upgrade from bundle.
                if stubCount(at: path) < 10_000 {
                    try? FileManager.default.removeItem(atPath: path)
                    removeWALSidecars(at: path)
                    try? FileManager.default.copyItem(at: bundleURL, to: URL(fileURLWithPath: path))
                }
            }
        }

        guard sqlite3_open(path, &db) == SQLITE_OK else { return }

        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA synchronous=NORMAL")
        createSchema()

        if let templates, rowCount() == 0 {
            insertBatch(templates)
        }

        // One-time migration: merge the 409 hardcoded catalog foods (Din Tai Fung etc.)
        // into the SQLite DB so they're searchable alongside the full food database.
        if path != ":memory:", !migrationDone("catalog_v1") {
            insertBatch(foodDatabase)
            setMigrationDone("catalog_v1")
        }

        // Incremental bundle merge: whenever the bundled foods.db grows (new restaurant
        // imports, etc.), INSERT OR IGNORE the new rows into the runtime DB.
        // The migration key is derived from the bundle file's byte size — when we ship
        // a larger bundle, the size changes, the key is new, and the merge re-runs
        // automatically on every device without manual version bumps.
        if path != ":memory:", let bundleURL,
           let key = bundleMigrationKey(at: bundleURL),
           !migrationDone(key) {
            mergeFromBundle(at: bundleURL)
            setMigrationDone(key)
        }

        count = rowCount()
        isReady = true
    }

    // MARK: - Migration helpers

    private func migrationDone(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: migrationFlagPath(name))
    }

    private func setMigrationDone(_ name: String) {
        FileManager.default.createFile(atPath: migrationFlagPath(name), contents: nil)
    }

    private func migrationFlagPath(_ name: String) -> String {
        let dir = (path as NSString).deletingLastPathComponent
        return (dir as NSString).appendingPathComponent(".\(name).done")
    }

    /// Returns a migration key that changes whenever the bundle file changes.
    /// Uses file size (bytes) as a lightweight, O(1) proxy for file identity —
    /// cheaper than hashing the full file and reliable for an append-only DB.
    private func bundleMigrationKey(at url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size > 0 else { return nil }
        return "bundle_bytes_\(size)"
    }

    /// Copies the bundle DB to a writable temp path, ATTACHes it, INSERT OR IGNOREs new rows,
    /// then removes the temp copy. We copy first because ATTACH defaults to read-write mode
    /// and silently fails when the source is on the read-only iOS app-bundle filesystem.
    private func mergeFromBundle(at url: URL) {
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bundle_merge_tmp.db")
        do {
            if FileManager.default.fileExists(atPath: tmpURL.path) {
                try FileManager.default.removeItem(at: tmpURL)
            }
            try FileManager.default.copyItem(at: url, to: tmpURL)
        } catch {
            return
        }
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let escaped = tmpURL.path.replacingOccurrences(of: "'", with: "''")
        exec("ATTACH DATABASE '\(escaped)' AS bundle_src")
        exec("""
            INSERT OR IGNORE INTO foods
                (name, category, kcal, protein, carbs, fat,
                 fiber, sugar, sat_fat, sodium, cholesterol, serving_g, serving_label)
            SELECT name, category, kcal, protein, carbs, fat,
                   fiber, sugar, sat_fat, sodium, cholesterol, serving_g, serving_label
            FROM bundle_src.foods
        """)
        exec("DETACH DATABASE bundle_src")
    }

    private func removeWALSidecars(at dbPath: String) {
        try? FileManager.default.removeItem(atPath: dbPath + "-wal")
        try? FileManager.default.removeItem(atPath: dbPath + "-shm")
    }

    /// Opens the DB read-only and returns its food count, or 0 on any error.
    private func stubCount(at dbPath: String) -> Int {
        var tmpDb: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &tmpDb, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_close(tmpDb) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(tmpDb, "SELECT COUNT(*) FROM foods", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    // MARK: - Search

    /// FTS5 prefix search across food names, prepending user-specific custom foods when `userID` is provided.
    /// Expands brand aliases (e.g. "DFT" → "Din Tai Fung"), falls back to LIKE substring
    /// search, then tries de-pluralizing the last word (e.g. "Proper Foods" → "Proper Food").
    func search(_ text: String, userID: UUID? = nil, limit: Int = 50) -> [FoodTemplate] {
        guard isReady else { return [] }
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }

        var customResults: [FoodTemplate] = []
        if let userID {
            customResults = customFoodsLikeSearch("%\(q)%", userID: userID, limit: limit)
        }

        let sharedResults = sharedSearch(q, limit: limit)

        if customResults.isEmpty { return sharedResults }
        let customNames = Set(customResults.map { $0.name.lowercased() })
        return customResults + sharedResults.filter { !customNames.contains($0.name.lowercased()) }
    }

    private func sharedSearch(_ q: String, limit: Int) -> [FoodTemplate] {
        // Expand known brand abbreviations / plural variants before anything else.
        let expanded = Self.brandAliases[q.lowercased()] ?? q

        let sanitized = expanded.components(separatedBy: ftsSpecialChars).joined(separator: " ")
        let words = sanitized.split(separator: " ").filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }

        // 1. FTS AND-prefix search.
        let ftsQuery = words.map { "\($0)*" }.joined(separator: " ")
        let r1 = ftsSearch(ftsQuery, limit: limit)
        if !r1.isEmpty { return prioritized(r1, query: q) }

        // 2. LIKE substring fallback on the expanded query.
        let r2 = likeSearch("%\(expanded)%", limit: limit)
        if !r2.isEmpty { return prioritized(r2, query: q) }

        // 3. De-pluralize the last word and retry FTS (handles "Proper Foods" → "Proper Food*").
        if let lastWord = words.last, lastWord.count > 2, lastWord.hasSuffix("s") {
            let stem = lastWord.dropLast()
            let stemQuery = (words.dropLast().map { "\($0)*" } + ["\(stem)*"]).joined(separator: " ")
            let r3 = ftsSearch(stemQuery, limit: limit)
            if !r3.isEmpty { return prioritized(r3, query: q) }
        }

        // 4. No-space compound query (e.g. "budlight" → try splitting at each position,
        //    look up candidate in aliases, search with the expanded form).
        let qLower = q.lowercased()
        if !qLower.contains(" ") && qLower.count > 3 {
            for i in 1..<qLower.count {
                let idx = qLower.index(qLower.startIndex, offsetBy: i)
                let candidate = String(qLower[..<idx]) + " " + String(qLower[idx...])
                let candidateExpanded = Self.brandAliases[candidate] ?? candidate
                let san = candidateExpanded.components(separatedBy: ftsSpecialChars).joined(separator: " ")
                let ws = san.split(separator: " ").filter { !$0.isEmpty }
                guard !ws.isEmpty else { continue }
                let r4 = ftsSearch(ws.map { "\($0)*" }.joined(separator: " "), limit: limit)
                if !r4.isEmpty { return prioritized(r4, query: q) }
            }
            // Also try a pure LIKE with each split position (catches names not in aliases).
            for i in 1..<qLower.count {
                let idx = qLower.index(qLower.startIndex, offsetBy: i)
                let candidate = String(qLower[..<idx]) + " " + String(qLower[idx...])
                let r4b = likeSearch("%\(candidate)%", limit: limit)
                if !r4b.isEmpty { return prioritized(r4b, query: q) }
            }
        }

        return []
    }

    /// Re-sorts results so exact matches appear first, then prefix matches, then the rest.
    /// Within each tier, shorter names rank higher (more direct match).
    private func prioritized(_ results: [FoodTemplate], query q: String) -> [FoodTemplate] {
        let qLower = q.lowercased()
        return results.sorted { a, b in
            let aLower = a.name.lowercased()
            let bLower = b.name.lowercased()
            let aExact = aLower == qLower
            let bExact = bLower == qLower
            if aExact != bExact { return aExact }
            let aPrefix = aLower.hasPrefix(qLower)
            let bPrefix = bLower.hasPrefix(qLower)
            if aPrefix != bPrefix { return aPrefix }
            return a.name.count < b.name.count
        }
    }

    // MARK: - Match (for NL food resolution)

    /// Exact name match first, then prefix FTS. Returns nil if nothing matches.
    func matchFood(_ name: String) -> FoodTemplate? {
        guard isReady else { return nil }
        let q = name.trimmingCharacters(in: .whitespaces)
        return exactSearch(q) ?? search(q, limit: 1).first
    }

    // MARK: - JSON Import

    /// Imports foods from a JSON file. Replaces existing entries with the same name.
    /// Returns the number of rows successfully inserted/replaced.
    @discardableResult
    func importJSON(from url: URL) async throws -> Int {
        let data = try Data(contentsOf: url)
        let items = try JSONDecoder().decode([JSONFoodItem].self, from: data)
        let n = insertJSONBatch(items)
        count = rowCount()
        return n
    }

    // MARK: - Schema

    private func createSchema() {
        exec("""
            CREATE TABLE IF NOT EXISTS foods (
                rowid       INTEGER PRIMARY KEY AUTOINCREMENT,
                name        TEXT    NOT NULL,
                category    TEXT    NOT NULL,
                kcal        REAL    NOT NULL DEFAULT 0,
                protein     REAL    NOT NULL DEFAULT 0,
                carbs       REAL    NOT NULL DEFAULT 0,
                fat         REAL    NOT NULL DEFAULT 0,
                fiber       REAL    NOT NULL DEFAULT 0,
                sugar       REAL    NOT NULL DEFAULT 0,
                sat_fat     REAL    NOT NULL DEFAULT 0,
                sodium      REAL    NOT NULL DEFAULT 0,
                cholesterol REAL    NOT NULL DEFAULT 0,
                serving_g   INTEGER NOT NULL DEFAULT 100,
                serving_label TEXT,
                UNIQUE(name)
            )
        """)

        exec("""
            CREATE TABLE IF NOT EXISTS custom_foods (
                id           TEXT    PRIMARY KEY,
                user_id      TEXT    NOT NULL,
                name         TEXT    NOT NULL,
                category     TEXT    NOT NULL,
                kcal         REAL    NOT NULL DEFAULT 0,
                protein      REAL    NOT NULL DEFAULT 0,
                carbs        REAL    NOT NULL DEFAULT 0,
                fat          REAL    NOT NULL DEFAULT 0,
                fiber        REAL    NOT NULL DEFAULT 0,
                sugar        REAL    NOT NULL DEFAULT 0,
                sat_fat      REAL    NOT NULL DEFAULT 0,
                sodium       REAL    NOT NULL DEFAULT 0,
                cholesterol  REAL    NOT NULL DEFAULT 0,
                serving_g    INTEGER NOT NULL DEFAULT 100,
                serving_label TEXT,
                created_at   INTEGER NOT NULL DEFAULT 0,
                UNIQUE(name, user_id)
            )
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_custom_foods_user ON custom_foods(user_id)")
        exec("""
            CREATE INDEX IF NOT EXISTS idx_foods_category ON foods(category)
        """)
        exec("""
            CREATE VIRTUAL TABLE IF NOT EXISTS foods_fts USING fts5(
                name,
                content=foods,
                content_rowid=rowid,
                tokenize='unicode61'
            )
        """)
        exec("""
            CREATE TRIGGER IF NOT EXISTS foods_ai AFTER INSERT ON foods BEGIN
                INSERT INTO foods_fts(rowid, name) VALUES (new.rowid, new.name);
            END
        """)
        exec("""
            CREATE TRIGGER IF NOT EXISTS foods_ad AFTER DELETE ON foods BEGIN
                INSERT INTO foods_fts(foods_fts, rowid, name) VALUES ('delete', old.rowid, old.name);
            END
        """)
        exec("""
            CREATE TRIGGER IF NOT EXISTS foods_au AFTER UPDATE ON foods BEGIN
                INSERT INTO foods_fts(foods_fts, rowid, name) VALUES ('delete', old.rowid, old.name);
                INSERT INTO foods_fts(rowid, name) VALUES (new.rowid, new.name);
            END
        """)
    }

    // MARK: - Insert

    private func insertBatch(_ templates: [FoodTemplate]) {
        guard let db else { return }
        exec("BEGIN TRANSACTION")
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL(orReplace: false), -1, &stmt, nil) == SQLITE_OK else {
            exec("ROLLBACK"); return
        }
        defer { sqlite3_finalize(stmt) }
        for t in templates {
            sqlite3_reset(stmt)
            bind(stmt!, 1, t.name)
            bind(stmt!, 2, t.category.rawValue)
            sqlite3_bind_double(stmt!, 3, t.kcal)
            sqlite3_bind_double(stmt!, 4, t.protein)
            sqlite3_bind_double(stmt!, 5, t.carbs)
            sqlite3_bind_double(stmt!, 6, t.fat)
            sqlite3_bind_double(stmt!, 7, t.fiber)
            sqlite3_bind_double(stmt!, 8, t.sugar)
            sqlite3_bind_double(stmt!, 9, t.saturatedFat)
            sqlite3_bind_double(stmt!, 10, t.sodium)
            sqlite3_bind_double(stmt!, 11, t.cholesterol)
            sqlite3_bind_int(stmt!, 12, Int32(t.defaultServingG))
            bindOpt(stmt!, 13, t.servingLabel)
            sqlite3_step(stmt)
        }
        exec("COMMIT")
    }

    private func insertJSONBatch(_ items: [JSONFoodItem]) -> Int {
        guard let db else { return 0 }
        exec("BEGIN TRANSACTION")
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL(orReplace: true), -1, &stmt, nil) == SQLITE_OK else {
            exec("ROLLBACK"); return 0
        }
        defer { sqlite3_finalize(stmt) }
        var n = 0
        for item in items {
            sqlite3_reset(stmt)
            let cat = FoodCategory(rawValue: item.category) ?? .meals
            bind(stmt!, 1, item.name)
            bind(stmt!, 2, cat.rawValue)
            sqlite3_bind_double(stmt!, 3, item.kcal)
            sqlite3_bind_double(stmt!, 4, item.protein)
            sqlite3_bind_double(stmt!, 5, item.carbs)
            sqlite3_bind_double(stmt!, 6, item.fat)
            sqlite3_bind_double(stmt!, 7, item.fiber ?? 0)
            sqlite3_bind_double(stmt!, 8, item.sugar ?? 0)
            sqlite3_bind_double(stmt!, 9, item.saturatedFat ?? 0)
            sqlite3_bind_double(stmt!, 10, item.sodium ?? 0)
            sqlite3_bind_double(stmt!, 11, item.cholesterol ?? 0)
            sqlite3_bind_int(stmt!, 12, Int32(item.defaultServingG))
            bindOpt(stmt!, 13, item.servingLabel)
            if sqlite3_step(stmt) == SQLITE_DONE { n += 1 }
        }
        exec("COMMIT")
        return n
    }

    private func insertSQL(orReplace: Bool) -> String {
        let conflict = orReplace ? "OR REPLACE" : "OR IGNORE"
        return """
            INSERT \(conflict) INTO foods
              (name, category, kcal, protein, carbs, fat,
               fiber, sugar, sat_fat, sodium, cholesterol, serving_g, serving_label)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
        """
    }

    // MARK: - Queries

    private func ftsSearch(_ ftsQuery: String, limit: Int) -> [FoodTemplate] {
        guard let db else { return [] }
        let sql = """
            SELECT f.name, f.category, f.kcal, f.protein, f.carbs, f.fat,
                   f.fiber, f.sugar, f.sat_fat, f.sodium, f.cholesterol,
                   f.serving_g, f.serving_label
            FROM foods f
            JOIN foods_fts ON f.rowid = foods_fts.rowid
            WHERE foods_fts MATCH ?
            ORDER BY rank
            LIMIT ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(stmt!, 1, ftsQuery)
        sqlite3_bind_int(stmt!, 2, Int32(limit))
        return collectRows(stmt!)
    }

    private func likeSearch(_ pattern: String, limit: Int) -> [FoodTemplate] {
        guard let db else { return [] }
        let sql = """
            SELECT name, category, kcal, protein, carbs, fat,
                   fiber, sugar, sat_fat, sodium, cholesterol, serving_g, serving_label
            FROM foods WHERE name LIKE ? LIMIT ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(stmt!, 1, pattern)
        sqlite3_bind_int(stmt!, 2, Int32(limit))
        return collectRows(stmt!)
    }

    private func exactSearch(_ name: String) -> FoodTemplate? {
        guard let db else { return nil }
        let sql = """
            SELECT name, category, kcal, protein, carbs, fat,
                   fiber, sugar, sat_fat, sodium, cholesterol, serving_g, serving_label
            FROM foods WHERE name = ? COLLATE NOCASE LIMIT 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        bind(stmt!, 1, name)
        return collectRows(stmt!).first
    }

    /// Returns up to `limit` foods in `category`, ordered alphabetically.
    /// When `userID` is provided, the user's custom foods in that category are prepended.
    func foods(in category: FoodCategory, userID: UUID? = nil, limit: Int = 200) -> [FoodTemplate] {
        guard isReady, let db else { return [] }

        var customResults: [FoodTemplate] = []
        if let userID {
            customResults = customFoodsInCategory(category, userID: userID)
        }

        let sql = """
            SELECT name, category, kcal, protein, carbs, fat,
                   fiber, sugar, sat_fat, sodium, cholesterol, serving_g, serving_label
            FROM foods WHERE category = ? ORDER BY name LIMIT ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return customResults }
        defer { sqlite3_finalize(stmt) }
        bind(stmt!, 1, category.rawValue)
        sqlite3_bind_int(stmt!, 2, Int32(limit))
        let sharedResults = collectRows(stmt!)

        if customResults.isEmpty { return sharedResults }
        let customNames = Set(customResults.map { $0.name.lowercased() })
        return customResults + sharedResults.filter { !customNames.contains($0.name.lowercased()) }
    }

    private func rowCount() -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM foods", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    // MARK: - Row decoding

    private func collectRows(_ stmt: OpaquePointer) -> [FoodTemplate] {
        var out: [FoodTemplate] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let t = decodeRow(stmt) { out.append(t) }
        }
        return out
    }

    private func decodeRow(_ stmt: OpaquePointer) -> FoodTemplate? {
        guard let namePtr = sqlite3_column_text(stmt, 0),
              let catPtr  = sqlite3_column_text(stmt, 1) else { return nil }
        let label: String? = sqlite3_column_type(stmt, 12) != SQLITE_NULL
            ? sqlite3_column_text(stmt, 12).map { String(cString: $0) }
            : nil
        return FoodTemplate(
            name:            String(cString: namePtr),
            category:        FoodCategory(rawValue: String(cString: catPtr)) ?? .meals,
            kcal:            sqlite3_column_double(stmt, 2),
            protein:         sqlite3_column_double(stmt, 3),
            carbs:           sqlite3_column_double(stmt, 4),
            fat:             sqlite3_column_double(stmt, 5),
            fiber:           sqlite3_column_double(stmt, 6),
            sugar:           sqlite3_column_double(stmt, 7),
            saturatedFat:    sqlite3_column_double(stmt, 8),
            sodium:          sqlite3_column_double(stmt, 9),
            cholesterol:     sqlite3_column_double(stmt, 10),
            defaultServingG: Int(sqlite3_column_int(stmt, 11)),
            servingLabel:    label
        )
    }

    // custom_foods rows have id TEXT as column 0, then name/category/macros/serving
    private func collectCustomRows(_ stmt: OpaquePointer) -> [FoodTemplate] {
        var out: [FoodTemplate] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let t = decodeCustomRow(stmt) { out.append(t) }
        }
        return out
    }

    private func decodeCustomRow(_ stmt: OpaquePointer) -> FoodTemplate? {
        guard let idPtr   = sqlite3_column_text(stmt, 0),
              let namePtr = sqlite3_column_text(stmt, 1),
              let catPtr  = sqlite3_column_text(stmt, 2) else { return nil }
        let customFoodID = UUID(uuidString: String(cString: idPtr))
        let label: String? = sqlite3_column_type(stmt, 13) != SQLITE_NULL
            ? sqlite3_column_text(stmt, 13).map { String(cString: $0) }
            : nil
        return FoodTemplate(
            name:            String(cString: namePtr),
            category:        FoodCategory(rawValue: String(cString: catPtr)) ?? .meals,
            kcal:            sqlite3_column_double(stmt, 3),
            protein:         sqlite3_column_double(stmt, 4),
            carbs:           sqlite3_column_double(stmt, 5),
            fat:             sqlite3_column_double(stmt, 6),
            fiber:           sqlite3_column_double(stmt, 7),
            sugar:           sqlite3_column_double(stmt, 8),
            saturatedFat:    sqlite3_column_double(stmt, 9),
            sodium:          sqlite3_column_double(stmt, 10),
            cholesterol:     sqlite3_column_double(stmt, 11),
            defaultServingG: Int(sqlite3_column_int(stmt, 12)),
            servingLabel:    label,
            isCustom:        true,
            customFoodID:    customFoodID
        )
    }

    private func customFoodsLikeSearch(_ pattern: String, userID: UUID, limit: Int) -> [FoodTemplate] {
        guard let db else { return [] }
        let sql = """
            SELECT id, name, category, kcal, protein, carbs, fat,
                   fiber, sugar, sat_fat, sodium, cholesterol, serving_g, serving_label
            FROM custom_foods WHERE user_id = ? AND name LIKE ? ORDER BY name LIMIT ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(stmt!, 1, userID.uuidString)
        bind(stmt!, 2, pattern)
        sqlite3_bind_int(stmt!, 3, Int32(limit))
        return collectCustomRows(stmt!)
    }

    private func customFoodsInCategory(_ category: FoodCategory, userID: UUID, limit: Int = 200) -> [FoodTemplate] {
        guard let db else { return [] }
        let sql = """
            SELECT id, name, category, kcal, protein, carbs, fat,
                   fiber, sugar, sat_fat, sodium, cholesterol, serving_g, serving_label
            FROM custom_foods WHERE user_id = ? AND category = ? ORDER BY name LIMIT ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(stmt!, 1, userID.uuidString)
        bind(stmt!, 2, category.rawValue)
        sqlite3_bind_int(stmt!, 3, Int32(limit))
        return collectCustomRows(stmt!)
    }

    // MARK: - SQLite helpers

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        guard let db else { return false }
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func bind(_ stmt: OpaquePointer, _ idx: Int32, _ value: String) {
        value.withCString { sqlite3_bind_text(stmt, idx, $0, -1, sqTransient) }
    }

    private func bindOpt(_ stmt: OpaquePointer, _ idx: Int32, _ value: String?) {
        if let v = value { bind(stmt, idx, v) } else { sqlite3_bind_null(stmt, idx) }
    }

    // MARK: - Paths

    private static func defaultPath() -> String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DailyFitness/foods.db").path
    }

    private var ftsSpecialChars: CharacterSet { CharacterSet(charactersIn: "\"*()^~+") }

    // Maps lowercase search terms to the canonical name prefix stored in the DB.
    private static let brandAliases: [String: String] = [
        // Din Tai Fung — items are stored as "DTF · ..."
        "dtf": "DTF",
        "dft": "DTF",
        "din tai": "DTF",
        "din tai fung": "DTF",
        // Proper Food — items stored as "Proper Food – ..."
        "proper foods": "Proper Food",
        // Joe and the Juice — items stored as "Joe and the Juice – ..."
        "jj": "Joe and the Juice",
        "joe juice": "Joe and the Juice",
        "joe & the juice": "Joe and the Juice",
        // Alcohol brand short names
        "jd": "Jack Daniel",
        "jack daniels": "Jack Daniel",
        "makers mark": "Maker's Mark",
        "titos": "Tito's",
        "tito": "Tito's",
        "grey goose": "Grey Goose",
        "jw": "Johnnie Walker",
        "johnnie walker": "Johnnie Walker",
        "hennessy": "Hennessy",
        "remy": "Rémy Martin",
        "remy martin": "Rémy Martin",
        "patron": "Patrón",
        "don julio": "Don Julio",
        "casamigos": "Casamigos",
        "white claw": "White Claw",
        "white claws": "White Claw",
        "bud light": "Bud Light",
        "budweiser": "Budweiser",
        "miller lite": "Miller Lite",
        "coors light": "Coors Light",
        "michelob ultra": "Michelob Ultra",
        "corona extra": "Corona Extra",
        "modelo": "Modelo",
        "heineken": "Heineken",
        "stella": "Stella Artois",
        "guinness": "Guinness",
        "sam adams": "Sam Adams",
        "blue moon": "Blue Moon",
        "lagunitas": "Lagunitas",
        "sierra nevada": "Sierra Nevada",
        "angry orchard": "Angry Orchard",
        "twisted tea": "Twisted Tea",
        "high noon": "High Noon",
        "captain morgan": "Captain Morgan",
        "bacardi": "Bacardi",
        "malibu": "Malibu",
        "tanqueray": "Tanqueray",
        "hendricks": "Hendrick's",
        "bombay": "Bombay Sapphire",
        "crown royal": "Crown Royal",
        "glenfiddich": "Glenfiddich",
        "macallan": "Macallan",
        "buffalo trace": "Buffalo Trace",
        "pbr": "Pabst Blue Ribbon",
        "yuengling": "Yuengling",
    ]
}

// MARK: - JSON import schema

extension FoodStore {
    /// Mirrors the FoodTemplate fields. All micro/macro fields are optional for forward compatibility.
    struct JSONFoodItem: Decodable {
        let name: String
        let category: String
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let fiber: Double?
        let sugar: Double?
        let saturatedFat: Double?
        let sodium: Double?
        let cholesterol: Double?
        let defaultServingG: Int
        let servingLabel: String?
    }
}

// MARK: - SQLite TRANSIENT destructor

private let sqTransient = unsafeBitCast(-1 as Int, to: sqlite3_destructor_type.self)
