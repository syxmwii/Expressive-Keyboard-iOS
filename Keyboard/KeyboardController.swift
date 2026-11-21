import UIKit
import AudioToolbox
import CoreText

final class KeyboardController: UIInputViewController, UIGestureRecognizerDelegate {
    enum Panel { case typing, toolbar, emoji, clipboard, plugins, gifs, translate, voice, script(String, Int), variants }
    let body = UIStackView()
    let header = UIStackView()
    let content = UIStackView()
    let gradient = CAGradientLayer()
    let photo = UIImageView()
    let overlay = OverlayView()
    var heightConstraint: NSLayoutConstraint!
    var preferences = Preferences()
    var theme = KeyboardTheme(Preferences(), dark: false)
    var panel: Panel = .typing
    var languageID = "en"
    var availableLayouts = Resources.layouts
    var language: KeyboardLayout { availableLayouts.first { $0.id == languageID } ?? availableLayouts[0] }
    var symbols = 0
    var shift = 0
    var lastShift = Date.distantPast
    var lastSpace = Date.distantPast
    var composition = ""
    var rendered = ""
    var document: UUID?
    var keyboardType: UIKeyboardType = .default
    var incognito = false
    var privateInput: Bool { incognito || preferences.incognito }
    var pendingSearch: Panel?
    var searchText = ""
    var category = 0
    var variants: [String] = []
    var recentEmoji: [String] = []
    var clipboard: [String] = []
    var snippets: [String] = []
    var gifResults: [(String, URL)] = []
    var translation = ""
    var status = ""
    var pendingNetwork: Task<Void, Never>?
    var runtimes: [String: ScriptRuntime] = [:]
    var frameTimer: Timer?
    var captureTouches = false
    var pressDepth = 0
    var suppressTextChanges = false
    var learned: [String: [String: Int]] = [:]
    var supplementary: [String: String] = [:]
    var glideAlternatives: [String] = []
    var lastGlide = ""
    var lastScriptResult: Any?
    var inputCallback: Int?
    var composingUndo: (word: String, corrected: String)?
    var fontName: String?
    let lexicon = Lexicon()
    let checker = UITextChecker()
    var points: [CGPoint] = []
    var path: [String] = []
    var markedButtons: [ExpressiveButton] = []
    let feedback = UIImpactFeedbackGenerator(style: .light)
    let defaults = UserDefaults.standard

