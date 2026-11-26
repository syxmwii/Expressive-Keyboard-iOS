import UIKit

enum KeyRole: String {
    case normal = "*"
    case function = "func"
    case accent, space, enter, mode, shift
}

struct KeyStyle {
    var background: UIColor
    var text: UIColor
    var pressedBackground: UIColor
    var pressedText: UIColor
    var radius: CGFloat
    var pressedRadius: CGFloat
    var border: UIColor
    var borderWidth: CGFloat
    var shadow: CGFloat
    var shadowY: CGFloat
    var shadowColor: UIColor
    var fontScale: CGFloat
    var fontWeight: UIFont.Weight
    var press: String
    var pressScale: CGFloat
    var textShadow: UIColor?
}

struct KeyboardTheme {
    struct Orb {
        let color: UIColor
        let x: CGFloat
        let y: CGFloat
        let radius: CGFloat
    }

    let background: UIColor
    let key: UIColor
    let text: UIColor
    let function: UIColor
    let functionText: UIColor
    let accent: UIColor
    let accentText: UIColor
    let border: UIColor
    let secondaryBackground: UIColor?
    let trail: UIColor
    let pattern: UIImage?
    let orbs: [Orb]
    let monospaced: Bool
    let design: Design

    private let skin: [String: Any]
    private let dark: Bool
    private let baseRadius: CGFloat

    init(_ preferences: Preferences, dark: Bool) {
        design = preferences.design
        self.dark = dark
        baseRadius = CGFloat(preferences.radius)
        var raw = Self.skin(for: preferences)
        if dark, let overrides = raw["dark"] as? [String: Any] { raw = Self.merge(raw, overrides) }
        skin = raw
        let colors = raw["colors"] as? [String: Any] ?? [:]
        let keyboard = raw["keyboard"] as? [String: Any]
        let backgroundData = keyboard?["background"] as? [String: Any]
        let gradient = (backgroundData?["colors"] as? [String] ?? []).compactMap(UIColor.init(hex:))
        background = gradient.first ?? Self.pick(colors, "background", dark ? UIColor(hex: "#211E2C")! : UIColor(hex: "#ECE7F8")!, dark: dark)
        secondaryBackground = gradient.dropFirst().first
        key = Self.pick(colors, "key", dark ? UIColor(hex: "#393445")! : UIColor(hex: "#FFFBFF")!, dark: dark)
        text = Self.pick(colors, "keyText", dark ? UIColor(hex: "#F3EDFF")! : UIColor(hex: "#241A38")!, dark: dark)
        function = Self.pick(colors, "func", dark ? UIColor(hex: "#504563")! : UIColor(hex: "#DBD1F0")!, dark: dark)
        functionText = Self.pick(colors, "funcText", text, dark: dark)
        accent = UIColor(hex: preferences.tint) ?? Self.pick(colors, "accent", dark ? UIColor(hex: "#D0BCFF")! : UIColor(hex: "#6C49AB")!, dark: dark)
        if preferences.tint.isEmpty {
            accentText = Self.pick(colors, "accentText", dark ? UIColor(hex: "#2F164E")! : .white, dark: dark)
        } else {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            accent.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            accentText = red * 0.299 + green * 0.587 + blue * 0.114 > 0.60 ? .black : .white
        }
        border = design == .neon ? accent.withAlphaComponent(0.55) : .clear
        trail = (keyboard?["trail"] as? String).flatMap(UIColor.init(hex:)) ?? accent
        monospaced = (keyboard?["font"] as? String) == "pixel"
        pattern = Self.pattern(backgroundData)
        orbs = (backgroundData?["orbs"] as? [[String: Any]] ?? []).compactMap { item in
            guard let value = item["color"] as? String, let color = UIColor(hex: value) else { return nil }
            return Orb(color: color,
                       x: CGFloat((item["x"] as? Double) ?? 0),
                       y: CGFloat((item["y"] as? Double) ?? 0),
                       radius: CGFloat((item["r"] as? Double) ?? 0))
        }
    }

