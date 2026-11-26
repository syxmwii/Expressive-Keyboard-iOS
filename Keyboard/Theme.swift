import UIKit

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
    var pressedColor: UIColor?
    var pressMode = "none"
    var pressScale: CGFloat = 1
    var idleRadius: CGFloat = 0
    var pressedRadius: CGFloat?
    var shadow: (radius: CGFloat, y: CGFloat, color: UIColor)? {
        didSet { applyShadow() }
    }
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
            backgroundColor = isHighlighted ? (pressedColor ?? baseColor.withAlphaComponent(0.65)) : baseColor
            if let pressedRadius {
                layer.cornerRadius = isHighlighted ? pressedRadius : idleRadius
                setNeedsLayout()
            }
            guard pressMode != "none" else {
                transform = .identity
                return
            }
            let scale = isHighlighted ? pressScale : 1
            let sink: CGFloat = isHighlighted && pressMode == "sink" ? 1 : 0
            UIView.animate(withDuration: 0.08) {
                self.transform = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: 0, y: sink)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard layer.shadowOpacity > 0 else { return }
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }

    func symbol(_ name: String, size: CGFloat = 18) {
        let image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .semibold))
        setTitle(nil, for: .normal)
        setImage(image, for: .normal)
        tintColor = titleColor(for: .normal)
    }

    private func applyShadow() {
        guard let shadow, shadow.radius > 0 else {
            layer.shadowOpacity = 0
            return
        }
        layer.shadowColor = shadow.color.cgColor
        layer.shadowOpacity = Float(shadow.color.cgColor.alpha)
        layer.shadowRadius = shadow.radius
        layer.shadowOffset = CGSize(width: 0, height: shadow.y)
        setNeedsLayout()
    }

    @objc private func reset() { consumedHold = false }
    @objc private func activate() { if !consumedHold { action?() } }
    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began, let hold { consumedHold = true; hold() }
    }
}