    override func loadView() {
        view = ExpressiveInputView(frame: .zero, inputViewStyle: .keyboard)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        inputView?.allowsSelfSizing = true
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        view.layer.insertSublayer(gradient, at: 0)
        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        photo.alpha = 0.42
        view.addSubview(photo)
        body.axis = .vertical
        body.spacing = 6
        body.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(body)
        header.axis = .horizontal
        header.distribution = .fill
        header.spacing = 5
        content.axis = .vertical
        content.spacing = 4
        body.addArrangedSubview(header)
        body.addArrangedSubview(content)
        header.heightAnchor.constraint(equalToConstant: 37).isActive = true
        view.addSubview(overlay)
        overlay.isUserInteractionEnabled = false
        heightConstraint = view.heightAnchor.constraint(equalToConstant: 267)
        heightConstraint.priority = UILayoutPriority(999)
        heightConstraint.isActive = true
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            body.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -5),
            body.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor, constant: 5),
            body.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor, constant: -5)
        ])
        let pan = UIPanGestureRecognizer(target: self, action: #selector(trackGlide(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = true
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        learned = defaults.object(forKey: "learned") as? [String: [String: Int]] ?? [:]
        recentEmoji = defaults.stringArray(forKey: "emoji") ?? []
        clipboard = defaults.stringArray(forKey: "clipboard") ?? []
        snippets = defaults.stringArray(forKey: "snippets") ?? []
        languageID = defaults.string(forKey: "language") ?? "en"
        requestSupplementaryLexicon { [weak self] lexicon in
            for entry in lexicon.entries { self?.supplementary[entry.userInput.lowercased()] = entry.documentText }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
        emit("show")
        emit("start", ["type": textDocumentProxy.keyboardType?.rawValue ?? 0])
        frameTimer?.invalidate()
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self, !self.runtimes.isEmpty else { return }
            self.emit("frame", 33)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        finish()
        emit("finish")
        emit("hide")
        frameTimer?.invalidate()
        frameTimer = nil
        pendingNetwork?.cancel()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradient.frame = view.bounds
        photo.frame = view.bounds
        overlay.frame = view.bounds
        updateHeight()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if isViewLoaded && previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle { redraw() }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        guard isViewLoaded, !suppressTextChanges else { return }
        let newDocument = textDocumentProxy.documentIdentifier
        let type = textDocumentProxy.keyboardType ?? .default
        if document != newDocument || keyboardType != type {
            composition = ""
            rendered = ""
            pendingSearch = nil
            panel = .typing
            keyboardType = type
            document = newDocument
            symbols = numericMode ? 1 : 0
            redraw()
        } else {
            updateHeader()
        }
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        guard isViewLoaded, !suppressTextChanges else { return }
        updateHeader()
    }

    var numericMode: Bool { [.numberPad, .decimalPad, .phonePad, .namePhonePad, .asciiCapableNumberPad].contains(keyboardType) }
    var context: String { textDocumentProxy.documentContextBeforeInput ?? "" }
    var prefix: String {
        String(context.reversed().prefix { $0.isLetter || $0 == "'" || $0 == "’" }.reversed())
    }
    var dictionary: String { language.dictionary ?? language.id }
    var currentComposition: String { language.id == "my" ? "myanmar" : language.composer }
    var cjk: Bool { ["pinyin", "kana"].contains(currentComposition) }
    var cjkDictionary: String { currentComposition == "kana" ? "ja" : (language.id == "zh-tw" ? "zh_tw" : "zh_cn") }
    var canSuggest: Bool {
        !privateInput && preferences.suggestions && pendingSearch == nil && !numericMode &&
        textDocumentProxy.autocorrectionType != .no && ![.emailAddress, .URL, .twitter, .webSearch].contains(keyboardType)
    }

    func reload() {
        preferences = SharedStore.load()
        availableLayouts = preferences.enabledLayouts
        if !availableLayouts.contains(where: { $0.id == languageID }) { languageID = availableLayouts[0].id }
        primaryLanguage = language.locale
        keyboardType = textDocumentProxy.keyboardType ?? .default
        document = textDocumentProxy.documentIdentifier
        symbols = numericMode ? 1 : symbols
        photo.image = preferences.hasPhoto ? SharedStore.file("background.jpg").flatMap { UIImage(contentsOfFile: $0.path) } : nil
        if preferences.hasFont, let file = SharedStore.file("font"), let provider = CGDataProvider(url: file as CFURL),
           let font = CGFont(provider) {
            CTFontManagerRegisterGraphicsFont(font, nil)
            fontName = font.postScriptName as String?
        } else {
            fontName = nil
        }
        if !privateInput { loadScripts() } else { runtimes.removeAll(); captureTouches = false }
        redraw()
    }

    func updateHeight() {
        let count = numericMode ? 4 : ((symbols == 0 ? language.rows.count + (preferences.numberRow ? 1 : 0) : 3) + 1)
        let rowHeight = view.bounds.width > 580 && traitCollection.verticalSizeClass == .compact ? min(36.0, preferences.height) : preferences.height
        heightConstraint.constant = CGFloat(count) * CGFloat(rowHeight + preferences.spacing) + 54
    }

    func redraw() {
        theme = KeyboardTheme(preferences, dark: traitCollection.userInterfaceStyle == .dark)
        view.backgroundColor = theme.background
        gradient.colors = [theme.background.cgColor, (theme.secondaryBackground ?? theme.background).cgColor]
        updateHeight()
        updateHeader()
        renderPanel()
    }

    func clear(_ stack: UIStackView) {
        for child in stack.arrangedSubviews { stack.removeArrangedSubview(child); child.removeFromSuperview() }
    }

    func key(_ label: String, style: Int = 0, size: CGFloat = 21, accessible: String? = nil,
             action: (() -> Void)? = nil) -> ExpressiveButton {
        let button = ExpressiveButton(frame: .zero)
        button.action = action
        button.accessibilityLabel = accessible ?? label
        button.setTitle(label, for: .normal)
        button.setTitleColor(style == 2 ? theme.accentText : style == 1 ? theme.functionText : theme.text, for: .normal)
        button.baseColor = style == 2 ? theme.accent : style == 1 ? theme.function : theme.key
        button.layer.cornerRadius = CGFloat(preferences.radius)
        button.layer.borderWidth = preferences.design == .neon ? 0.8 : 0
        button.layer.borderColor = theme.border.cgColor
        if let fontName, let custom = UIFont(name: fontName, size: size) {
            button.titleLabel?.font = custom
        } else {
            let weighted = UIFont.systemFont(ofSize: size, weight: style == 0 ? .medium : .semibold)
            let choice = preferences.design == .expressive ? weighted.fontDescriptor.withDesign(.rounded) : nil
            button.titleLabel?.font = choice.map { UIFont(descriptor: $0, size: size) } ?? weighted
        }
        button.wavy = preferences.design == .expressive && (style == 2 ? preferences.shapes > 0 : preferences.shapes == 2)
        return button
    }

    func label(_ text: String, size: CGFloat = 14) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: .medium)
        label.textColor = theme.text
        label.numberOfLines = 0
        label.textAlignment = .center
        return label
    }

    func switchPanel(_ next: Panel) {
        if case .script(let id, let index) = panel { _ = runtimes[id]?.event("$panelClose", index) }
        if case .typing = panel { finish() }
        if case .toolbar = panel {
            searchText = ""
            translation = ""
            gifResults = []
        }
        pendingNetwork?.cancel()
        panel = next
        if case .script(let id, let index) = next { _ = runtimes[id]?.event("$panelOpen", index) }
        emit("panel", String(describing: next))
        redraw()
        if case .gifs = next { fetchGIFs() }
    }

    func updateHeader() {
        clear(header)
        let title: String
        switch panel {
        case .typing: title = pendingSearch == nil ? "▦" : "×"
        default: title = "‹"
        }
        let menu = key(title, style: 1, size: 23, accessible: L("Keyboard tools", "Инструменты клавиатуры")) { [weak self] in
            guard let self else { return }
            if case .typing = self.panel {
                if let previous = self.pendingSearch {
                    self.pendingSearch = nil
                    self.switchPanel(previous)
                } else { self.switchPanel(.toolbar) }
            } else {
                self.pendingSearch = nil
                self.switchPanel(.typing)
            }
        }
        menu.widthAnchor.constraint(equalToConstant: 42).isActive = true
        header.addArrangedSubview(menu)
        if let search = pendingSearch, case .typing = panel {
            header.addArrangedSubview(label(searchText.isEmpty ? L("Type here…", "Введите текст…") : searchText))
            header.addArrangedSubview(key("↵", style: 2) { [weak self] in self?.completeSearch(search) })
            return
        }
        if case .typing = panel {
            let values = suggestions()
            if values.isEmpty {
                let title = privateInput ? L("Incognito", "Инкогнито") : language.space
                header.addArrangedSubview(label(status.isEmpty ? title : status))
                let emoji = key("☺", style: 1, accessible: L("Emoji", "Эмодзи")) { [weak self] in self?.switchPanel(.emoji) }
                emoji.widthAnchor.constraint(equalToConstant: 38).isActive = true
                header.addArrangedSubview(emoji)
            } else {
                let row = UIStackView()
                row.distribution = .fillEqually
                row.spacing = 4
                for word in values.prefix(4) {
                    row.addArrangedSubview(key(word, size: 15) { [weak self] in self?.pick(word) })
                }
                header.addArrangedSubview(row)
            }
        } else {
            header.addArrangedSubview(label(status.isEmpty ? panelTitle : status))
        }
    }

    func renderPanel() {
        clear(content)
        markedButtons.removeAll()
        content.distribution = .fill
        content.spacing = CGFloat(preferences.spacing)
        switch panel {
        case .typing: renderTyping()
        case .toolbar: showToolbar()
        case .emoji: showEmoji()
        case .clipboard: showClipboard()
        case .plugins: showPlugins()
        case .gifs: showGIFs()
        case .translate: showTranslate()
        case .voice: showVoice()
        case .script(let id, let index): showScript(id, index)
        case .variants:
            grid(variants, columns: 7) { [weak self] value in self?.pickVariant(value) }
        }
    }

    func row(_ buttons: [UIView], distribution: UIStackView.Distribution = .fillEqually) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: buttons)
        stack.distribution = distribution
        stack.spacing = CGFloat(preferences.spacing)
        return stack
    }

    func typingRow(_ buttons: [UIView]) {
        var arranged = buttons
        if preferences.width < 0.99 || preferences.hand != 0 {
            let fraction = CGFloat(min(preferences.width, preferences.hand == 0 ? 1 : 0.82))
            let shell = UIStackView()
            let keys = row(buttons)
            let spacer = UIView()
            shell.addArrangedSubview(preferences.hand < 0 ? keys : spacer)
            shell.addArrangedSubview(preferences.hand < 0 ? spacer : keys)
            keys.widthAnchor.constraint(equalTo: shell.widthAnchor, multiplier: fraction).isActive = true
            if preferences.hand == 0 {
                let end = UIView()
                shell.addArrangedSubview(end)
                end.widthAnchor.constraint(equalTo: spacer.widthAnchor).isActive = true
            }
            arranged = [shell]
        }
        content.addArrangedSubview(row(arranged))
    }

    func renderTyping() {
        content.distribution = .fillEqually
        let numeric = numericMode && pendingSearch == nil
        let rows: [[String]]
        if numeric {
            rows = ["123", "456", "789", keyboardType == .decimalPad ? ".0⌫" : "−0⌫"].map(KeyboardLayout.tokens)
        } else if symbols == 1 {
            rows = ["1234567890", "@ # $ % & * - + ( )", "! \" ' : ; / ?",].map(KeyboardLayout.tokens)
        } else if symbols == 2 {
            rows = ["~ ` | • √ π ÷ × ¶ ∆", "£ € ₽ ¥ ¢ ^ = { } \\", "_ © ® ™ [ ] < >"].map(KeyboardLayout.tokens)
        } else {
            rows = (preferences.numberRow ? [KeyboardLayout.tokens("1234567890")] : []) + language.rows
        }
        for (index, line) in rows.enumerated() {
            var buttons: [UIView] = []
            let last = index == rows.count - 1
            if last && !numeric {
                let capital = shift > 0 || autoShift
                let shiftButton = key(symbols > 0 ? (symbols == 1 ? "#+=" : "123") : (shift == 2 ? "⇪" : "⇧"),
                                      style: symbols == 0 && capital ? 2 : 1, size: 19, accessible: L("Shift", "Регистр")) { [weak self] in
                    self?.toggleShift()
                }
                buttons.append(shiftButton)
            }
            for value in line {
                if value == "⌫" {
                    buttons.append(deleteKey())
                    continue
                }
                let shown = symbols == 0 && !numeric ? shifted(value) : value
                let button = key(shown) { [weak self] in self?.type(shown) }
                if symbols == 0 && !numeric {
                    button.value = value
                    markedButtons.append(button)
                    var alternatives = language.accents[value] ?? []
                    for plugin in preferences.activePlugins {
                        if let maps = plugin.object["variants"] as? [String: [String: [String]]],
                           let extra = maps[language.id]?[value] ?? maps["*"]?[value] { alternatives += extra }
                    }
                    if value == "е" && language.id == "ru" { alternatives.append("ё") }
                    if value == "ь" && language.id == "ru" { alternatives.append("ъ") }
                    if index == (preferences.numberRow ? 1 : 0), let place = line.firstIndex(of: value), place < 10 {
                        alternatives.insert(String((place + 1) % 10), at: 0)
                    }
                    if !alternatives.isEmpty {
                        button.hold = { [weak self] in
                            guard let self else { return }
                            self.variants = alternatives.map { self.shifted($0) }
                            self.panel = .variants
                            self.redraw()
                        }
                    }
                }
                buttons.append(button)
            }
            if last && !numeric { buttons.append(deleteKey()) }
            typingRow(buttons)
        }
        guard !numeric else { return }
        let bottom = UIStackView()
        bottom.spacing = CGFloat(preferences.spacing)
        let numbers = key(symbols == 0 ? "123" : "ABC", style: 1, size: 14) { [weak self] in
            guard let self else { return }
            self.finish()
            self.symbols = self.symbols == 0 ? 1 : 0
            self.redraw()
        }
        let languageKey = key(language.label, style: 1, size: 12, accessible: L("Language", "Язык")) { [weak self] in
            self?.nextLanguage()
        }
        let space = key(pendingSearch == nil ? language.space : "␣", size: 15, accessible: L("Space", "Пробел")) { [weak self] in
            self?.space()
        }
        space.hold = { [weak self] in
            guard let self else { return }
            self.finish()
            self.textDocumentProxy.adjustTextPosition(byCharacterOffset: -1)
        }
        let cursor = UIPanGestureRecognizer(target: self, action: #selector(moveOnSpace(_:)))
        space.addGestureRecognizer(cursor)
        let punctuation = key(keyboardType == .emailAddress ? "@" : ".", style: 1) { [weak self] in
            guard let self else { return }
            self.type(self.keyboardType == .emailAddress ? "@" : ".")
        }
        punctuation.hold = { [weak self] in
            guard let self else { return }
            self.variants = [",", ".", "?", "!", ":", ";", "…", "—"]
            self.panel = .variants
            self.redraw()
        }
        let enter = key(returnLabel, style: 2, size: 17, accessible: L("Return", "Ввод")) { [weak self] in self?.enter() }
        var keys = [numbers, languageKey, space, punctuation, enter]
        if needsInputModeSwitchKey {
            let globe = key("◎", style: 1, size: 19, accessible: L("Next keyboard", "Следующая клавиатура"))
            globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
            keys.insert(globe, at: 1)
        }
        for button in keys {
            bottom.addArrangedSubview(button)
            if button !== space {
                button.widthAnchor.constraint(equalTo: bottom.widthAnchor, multiplier: button === enter ? 0.14 : 0.115).isActive = true
            }
        }
        typingRow([bottom])
    }

    var returnLabel: String {
        switch textDocumentProxy.returnKeyType ?? .default {
        case .search, .google, .yahoo: return "⌕"
        case .send: return "➤"
        case .go, .next: return "→"
        case .done: return "✓"
        default: return "↵"
        }
    }

    func deleteKey() -> ExpressiveButton {
        let button = key("⌫", style: 1, accessible: L("Delete", "Удалить")) { [weak self] in self?.backspace() }
        button.hold = { [weak self] in self?.deleteWord() }
        return button
    }

    var autoShift: Bool {
        guard pendingSearch == nil, preferences.autoCap, language.hasCase, !cjk, shift == 0,
              (textDocumentProxy.autocapitalizationType ?? .sentences) != .none, keyboardType == .default || keyboardType == .twitter
        else { return false }
        let value = context
        if textDocumentProxy.autocapitalizationType == .allCharacters { return true }
        if textDocumentProxy.autocapitalizationType == .words { return value.last?.isWhitespace ?? true }
        return value.isEmpty || value.last == "\n" ||
            (value.last?.isWhitespace == true && value.trimmingCharacters(in: .whitespaces).last.map { ".!?。！？".contains($0) } == true)
    }

    func shifted(_ value: String) -> String {
        guard shift > 0 || autoShift else { return value }
        return language.shift[value] ?? (language.hasCase ? value.uppercased(with: Locale(identifier: language.locale)) : value)
    }

    func toggleShift() {
        if symbols != 0 { symbols = symbols == 1 ? 2 : 1 } else {
            shift = Date().timeIntervalSince(lastShift) < 0.34 && shift == 1 ? 2 : (shift == 0 ? 1 : 0)
            lastShift = Date()
            emit("shift", ["off", "single", "caps"][shift])
        }
        redraw()
    }

    func nextLanguage() {
        finish()
        let current = availableLayouts.firstIndex { $0.id == languageID } ?? 0
        languageID = availableLayouts[(current + 1) % availableLayouts.count].id
        defaults.set(languageID, forKey: "language")
        primaryLanguage = language.locale
        symbols = 0
        shift = 0
        emit("language", languageID)
        redraw()
    }

    func touchFeedback() {
        if preferences.haptics { feedback.impactOccurred(intensity: preferences.intensity) }
        if preferences.sound { UIDevice.current.playInputClick() }
    }

    func type(_ key: String) {
        touchFeedback()
        if pendingSearch != nil { searchText += key; updateHeader(); return }
        glideAlternatives.removeAll()
        composingUndo = nil
        if let result = emit("key", ["text": key], needsText: true) as? Bool, result == false { return }
        let value = (lastScriptResult as? String) ?? key
        let capitals = autoShift || shift == 1
        if currentComposition != "none", symbols == 0, value.unicodeScalars.allSatisfy({
            CharacterSet.letters.contains($0) || CharacterSet.nonBaseCharacters.contains($0) || (cjk && ($0 == "'" || $0 == "-"))
        }) {
            composition += value
            updateComposition()
        } else {
            finish()
            insert(value)
        }
        if shift == 1 { shift = 0 }
        if capitals || autoShift || value == "." { redraw() } else { updateHeader() }
    }

    func insert(_ text: String) {
        guard !text.isEmpty else { return }
        suppressTextChanges = true
        textDocumentProxy.insertText(text)
        suppressTextChanges = false
    }

    func erase(_ count: Int) {
        suppressTextChanges = true
        for _ in 0..<count { textDocumentProxy.deleteBackward() }
        suppressTextChanges = false
    }

    func updateComposition() {
        rendered = Composition.render(composition, kind: currentComposition)
        suppressTextChanges = true
        if rendered.isEmpty {
            textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
            textDocumentProxy.unmarkText()
        } else {
            textDocumentProxy.setMarkedText(rendered, selectedRange: NSRange(location: rendered.utf16.count, length: 0))
        }
        suppressTextChanges = false
    }

    func finish(_ replacement: String? = nil) {
        guard !composition.isEmpty || !rendered.isEmpty else { return }
        suppressTextChanges = true
        if let replacement {
            textDocumentProxy.setMarkedText(replacement, selectedRange: NSRange(location: replacement.utf16.count, length: 0))
        }
        textDocumentProxy.unmarkText()
        suppressTextChanges = false
        composition = ""
        rendered = ""
    }

    func space() {
        touchFeedback()
        composingUndo = nil
        if pendingSearch != nil { searchText += " "; updateHeader(); return }
        if emit("space") as? Bool == false { return }
        if cjk && !composition.isEmpty {
            finish(candidates().first ?? rendered)
            redraw()
            return
        }
        finish()
        glideAlternatives.removeAll()
        let word = prefix
        let token = context.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        if !privateInput, let shortcut = preferences.activePlugins.reversed().compactMap({ $0.shortcuts[token] }).first {
            erase(token.count)
            insert(Plugin.expand(shortcut) + " ")
        } else if Date().timeIntervalSince(lastSpace) < 0.34, context.last == " ",
                  context.dropLast().last?.isLetter == true {
            erase(1)
            insert(". ")
            lastSpace = .distantPast
        } else {
            var correction: String?
            if !word.isEmpty && canSuggest && preferences.autocorrect && language.autoCorrect {
                correction = lexicon.correction(word, language: dictionary) ?? supplementary[word.lowercased()]
                if let correction, word.first?.isUppercase == true {
                    self.composingUndo = (word, correction.capitalized)
                } else if let correction {
                    self.composingUndo = (word, correction)
                }
                if let undo = composingUndo {
                    erase(word.count)
                    insert(undo.corrected)
                    correction = undo.corrected
                }
            }
            insert(" ")
            lastSpace = Date()
            learn(correction ?? word)
            if !word.isEmpty { emit("word", ["word": correction ?? word], needsText: true) }
        }
        redraw()
    }

    func enter() {
        if let search = pendingSearch { completeSearch(search); return }
        if emit("enter") as? Bool == false { return }
        finish(cjk ? candidates().first : nil)
        insert("\n")
        redraw()
    }

    func backspace() {
        touchFeedback()
        if pendingSearch != nil { if !searchText.isEmpty { searchText.removeLast() }; updateHeader(); return }
        if emit("backspace") as? Bool == false { return }
        if !composition.isEmpty {
            composition.removeLast()
            updateComposition()
        } else if let undo = composingUndo, context.hasSuffix(undo.corrected + " ") {
            erase(undo.corrected.count + 1)
            insert(undo.word)
        } else {
            erase(1)
        }
        composingUndo = nil
        glideAlternatives.removeAll()
        redraw()
    }

    func deleteWord() {
        if pendingSearch != nil { searchText = ""; updateHeader(); return }
        if !composition.isEmpty { composition = ""; updateComposition(); redraw(); return }
        let trailing = context.reversed().prefix(while: \.isWhitespace).count
        let count = context.dropLast(trailing).reversed().prefix { !$0.isWhitespace }.count
        erase(max(1, count + trailing))
        composingUndo = nil
        redraw()
    }

    func candidates() -> [String] {
        guard !composition.isEmpty else { return [] }
        if currentComposition == "pinyin" { return lexicon.complete(composition.replacingOccurrences(of: "'", with: ""), language: cjkDictionary) }
        if currentComposition == "kana" {
            let katakana = rendered.applyingTransform(.hiraganaToKatakana, reverse: false) ?? rendered
            return lexicon.complete(rendered, language: cjkDictionary) + [rendered, katakana]
        }
        return []
    }

    func suggestions() -> [String] {
        let values: [String]
        if cjk && !composition.isEmpty {
            values = candidates() + [rendered]
        } else if !canSuggest {
            return []
        } else if !glideAlternatives.isEmpty {
            values = glideAlternatives
        } else {
            let word = prefix
            if word.isEmpty {
                let words = context.split(whereSeparator: \.isWhitespace).suffix(2).map { String($0).trimmingCharacters(in: .punctuationCharacters) }
                values = lexicon.follow(words, language: dictionary)
            } else {
                let learnedWords = (learned[dictionary] ?? [:]).filter { $0.key.hasPrefix(word.lowercased()) }
                    .sorted { $0.value > $1.value }.prefix(4).map(\.key)
                let matches = lexicon.complete(word, language: dictionary)
                let locale = language.locale.replacingOccurrences(of: "-", with: "_")
                let systemLanguage = UITextChecker.availableLanguages.first { $0 == locale }
                    ?? UITextChecker.availableLanguages.first { $0.hasPrefix(String(locale.split(separator: "_").first ?? "")) }
                let system = systemLanguage.flatMap {
                    checker.completions(forPartialWordRange: NSRange(location: 0, length: word.utf16.count), in: word, language: $0)
                } ?? []
                let typo = lexicon.correction(word, language: dictionary) ?? supplementary[word.lowercased()]
                values = [word] + (typo.map { [$0] } ?? []) + learnedWords + matches + system
            }
        }
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    func pick(_ word: String) {
        if emit("pick", ["word": word], needsText: true) as? Bool == false { return }
        if cjk && !composition.isEmpty {
            finish(word)
        } else {
            let previous = prefix
            finish()
            if !lastGlide.isEmpty && !glideAlternatives.isEmpty && context.hasSuffix(lastGlide + " ") {
                erase(lastGlide.count + 1)
            } else {
                erase(previous.count)
            }
            insert(word + " ")
            learn(word)
        }
        glideAlternatives.removeAll()
        lastGlide = ""
        redraw()
    }

    func learn(_ word: String) {
        guard canSuggest, preferences.learn, word.count >= 2, word.count < 64,
              word.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" }) else { return }
        var words = learned[dictionary] ?? [:]
        words[word.lowercased(), default: 0] += 1
        if words.count > 500 { words = Dictionary(uniqueKeysWithValues: words.sorted { $0.value > $1.value }.prefix(450).map { ($0.key, $0.value) }) }
        learned[dictionary] = words
        defaults.set(learned, forKey: "learned")
    }

    func pickVariant(_ value: String) {
        panel = .typing
        type(value)
        redraw()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer.view === view else { return true }
        if captureTouches { return !privateInput }
        guard preferences.glide, !privateInput, language.dictionary != nil, symbols == 0, pendingSearch == nil,
              let pan = gestureRecognizer as? UIPanGestureRecognizer, case .typing = panel else { return false }
        let location = pan.location(in: view)
        let displacement = pan.translation(in: view)
        let start = CGPoint(x: location.x - displacement.x, y: location.y - displacement.y)
        return button(at: start) != nil
    }

    func button(at point: CGPoint) -> ExpressiveButton? {
        markedButtons.first { $0.convert($0.bounds, to: view).insetBy(dx: -2, dy: -2).contains(point) }
    }

    @objc func trackGlide(_ pan: UIPanGestureRecognizer) {
        let point = pan.location(in: view)
        if captureTouches {
            let kind = pan.state == .began ? "down" : pan.state == .changed ? "move" : "up"
            emit("touch", ["type": kind, "x": point.x, "y": point.y, "pointer": 0], needsText: true)
            return
        }
        if pan.state == .began {
            let displacement = pan.translation(in: view)
            let first = CGPoint(x: point.x - displacement.x, y: point.y - displacement.y)
            points = [first]
            path = button(at: first)?.value.map { [$0] } ?? []
        }
        if pan.state == .began || pan.state == .changed || pan.state == .ended {
            points.append(point)
            if let letter = button(at: point)?.value, path.last != letter { path.append(letter) }
            overlay.trail = points
            overlay.trailColor = theme.accent
        }
        if pan.state == .ended || pan.state == .cancelled {
            defer { overlay.trail = []; points = []; path = [] }
            guard pan.state == .ended, path.count > 1 else {
                if pan.state == .ended, let letter = path.first { type(shifted(letter)) }
                return
            }
            let choices = lexicon.glide(path, language: dictionary)
            guard let word = choices.first else { return }
            let final = autoShift || shift > 0 ? word.prefix(1).uppercased() + word.dropFirst() : word
            finish()
            insert(final + " ")
            lastGlide = final
            glideAlternatives = choices
            shift = shift == 2 ? 2 : 0
            emit("glide", ["word": final, "alternatives": choices], needsText: true)
            redraw()
        }
    }

    @objc func moveOnSpace(_ pan: UIPanGestureRecognizer) {
        let distance = pan.translation(in: pan.view).x
        let steps = Int(distance / 13)
        if steps != 0 {
            finish()
            textDocumentProxy.adjustTextPosition(byCharacterOffset: steps)
            pan.setTranslation(.zero, in: pan.view)
        }
    }
}

final class ExpressiveInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

func L(_ english: String, _ russian: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("ru") == true ? russian : english
}