    func style(_ role: KeyRole) -> KeyStyle {
        let base: (UIColor, UIColor)
        switch role {
        case .function, .mode, .shift: base = (function, functionText)
        case .accent, .enter: base = (accent, accentText)
        case .space, .normal: base = (key, text)
        }
        let keys = skin["keys"] as? [String: Any]
        let common = keys?["*"] as? [String: Any] ?? [:]
        let own: [String: Any] = role == .normal ? [:] : (keys?[role.rawValue] as? [String: Any] ?? [:])
        let merged = common.merging(own) { _, new in new }
        func color(_ name: String, _ fallback: UIColor) -> UIColor {
            guard let raw = merged[name] as? String else { return fallback }
            return UIColor(hex: raw) ?? fallback
        }
        func number(_ name: String, _ fallback: CGFloat) -> CGFloat {
            if let value = merged[name] as? Double { return CGFloat(value) }
            if let value = merged[name] as? Int { return CGFloat(value) }
            return fallback
        }
        let radius = number("radius", baseRadius)
        let weight = number("fontWeight", role == .normal ? 500 : 600)
        return KeyStyle(
            background: color("background", base.0),
            text: color("text", base.1),
            pressedBackground: color("pressedBackground", base.0.withAlphaComponent(0.65)),
            pressedText: color("pressedText", base.1),
            radius: radius,
            pressedRadius: number("pressedRadius", radius),
            border: color("border", border),
            borderWidth: number("borderWidth", design == .neon ? 0.8 : 0),
            shadow: number("shadow", 0),
            shadowY: number("shadowY", 1),
            shadowColor: color("shadowColor", UIColor.black.withAlphaComponent(0.25)),
            fontScale: number("fontScale", 1),
            fontWeight: weight >= 700 ? .bold : weight >= 600 ? .semibold : weight >= 500 ? .medium : .regular,
            press: merged["press"] as? String ?? "none",
            pressScale: number("pressScale", 1),
            textShadow: (merged["textShadow"] as? String).flatMap(UIColor.init(hex:))
        )
    }

    private static var loadedDesigns: Set<String> = []
    private static var designSkins: [String: [String: Any]] = [:]
    private static var pluginSkins: [String: [String: Any]] = [:]

    private static func skin(for preferences: Preferences) -> [String: Any] {
        guard let plugin = preferences.activePlugins.first(where: { $0.id == preferences.skinPlugin }) else {
            return fileSkin(preferences.design)
        }
        let key = "\(plugin.id)|\(plugin.definition.hashValue)"
        if let cached = pluginSkins[key] { return cached }
        let skin = plugin.skin ?? [:]
        pluginSkins[key] = skin
        return skin
    }

    private static func fileSkin(_ design: Design) -> [String: Any] {
        if loadedDesigns.contains(design.rawValue) { return designSkins[design.rawValue] ?? [:] }
        let skin = design.skinFile
            .flatMap { Resources.data("plugins/\($0).json") }
            .flatMap { try? Plugin.load($0, type: "json") }?.skin ?? [:]
        designSkins[design.rawValue] = skin
        loadedDesigns.insert(design.rawValue)
        return skin
    }

    private static func merge(_ base: [String: Any], _ overrides: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in overrides {
            if let nested = base[key] as? [String: Any], let patch = value as? [String: Any] {
                result[key] = merge(nested, patch)
            } else {
                result[key] = value
            }
        }
        return result
    }

    private static func pick(_ colors: [String: Any], _ name: String, _ fallback: UIColor, dark: Bool) -> UIColor {
        if let value = colors[name] as? String { return UIColor(hex: value) ?? fallback }
        if let value = colors[name] as? [String: String] {
            return (value[dark ? "dark" : "light"]).flatMap(UIColor.init(hex:)) ?? fallback
        }
        return fallback
    }

    private static func pattern(_ data: [String: Any]?) -> UIImage? {
        guard let data, let kind = data["pattern"] as? String,
              let colors = (data["colors"] as? [String])?.compactMap(UIColor.init(hex:)), !colors.isEmpty
        else { return nil }
        let cell = max(2, CGFloat((data["cell"] as? Double) ?? 8))
        let size: CGFloat
        switch kind {
        case "dots": size = cell * 2
        case "pixels": size = cell * 8
        default: return nil
        }
        var state = UInt32(truncatingIfNeeded: (data["seed"] as? Int) ?? 1)
        func next() -> UInt32 {
            state = state &* 1664525 &+ 1013904223
            return state
        }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            colors[0].setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: size, height: size))
            if kind == "dots" {
                if colors.count > 1 { colors[1].setFill() }
                let dot = max(1, cell * 0.6)
                context.cgContext.fillEllipse(in: CGRect(x: (size - dot) / 2, y: (size - dot) / 2, width: dot, height: dot))
            } else {
                let count = Int(size / cell)
                for row in 0..<count {
                    for column in 0..<count {
                        colors[Int(next() % UInt32(colors.count))].setFill()
                        context.cgContext.fill(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell))
                    }
                }
            }
        }
    }
}

extension UIColor {
    convenience init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespacesAndNewlines))
        guard [6, 8].contains(value.count), let number = UInt32(value, radix: 16) else { return nil }
        self.init(red: CGFloat((number >> 16) & 255) / 255,
                  green: CGFloat((number >> 8) & 255) / 255,
                  blue: CGFloat(number & 255) / 255,
                  alpha: value.count == 8 ? CGFloat((number >> 24) & 255) / 255 : 1)
    }
}
