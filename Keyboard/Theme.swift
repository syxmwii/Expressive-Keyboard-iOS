import UIKit

struct KeyboardTheme {
    let background: UIColor
    let key: UIColor
    let text: UIColor
    let function: UIColor
    let functionText: UIColor
    let accent: UIColor
    let accentText: UIColor
    let border: UIColor
    let secondaryBackground: UIColor?
    let design: Design

    init(_ preferences: Preferences, dark: Bool) {
        design = preferences.design
        let fileSkin = preferences.design.skinFile
            .flatMap { Resources.data("plugins/\($0).json") }
            .flatMap { try? Plugin.load($0, type: "json") }?.skin
        let selected = preferences.activePlugins.first { $0.id == preferences.skinPlugin }
        let skin = selected?.skin ?? fileSkin
        let colors = skin?["colors"] as? [String: Any] ?? [:]
        func pick(_ name: String, _ fallback: UIColor) -> UIColor {
            if let value = colors[name] as? String { return UIColor(hex: value) ?? fallback }
            if let value = colors[name] as? [String: String] {
                return (value[dark ? "dark" : "light"]).flatMap(UIColor.init(hex:)) ?? fallback
            }
            return fallback
        }
        let backgroundData = (skin?["keyboard"] as? [String: Any])?["background"] as? [String: Any]
        let gradient = (backgroundData?["colors"] as? [String] ?? []).compactMap(UIColor.init(hex:))
        background = gradient.first ?? pick("background", dark ? UIColor(hex: "#211E2C")! : UIColor(hex: "#ECE7F8")!)
        secondaryBackground = gradient.dropFirst().first
        key = pick("key", dark ? UIColor(hex: "#393445")! : UIColor(hex: "#FFFBFF")!)
        text = pick("keyText", dark ? UIColor(hex: "#F3EDFF")! : UIColor(hex: "#241A38")!)
        function = pick("func", dark ? UIColor(hex: "#504563")! : UIColor(hex: "#DBD1F0")!)
        functionText = pick("funcText", text)
        accent = UIColor(hex: preferences.tint) ?? pick("accent", dark ? UIColor(hex: "#D0BCFF")! : UIColor(hex: "#6C49AB")!)
        if preferences.tint.isEmpty {
            accentText = pick("accentText", dark ? UIColor(hex: "#2F164E")! : .white)
        } else {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            accent.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            accentText = red * 0.299 + green * 0.587 + blue * 0.114 > 0.60 ? .black : .white
        }
        border = design == .neon ? accent.withAlphaComponent(0.55) : .clear
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

final class ExpressiveButton: UIButton {
    var hold: (() -> Void)? {
        didSet {
            guard hold != nil, oldValue == nil, gestureRecognizers?.contains(where: { $0 is UILongPressGestureRecognizer }) != true else { return }
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
            longPress.minimumPressDuration = 0.37
            longPress.cancelsTouchesInView = false
            longPress.delaysTouchesEnded = false
            addGestureRecognizer(longPress)
        }
    }
    var action: (() -> Void)?
    var value: String?
    var variantValues: [String] = []
    private var consumedHold = false
    var baseColor = UIColor.clear { didSet { backgroundColor = baseColor } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addTarget(self, action: #selector(activate), for: .touchUpInside)
        addTarget(self, action: #selector(reset), for: .touchDown)
        accessibilityTraits = .button
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.55
        titleLabel?.lineBreakMode = .byClipping
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? baseColor.withAlphaComponent(0.65) : baseColor
        }
    }

    func symbol(_ name: String, size: CGFloat = 18) {
        let image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .semibold))
        setTitle(nil, for: .normal)
        setImage(image, for: .normal)
        tintColor = titleColor(for: .normal)
    }

    @objc private func reset() { consumedHold = false }
    @objc private func activate() { if !consumedHold { action?() } }
    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began, let hold { consumedHold = true; hold() }
    }
}
