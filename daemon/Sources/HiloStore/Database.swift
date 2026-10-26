import Foundation
import SQLite3

public struct StoreError: Error, CustomStringConvertible {
    public var description: String
}

public enum SQLValue: Equatable, Sendable {
    case int(Int)
    case text(String)
    case null
}

public protocol SQLBindable {
    var sqlValue: SQLValue { get }
}

extension Int: SQLBindable { public var sqlValue: SQLValue { .int(self) } }
extension String: SQLBindable { public var sqlValue: SQLValue { .text(self) } }
extension Optional: SQLBindable where Wrapped: SQLBindable {
    public var sqlValue: SQLValue { self?.sqlValue ?? .null }
}

private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// One SQLite connection; opened in serialized mode so callers on different threads are safe.
final class Database: @unchecked Sendable {
    private var handle: OpaquePointer?

    init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
            sqlite3_close(handle)
            throw StoreError(description: "\(path): \(message)")
        }
        sqlite3_busy_timeout(handle, 2000)
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA foreign_keys = ON")
    }

    deinit { sqlite3_close(handle) }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
    }

    @discardableResult
    func run(_ sql: String, _ args: [SQLBindable] = []) throws -> Int {
        try withStatement(sql, args) { statement in
            guard sqlite3_step(statement) == SQLITE_DONE else { throw error() }
        }
        return Int(sqlite3_last_insert_rowid(handle))
    }

    func rows(_ sql: String, _ args: [SQLBindable] = []) throws -> [Row] {
        try withStatement(sql, args) { statement in
            var rows: [Row] = []
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW: rows.append(Row(statement))
                case SQLITE_DONE: return rows
                default: throw error()
                }
            }
        }
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func withStatement<T>(_ sql: String, _ args: [SQLBindable], _ body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw error() }
        defer { sqlite3_finalize(statement) }
        for (i, arg) in args.enumerated() {
            let index = Int32(i + 1)
            switch arg.sqlValue {
            case .int(let v): sqlite3_bind_int64(statement, index, Int64(v))
            case .text(let v): sqlite3_bind_text(statement, index, v, -1, transient)
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        return try body(statement)
    }

    private func error() -> StoreError {
        StoreError(description: String(cString: sqlite3_errmsg(handle)))
    }
}

struct Row {
    private var values: [SQLValue] = []

    init(_ statement: OpaquePointer) {
        for i in 0..<sqlite3_column_count(statement) {
            switch sqlite3_column_type(statement, i) {
            case SQLITE_INTEGER: values.append(.int(Int(sqlite3_column_int64(statement, i))))
            case SQLITE_NULL: values.append(.null)
            default: values.append(.text(String(cString: sqlite3_column_text(statement, i))))
            }
        }
    }

    func int(_ i: Int) -> Int? {
        if case .int(let v) = values[i] { return v }
        return nil
    }

    func text(_ i: Int) -> String? {
        if case .text(let v) = values[i] { return v }
        return nil
    }
}
