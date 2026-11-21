import Foundation
import SQLite3

final class Lexicon {
    private var database: OpaquePointer?

    init(url: URL? = Resources.url("lexicon.sqlite3")) {
        guard let url else { return }
        if sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            sqlite3_close(database)
            database = nil
        }
    }

    deinit { sqlite3_close(database) }

    private func query(_ sql: String, _ args: [String]) -> [String] {
        guard let database else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        let copy = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, argument) in args.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), argument, -1, copy)
        }
        var result: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) { result.append(String(cString: text)) }
        }
        return result
    }

    func complete(_ input: String, language: String) -> [String] {
        let text = input.lowercased()
        guard !text.isEmpty else { return [] }
        return query("""
            SELECT output FROM entries WHERE lang=? AND input>=? AND input<? ORDER BY input<>?, rank LIMIT 12
            """, [language, text, text + "\u{10FFFF}", text])
    }

    func correction(_ input: String, language: String) -> String? {
        query("SELECT output FROM typo WHERE lang=? AND input=?", [language, input.lowercased()]).first
    }

    func follow(_ context: [String], language: String) -> [String] {
        let words = context.suffix(2).map { $0.lowercased() }
        guard let last = words.last else { return [] }
        return Array(NSOrderedSet(array: [words.joined(separator: " "), last].reduce(into: [String]()) { result, key in
            result += query("SELECT output FROM context WHERE lang=? AND input=? ORDER BY rank LIMIT 5", [language, key])
        }).array.compactMap { $0 as? String }.prefix(5))
    }

    func glide(_ letters: [String], language: String) -> [String] {
        let observed = letters.reduce(into: [String]()) { path, key in
            if path.last != key { path.append(key) }
        }.joined().lowercased()
        guard observed.count > 1 else { return [] }
        let sql = "SELECT word FROM glide WHERE lang=? AND path=? ORDER BY rank LIMIT 4"
        let exact = query(sql, [language, observed])
        if !exact.isEmpty { return exact }
        let characters = Array(observed)
        return characters.indices.dropFirst().dropLast().prefix(12).flatMap { index in
            var approximate = characters
            approximate.remove(at: index)
            return query(sql, [language, String(approximate)])
        }
    }
}
