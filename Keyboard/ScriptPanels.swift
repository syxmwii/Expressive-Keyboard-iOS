import UIKit

extension KeyboardController {
    func loadScripts() {
        subscriptions.removeAll()
        runtimes.removeAll()
        for plugin in enabledPlugins.filter({ $0.script != nil }).prefix(12) {
            runtimes[plugin.id] = ScriptRuntime(plugin: plugin) { [weak self] method, values in
                self?.scriptHost(plugin, method, values)
            }
        }
    }

    @discardableResult
    func emit(_ event: String, _ value: Any = NSNull(), needsText: Bool = false) -> Any? {
        lastScriptResult = nil
        guard !privateInput else { return nil }
        for plugin in enabledPlugins {
            guard subscriptions[plugin.id]?.contains(event) == true, let runtime = runtimes[plugin.id], !needsText || plugin.permissions.contains("read_text") else { continue }
            if let result = runtime.event(event, value), !(result is NSNull) {
                lastScriptResult = result
                if result as? Bool == false { break }
            }
        }
        return lastScriptResult
    }

    func scriptHost(_ plugin: Plugin, _ method: String, _ args: [Any]) -> Any? {
        guard !privateInput else { return nil }
        let permitted = plugin.permissions
        let first = args.first
        let text = first as? String ?? ""
        let number = max(-500, min(500, first as? Int ?? 0))
        let storageKey = "module." + plugin.id
        switch method {
        case "subscribe":
            subscriptions[plugin.id, default: []].insert(text)
            if text == "frame" { updateFrameTimer() }
        case "unsubscribe":
            subscriptions[plugin.id]?.remove(text)
            if text == "frame" { updateFrameTimer() }
        case "commit":
            insert(String(text.prefix(4_000)))
        case "deleteBefore":
            erase(max(0, number))
        case "deleteAfter":
            if number > 0 {
                textDocumentProxy.adjustTextPosition(byCharacterOffset: number)
                erase(number)
            }
        case "move":
            textDocumentProxy.adjustTextPosition(byCharacterOffset: number)
        case "textBefore":
            return permitted.contains("read_text") ? String(context.suffix(max(0, number))) : ""
        case "textAfter":
            return permitted.contains("read_text") ? String((textDocumentProxy.documentContextAfterInput ?? "").prefix(max(0, number))) : ""
        case "selectedText":
            return permitted.contains("read_text") ? (textDocumentProxy.selectedText ?? "") : ""
        case "clipboard":
            guard permitted.contains("clipboard") else { return [] as [String] }
            if let text = UIPasteboard.general.string { return [String(text.prefix(4_000))] + clipboard }
            return clipboard
        case "status", "log":
            if method == "status" { DispatchQueue.main.async { [weak self] in self?.setStatus(text) } }
        case "get":
            let data = defaults.data(forKey: storageKey) ?? Data()
            return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?[text]
        case "set":
            let data = defaults.data(forKey: storageKey) ?? Data()
            var values = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            values[text] = args.count >= 2 && !(args[1] is NSNull) ? args[1] : nil
            if let new = try? JSONSerialization.data(withJSONObject: values), new.count < 256_000 { defaults.set(new, forKey: storageKey) }
        case "config":
            return defaults.dictionary(forKey: storageKey + ".config")?[text]
                ?? (plugin.object["config"] as? [[String: Any]])?.first { $0["id"] as? String == text }?["default"]
        case "setConfigs":
            if let values = first as? [String: Any], PropertyListSerialization.propertyList(values, isValidFor: .binary) {
                defaults.set(values, forKey: storageKey + ".config")
            }
        case "size":
            return ["width": view.bounds.width, "height": view.bounds.height, "w": view.bounds.width, "h": view.bounds.height]
        case "device":
            return ["platform": "iOS", "dark": traitCollection.userInterfaceStyle == .dark, "landscape": view.bounds.width > 520] as [String: Any]
        case "capture":
            captureTouches = (first as? Bool) ?? false
        case "draw":
            if text == "clear" { overlay.commands = [] }
            else if let items = args.dropFirst().first as? [[String: Any]] { overlay.commands = Array(items.prefix(120)) }
            else if let item = args.dropFirst().first as? [String: Any] { overlay.commands.append(item.merging(["type": text]) { a, _ in a }) }
            if overlay.commands.count > 120 { overlay.commands.removeFirst(overlay.commands.count - 120) }
        case "haptic":
            touchFeedback()
        case "refresh":
            DispatchQueue.main.async { [weak self] in
                if let self, case .script = self.panel { self.renderPanel() }
            }
        case "closePanel":
            DispatchQueue.main.async { [weak self] in self?.switchPanel(.typing) }
        case "pressKey":
            if pressDepth == 0, text.count <= 20 {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.pressDepth = 1
                    self.runNamedKey(text)
                    self.pressDepth = 0
                }
            }
        case "input":
            if case .script = panel {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.inputCallback = nil
                    self.beginSearch(self.panel)
                }
            }
        default:
            return nil
        }
        return nil
    }

    func showScript(_ id: String, _ index: Int) {
        let list = scroll()
        guard let runtime = runtimes[id] else { return }
        let nodes = runtime.event("$render", index) as? [[String: Any]] ?? []
        if let error = runtime.error { list.addArrangedSubview(label(error)); return }
        for node in nodes.prefix(80) {
            list.addArrangedSubview(scriptNode(node, runtime: runtime, depth: 0))
        }
    }

    private func scriptNode(_ node: [String: Any], runtime: ScriptRuntime, depth: Int) -> UIView {
        guard depth < 6 else { return UIView() }
        let text = node["text"] as? String ?? node["title"] as? String ?? node["icon"] as? String ?? ""
        let type = node["type"] as? String ?? "text"
        let callback = node["callback"] as? Int
        let invoke: (Any) -> Void = { [weak self] value in
            if let callback {
                _ = runtime.event("$panelPick", [callback, value])
                self?.updateHeader()
            } else if type == "button", !text.isEmpty {
                self?.insert(text)
            }
        }
        switch type {
        case "row", "column", "box":
            let children = node["children"] as? [[String: Any]] ?? []
            let views = children.prefix(20).map { scriptNode($0, runtime: runtime, depth: depth + 1) }
            if callback != nil {
                let title = children.compactMap { $0["text"] as? String }.joined(separator: " ")
                let button = key(title.isEmpty ? text : title, size: 13) { invoke(NSNull()) }
                button.heightAnchor.constraint(equalToConstant: 35).isActive = true
                return button
            }
            let stack = row(views)
            stack.axis = type == "row" ? .horizontal : .vertical
            return stack
        case "grid", "tabs":
            let values = (node["items"] as? [Any] ?? []).prefix(80)
            let stack = UIStackView()
            stack.axis = .vertical
            stack.spacing = 4
            let columns = max(1, min(12, node["columns"] as? Int ?? 4))
            let items = Array(values)
            for start in stride(from: 0, to: items.count, by: columns) {
                let buttons = items[start..<min(start + columns, items.count)].map { item in
                    let title = item as? String ?? (item as? [String: Any])?["title"] as? String ?? ""
                    return key(title, size: 14) { invoke(item) }
                }
                let stackRow = row(buttons)
                stackRow.heightAnchor.constraint(equalToConstant: 34).isActive = true
                stack.addArrangedSubview(stackRow)
            }
            return stack
        case "canvas":
            let canvas = OverlayView()
            canvas.commands = node["items"] as? [[String: Any]] ?? []
            canvas.heightAnchor.constraint(equalToConstant: CGFloat(max(20, min(150, node["height"] as? Double ?? 90)))).isActive = true
            return canvas
        case "input":
            let button = key(node["value"] as? String ?? text, role: .function, size: 14) { [weak self] in
                guard let self else { return }
                self.inputCallback = node["change"] as? Int
                self.beginSearch(self.panel)
            }
            button.heightAnchor.constraint(equalToConstant: 35).isActive = true
            return button
        case "button", "chip":
            let button = key(text, role: node["accent"] as? Bool == true ? .accent : .function, size: 14) { invoke(NSNull()) }
            button.heightAnchor.constraint(equalToConstant: 35).isActive = true
            return button
        default:
            return label(text, size: CGFloat(max(9, min(24, node["size"] as? Double ?? 14))))
        }
    }
}

