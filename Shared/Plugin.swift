import Foundation

struct Plugin: Codable, Identifiable, Equatable {
    struct Action: Decodable, Identifiable {
        let title: String
        let icon: String?
        let type: String
        let text: String?
        let key: String?
        let url: String?
        var id: String { "\(type):\(title)" }
    }

    struct Symbols: Decodable, Identifiable {
        let title: String
        let icon: String?
        let items: [String]
        var id: String { title }
    }

    let id: String
    let name: String
    let definition: Data
    let script: String?
    let enabledByDefault: Bool

    var object: [String: Any] { Self.object(definition) ?? [:] }
    var permissions: [String] { object["permissions"] as? [String] ?? [] }
    var actions: [Action] { decode("actions") ?? [] }
    var symbols: [Symbols] { decode("symbols") ?? [] }
    var shortcuts: [String: String] { object["shortcuts"] as? [String: String] ?? [:] }
    var skin: [String: Any]? { object["skin"] as? [String: Any] }
    var layoutOverrides: [String: [[String]]] {
        (object["layouts"] as? [String: Any] ?? [:]).compactMapValues(Self.rows)
    }
    var keyboardLanguages: [KeyboardLayout] {
        (object["languages"] as? [[String: Any]] ?? []).compactMap { item in
            guard let id = item["id"] as? String, let rows = Self.rows(item["rows"]) else { return nil }
            let title = item["title"] as? String ?? id
            return KeyboardLayout(
                id: id, label: item["label"] as? String ?? id.uppercased(),
                space: item["spaceLabel"] as? String ?? title, title: title,
                locale: item["locale"] as? String ?? id, rows: rows,
                accents: item["accents"] as? [String: [String]] ?? [:],
                shift: item["shift"] as? [String: String] ?? [:],
                dictionary: item["dict"] as? String, hasCase: item["hasCase"] as? Bool ?? true,
                composer: (item["composer"] as? String ?? "none").lowercased(),
                autoCorrect: item["autoCorrect"] as? Bool ?? true, rtl: item["rtl"] as? Bool ?? false)
        }
    }

    private func decode<T: Decodable>(_ field: String) -> T? {
        guard let value = object[field], JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func rows(_ value: Any?) -> [[String]]? {
        let parsed = (value as? [[String]]) ?? (value as? [String])?.map(KeyboardLayout.tokens)
        guard let parsed, (1...6).contains(parsed.count),
              parsed.allSatisfy({ (1...18).contains($0.count) && $0.allSatisfy { !$0.isEmpty && $0.count <= 12 } })
        else { return nil }
        return parsed
    }

    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func load(_ data: Data, type: String, main: String? = nil) throws -> Plugin {
        guard data.count <= 2_000_000 else { throw ImportError.invalid }
        let manifest: Data
        var script = main
        if type == "js" {
            guard let text = String(data: data, encoding: .utf8),
                  let start = text.range(of: "/* @plugin"),
                  let end = text.range(of: "*/", range: start.upperBound..<text.endIndex) else { throw ImportError.invalid }
            manifest = Data(text[start.upperBound..<end.lowerBound].utf8)
            script = text
        } else {
            manifest = data
        }
        guard let object = object(manifest), let id = object["id"] as? String,
              id.range(of: "^[A-Za-z0-9._-]{2,64}$", options: .regularExpression) != nil,
              let name = object["name"] as? String, !name.isEmpty else { throw ImportError.invalid }
        script = script ?? (object["script"] as? String) ?? (object["script"] as? [String])?.joined(separator: "\n")
        return Plugin(id: id, name: name, definition: manifest, script: script,
                      enabledByDefault: object["enabledByDefault"] as? Bool ?? true)
    }

    static let builtIn: [Plugin] = {
        guard let path = Resources.url("plugins"),
              let files = try? FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)
        else { return [] }
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap {
            guard let data = try? Data(contentsOf: $0) else { return nil }
            return try? load(data, type: $0.pathExtension)
        }
    }()

    static func expand(_ text: String, now: Date = Date(), locale: Locale = .current) -> String {
        let pattern = #/\{(date|time|datetime)(?::([^}]+))?\}/#
        var result = text
        for match in text.matches(of: pattern).reversed() {
            let formatter = DateFormatter()
            formatter.locale = locale
            if let format = match.2 {
                formatter.dateFormat = String(format)
            } else {
                formatter.dateStyle = match.1 == "time" ? .none : .medium
                formatter.timeStyle = match.1 == "date" ? .none : .short
            }
            result.replaceSubrange(match.range, with: formatter.string(from: now))
        }
        return result
    }

    enum ImportError: LocalizedError {
        case invalid, archive
        var errorDescription: String? {
            switch self {
            case .invalid: return "Invalid Expressive plugin manifest."
            case .archive: return "The ZIP must contain plugin.json and fit within 8 MB."
            }
        }
    }
}
