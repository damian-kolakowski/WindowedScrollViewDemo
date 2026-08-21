import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Plain Swift + raw SQLite3 C API, no ORM, no reactive Flow machinery — a baseline to
/// contrast against the Room-KMP-backed screens (TodoiOSApp), which get reactive
/// cross-writer invalidation "for free" from Room's InvalidationTracker. Here, callers
/// (TodoStore) must manually re-fetch after every mutation.
final class TodoDatabase {
    private var db: OpaquePointer?

    init(seedCount: Int = 5000) {
        let fileURL = try! FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("todos_native.db")

        guard sqlite3_open(fileURL.path, &db) == SQLITE_OK else {
            fatalError("Unable to open database at \(fileURL.path)")
        }

        createTableIfNeeded()
        seedIfEmpty(count: seedCount)
    }

    deinit {
        sqlite3_close(db)
    }

    private func createTableIfNeeded() {
        exec("""
        CREATE TABLE IF NOT EXISTS todos (
            id TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL,
            isDone INTEGER NOT NULL,
            sortOrder REAL NOT NULL
        );
        """)
    }

    private func seedIfEmpty(count: Int) {
        guard rowCount() == 0 else { return }
        exec("BEGIN TRANSACTION;")
        for i in 1...count {
            insert(id: UUID().uuidString, title: "Todo item \(i)", isDone: i % 3 == 0, sortOrder: Double(i))
        }
        exec("COMMIT;")
    }

    func rowCount() -> Int {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        var result = 0
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM todos;", -1, &statement, nil) == SQLITE_OK,
           sqlite3_step(statement) == SQLITE_ROW {
            result = Int(sqlite3_column_int(statement, 0))
        }
        return result
    }

    func fetchAll() -> [Todo] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        var todos: [Todo] = []
        let sql = "SELECT id, title, isDone, sortOrder FROM todos ORDER BY sortOrder ASC;"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return todos }
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(statement, 0))
            let title = String(cString: sqlite3_column_text(statement, 1))
            let isDone = sqlite3_column_int(statement, 2) != 0
            let sortOrder = sqlite3_column_double(statement, 3)
            todos.append(Todo(id: id, title: title, isDone: isDone, sortOrder: sortOrder))
        }
        return todos
    }

    func fetchPage(limit: Int, offset: Int) -> [Todo] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        var todos: [Todo] = []
        let sql = "SELECT id, title, isDone, sortOrder FROM todos ORDER BY sortOrder ASC LIMIT ? OFFSET ?;"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return todos }
        sqlite3_bind_int(statement, 1, Int32(limit))
        sqlite3_bind_int(statement, 2, Int32(offset))
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(statement, 0))
            let title = String(cString: sqlite3_column_text(statement, 1))
            let isDone = sqlite3_column_int(statement, 2) != 0
            let sortOrder = sqlite3_column_double(statement, 3)
            todos.append(Todo(id: id, title: title, isDone: isDone, sortOrder: sortOrder))
        }
        return todos
    }

    func insert(id: String, title: String, isDone: Bool, sortOrder: Double) {
        let sql = "INSERT OR REPLACE INTO todos (id, title, isDone, sortOrder) VALUES (?, ?, ?, ?);"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 3, isDone ? 1 : 0)
        sqlite3_bind_double(statement, 4, sortOrder)
        sqlite3_step(statement)
    }

    func addTodo(title: String) {
        insert(id: UUID().uuidString, title: title, isDone: false, sortOrder: minSortOrder() - 1)
    }

    func toggleDone(id: String) {
        run("UPDATE todos SET isDone = NOT isDone WHERE id = ?;", textParams: [id])
    }

    func updateTitle(id: String, title: String) {
        run("UPDATE todos SET title = ? WHERE id = ?;", textParams: [title, id])
    }

    func delete(id: String) {
        run("DELETE FROM todos WHERE id = ?;", textParams: [id])
    }

    private func minSortOrder() -> Double {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        var result: Double = 1
        if sqlite3_prepare_v2(db, "SELECT MIN(sortOrder) FROM todos;", -1, &statement, nil) == SQLITE_OK,
           sqlite3_step(statement) == SQLITE_ROW {
            result = sqlite3_column_double(statement, 0)
        }
        return result
    }

    private func run(_ sql: String, textParams: [String]) {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        for (index, param) in textParams.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), param, -1, SQLITE_TRANSIENT)
        }
        sqlite3_step(statement)
    }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        var errMsg: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if result != SQLITE_OK, let errMsg {
            print("SQLite error: \(String(cString: errMsg))")
            sqlite3_free(errMsg)
            return false
        }
        return true
    }
}