final class OverlayView: UIView {
    var commands: [[String: Any]] = [] { didSet { setNeedsDisplay() } }
    var trail: [CGPoint] = [] { didSet { setNeedsDisplay() } }
    var trailColor = UIColor.systemPurple

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        func line(_ points: [CGPoint], color: UIColor, width: CGFloat) {
            guard points.count > 1 else { return }
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.beginPath()
            context.addLines(between: points)
            context.strokePath()
        }
        line(trail, color: trailColor.withAlphaComponent(0.75), width: 5)
        for command in commands {
            func number(_ name: String, fallback: Double = 0) -> CGFloat {
                let value = command[name] as? Double ?? fallback
                return value.isFinite ? CGFloat(min(10_000, max(-10_000, value))) : 0
            }
            let type = command["type"] as? String ?? ""
            let color = (command["color"] as? String).flatMap(UIColor.init(hex:)) ?? UIColor.systemPurple
            context.setFillColor(color.cgColor)
            switch type {
            case "path":
                let points = (command["points"] as? [[Double]] ?? []).prefix(1000).compactMap { point -> CGPoint? in
                    guard point.count >= 2, point[0].isFinite, point[1].isFinite else { return nil }
                    return CGPoint(x: point[0], y: point[1])
                }
                line(points, color: color, width: max(0.5, number("width", fallback: 2)))
            case "circle":
                let radius = max(0, number("r"))
                context.fillEllipse(in: CGRect(x: number("x") - radius, y: number("y") - radius, width: radius * 2, height: radius * 2))
            case "rect":
                context.fill(CGRect(x: number("x"), y: number("y"), width: max(0, number("w")), height: max(0, number("h"))))
            case "line":
                line([CGPoint(x: number("x1"), y: number("y1")), CGPoint(x: number("x2"), y: number("y2"))],
                     color: color, width: max(0.5, number("width", fallback: 2)))
            case "text":
                let text = String((command["text"] as? String ?? "").prefix(300))
                (text as NSString).draw(at: CGPoint(x: number("x"), y: number("y")), withAttributes: [
                    .foregroundColor: color, .font: UIFont.systemFont(ofSize: max(5, min(100, number("size", fallback: 16))))
                ])
            default:
                break
            }
        }
    }
}
