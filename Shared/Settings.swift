import Foundation

struct KeyboardLayout: Codable, Identifiable, Equatable {
    var id: String
    var label: String
    var space: String
    var title: String
    var locale: String
    var rows: [[String]]
    var accents: [String: [String]] = [:]
    var shift: [String: String] = [:]
    var dictionary: String?
    var hasCase = true
    var composer = "none"
    var autoCorrect = true
    var rtl = false

    var displayName: String {
        if Locale.preferredLanguages.first?.hasPrefix("ru") == true { return title }
        if ["pinyin", "kana", "telex"].contains(composer) { return space }
        return Locale(identifier: "en").localizedString(forIdentifier: locale) ?? space
    }

    static func tokens(_ row: String) -> [String] {
        row.contains(where: \.isWhitespace)
            ? row.split(whereSeparator: \.isWhitespace).map(String.init)
            : row.unicodeScalars.map(String.init)
    }
}

enum Resources {
    static func url(_ path: String) -> URL? {
        let extensionResources = Bundle.main.builtInPlugInsURL?.appendingPathComponent("ExpressiveExtension.appex/KeyboardData")
        let base = Bundle.main.bundleURL.pathExtension == "appex"
            ? Bundle.main.resourceURL?.appendingPathComponent("KeyboardData") : extensionResources
        return base?.appendingPathComponent(path)
    }

    static func data(_ path: String) -> Data? {
        guard let url = url(path) else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    static let layouts: [KeyboardLayout] = {
        if let data = data("layouts.json"),
           let layouts = try? JSONDecoder().decode([KeyboardLayout].self, from: data),
           !layouts.isEmpty { return layouts }
        return [KeyboardLayout(id: "en", label: "EN", space: "English", title: "Английский",
                               locale: "en-US", rows: ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map(KeyboardLayout.tokens),
                               dictionary: "en")]
    }()
}

enum Design: String, Codable, CaseIterable, Identifiable {
    case expressive, material, glass, classic, neon, neumorph, minecraft, samsung, nothing
    var id: String { rawValue }
    var title: String {
        switch self {
        case .expressive: return "Material 3 Expressive"
        case .material: return "Material 3"
        case .glass: return "Liquid Glass"
        case .classic: return "Classic"
        case .neon: return "Neon"
        case .neumorph: return "Neumorphism"
        case .minecraft: return "Minecraft-inspired"
        case .samsung: return "One UI-inspired"
        case .nothing: return "Nothing-inspired"
        }
    }
    var skinFile: String? {
        switch self {
        case .expressive: return nil
        case .glass: return "liquid_glass"
        default: return rawValue
        }
    }
    var radius: Double {
        switch self {
        case .expressive: return 16
        case .classic: return 6
        case .material: return 8
        case .samsung: return 9
        case .neon: return 10
        case .minecraft: return 0
        default: return 14
        }
    }
}

struct Preferences: Codable {
    var design: Design = .expressive
    var shapes = 1
    var languages = ["en", "ru"]
    var layouts: [String: [[String]]] = [:]
    var height = 46.0
    var spacing = 4.0
    var radius = 16.0
    var width = 1.0
    var hand = 0
    var numberRow = false
    var suggestions = true
    var autocorrect = true
    var autoCap = true
    var glide = true
    var haptics = true
    var intensity = 0.5
    var sound = false
    var incognito = false
    var learn = true
    var emojiStyle = "system"
    var tint = ""
    var gifKey = ""
    var translationTarget = "en"
    var plugins: [Plugin] = []
    var disabledPlugins: Set<String> = []
    var skinPlugin = ""
    var hasPhoto = false
    var hasFont = false
    var setup = false

    mutating func normalize() {
        height = min(max(height, 34), 62)
        spacing = min(max(spacing, 2), 8)
        radius = min(max(radius, 0), 24)
        width = min(max(width, 0.72), 1)
        shapes = min(max(shapes, 0), 2)
        hand = min(max(hand, -1), 1)
        intensity = min(max(intensity, 0.1), 1)
        var known = Set<String>()
        plugins = plugins.filter { known.insert($0.id).inserted }
        known.removeAll()
        languages = languages.filter { known.insert($0).inserted }
        layouts = layouts.filter { _, rows in
            (1...6).contains(rows.count) && rows.allSatisfy { row in
                (1...18).contains(row.count) && row.allSatisfy { !$0.isEmpty && $0.count <= 12 }
            }
        }
    }

    var allLayouts: [KeyboardLayout] {
        var installed = Resources.layouts
        for plugin in activePlugins {
            for layout in plugin.keyboardLanguages {
                if let index = installed.firstIndex(where: { $0.id == layout.id }) {
                    installed[index] = layout
                } else {
                    installed.append(layout)
                }
            }
        }
        return installed
    }

    var enabledLayouts: [KeyboardLayout] {
        let installed = allLayouts
        let current = languages.compactMap { id in installed.first { $0.id == id } }
        return (current.isEmpty ? [Resources.layouts.first { $0.id == "en" } ?? Resources.layouts[0]] : current).map { language in
            var language = language
            let rows = layouts[language.id] ?? activePlugins.reversed().compactMap { $0.layoutOverrides[language.id] }.first
            if let rows, !rows.isEmpty, rows.allSatisfy({ !$0.isEmpty }) { language.rows = rows }
            return language
        }
    }

    var availablePlugins: [Plugin] {
        Plugin.builtIn.filter { item in !plugins.contains { $0.id == item.id } } + plugins
    }

    var activePlugins: [Plugin] {
        availablePlugins.filter { !disabledPlugins.contains($0.id) && ($0.enabledByDefault || plugins.contains($0)) }
    }

    mutating func setPlugin(_ plugin: Plugin, enabled: Bool) {
        if enabled {
            disabledPlugins.remove(plugin.id)
            if !plugin.enabledByDefault && !plugins.contains(plugin) { plugins.append(plugin) }
        } else {
            disabledPlugins.insert(plugin.id)
        }
    }
}

enum SharedStore {
    static var groupID: String {
        Bundle.main.object(forInfoDictionaryKey: "ExpressiveAppGroup") as? String ?? "group.org.expressive.keyboard.ios"
    }

    static var container: URL? {
        #if os(iOS)
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
        #else
        return nil
        #endif
    }

    static func file(_ name: String) -> URL? { container?.appendingPathComponent(name) }

    static func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let url = file(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func write<T: Encodable>(_ value: T, _ name: String) throws {
        guard let url = file(name) else { throw CocoaError(.fileNoSuchFile) }
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    static func load() -> Preferences {
        var settings = read(Preferences.self, "preferences.json") ?? Preferences()
        settings.normalize()
        return settings
    }
    static func save(_ settings: Preferences) throws { try write(settings, "preferences.json") }
}
