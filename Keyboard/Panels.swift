import UIKit
import UniformTypeIdentifiers

extension KeyboardController {
    var panelTitle: String {
        switch panel {
        case .typing: return language.space
        case .toolbar: return L("Tools", "Инструменты")
        case .emoji: return L("Emoji", "Эмодзи")
        case .clipboard: return L("Clipboard", "Буфер обмена")
        case .plugins: return L("Plugins", "Плагины")
        case .gifs: return "GIF"
        case .translate: return L("Translate", "Перевод")
        case .voice: return L("Dictation", "Диктовка")
        case .script(let id, _): return runtimes[id]?.plugin.name ?? ""
        case .variants: return L("Alternatives", "Варианты")
        }
    }

    func scroll(horizontal: Bool = false, into parent: UIStackView? = nil) -> UIStackView {
        let target = parent ?? content
        let scroller = UIScrollView()
        scroller.alwaysBounceVertical = !horizontal
        scroller.alwaysBounceHorizontal = horizontal
        scroller.showsHorizontalScrollIndicator = false
        let list = UIStackView()
        list.axis = horizontal ? .horizontal : .vertical
        list.spacing = 5
        list.translatesAutoresizingMaskIntoConstraints = false
        scroller.addSubview(list)
        target.addArrangedSubview(scroller)
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: scroller.contentLayoutGuide.topAnchor),
            list.bottomAnchor.constraint(equalTo: scroller.contentLayoutGuide.bottomAnchor),
            list.leadingAnchor.constraint(equalTo: scroller.contentLayoutGuide.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: scroller.contentLayoutGuide.trailingAnchor),
            horizontal ? list.heightAnchor.constraint(equalTo: scroller.frameLayoutGuide.heightAnchor)
                       : list.widthAnchor.constraint(equalTo: scroller.frameLayoutGuide.widthAnchor)
        ])
        if horizontal { scroller.heightAnchor.constraint(equalToConstant: 34).isActive = true }
        return list
    }

    func grid(_ values: [String], columns: Int, into target: UIStackView? = nil,
              size: CGFloat = 18, action: @escaping (String) -> Void) {
        let target = target ?? scroll()
        let width = max(1, columns)
        for index in stride(from: 0, to: values.count, by: width) {
            var buttons: [UIView] = values[index..<min(index + width, values.count)].map { value in
                key(value, size: size) { action(value) }
            }
            while buttons.count < width { buttons.append(UIView()) }
            let line = row(buttons)
            line.heightAnchor.constraint(equalToConstant: 39).isActive = true
            target.addArrangedSubview(line)
        }
    }

    func changeSettings(_ change: (inout Preferences) -> Void) {
        var next = preferences
        change(&next)
        do { try SharedStore.save(next); reload() } catch { setStatus(error.localizedDescription) }
    }

    func showToolbar() {
        let tools: [(String, Panel)] = [
            (L("☺  Emoji", "☺  Эмодзи"), .emoji), ("GIF", .gifs),
            (L("Clipboard", "Буфер"), .clipboard), (L("Translate", "Перевод"), .translate),
            (L("Dictation", "Диктовка"), .voice), (L("Plugins", "Плагины"), .plugins)
        ]
        let list = scroll()
        if SharedStore.sharedContainer == nil {
            let apply = key(L("Apply settings from app", "Применить настройки из приложения"), style: 2, size: 15) { [weak self] in
                guard let self else { return }
                guard self.hasFullAccess else {
                    self.setStatus(L("Allow Full Access to import settings.", "Чтобы перенести настройки, разрешите полный доступ."))
                    return
                }
                guard let data = UIPasteboard.general.data(forPasteboardType: SharedStore.transferType) else {
                    self.setStatus(L("First copy settings in the app.", "Сначала скопируйте настройки в приложении."))
                    return
                }
                do {
                    try SharedStore.accept(data)
                    self.reload()
                    self.switchPanel(.typing)
                } catch { self.setStatus(error.localizedDescription) }
            }
            apply.heightAnchor.constraint(equalToConstant: 39).isActive = true
            list.addArrangedSubview(apply)
            let quick = key(L("Quick settings", "Быстрые настройки"), style: 1, size: 15)
            quick.menu = UIMenu(children: [
                UIMenu(title: L("Design", "Оформление"), children: Design.allCases.map { design in
                    UIAction(title: design.title, state: design == preferences.design ? .on : .off) { [weak self] _ in
                        self?.changeSettings { $0.design = design; $0.radius = design.radius; $0.skinPlugin = "" }
                    }
                }),
                UIMenu(title: L("Languages", "Языки"), children: preferences.allLayouts.map { layout in
                    UIAction(title: layout.space, state: preferences.languages.contains(layout.id) ? .on : .off) { [weak self] _ in
                        self?.changeSettings {
                            if !$0.languages.contains(layout.id) { $0.languages.append(layout.id) }
                            else if $0.languages.count > 1 { $0.languages.removeAll { $0 == layout.id } }
                        }
                    }
                }),
                UIAction(title: L("Number row", "Ряд цифр"), state: preferences.numberRow ? .on : .off) { [weak self] _ in
                    self?.changeSettings { $0.numberRow.toggle() }
                },
                UIAction(title: L("Autocorrect", "Автоисправление"), state: preferences.autocorrect ? .on : .off) { [weak self] _ in
                    self?.changeSettings { $0.autocorrect.toggle() }
                }
            ])
            quick.showsMenuAsPrimaryAction = true
            quick.heightAnchor.constraint(equalToConstant: 39).isActive = true
            list.addArrangedSubview(quick)
        }
        grid(tools.map(\.0), columns: 3, into: list, size: 14) { [weak self] name in
            if let panel = tools.first(where: { $0.0 == name })?.1 { self?.switchPanel(panel) }
        }
        grid([privateInput ? L("Resume learning", "Выйти из инкогнито") : L("Incognito", "Инкогнито"),
              "◀", "▶"], columns: 3, into: list, size: 13) { [weak self] value in
            guard let self else { return }
            if value == "◀" || value == "▶" {
                self.textDocumentProxy.adjustTextPosition(byCharacterOffset: value == "◀" ? -1 : 1)
            } else {
                guard !self.preferences.incognito else {
                    self.setStatus(L("Incognito is enabled in Settings.", "Инкогнито включено в настройках."))
                    return
                }
                self.incognito.toggle()
                if self.privateInput {
                    self.runtimes.removeAll()
                    self.overlay.commands = []
                    self.captureTouches = false
                } else {
                    self.loadScripts()
                }
                self.redraw()
            }
        }
        for runtime in runtimes.values.sorted(by: { $0.plugin.id < $1.plugin.id }) {
            for (index, button) in (runtime.catalog["buttons"] ?? []).enumerated() {
                if let title = button["title"] as? String {
                    let action = key(title, style: 1, size: 14) { [weak self] in
                        _ = runtime.event("$button", index)
                        self?.updateHeader()
                    }
                    action.heightAnchor.constraint(equalToConstant: 36).isActive = true
                    list.addArrangedSubview(action)
                }
            }
        }
    }

    func beginSearch(_ target: Panel) {
        searchText = ""
        pendingSearch = target
        panel = .typing
        symbols = 0
        redraw()
    }

    func completeSearch(_ target: Panel) {
        pendingSearch = nil
        if case .script = target { panel = target } else { switchPanel(target) }
        if case .script(let id, _) = target {
            if let callback = inputCallback {
                _ = runtimes[id]?.event("$panelPick", [callback, searchText])
            }
            if let runtime = runtimes[id] { _ = runtime.event("$input", searchText) }
            inputCallback = nil
            redraw()
        }
    }

    func showEmoji() {
        let catalog = EmojiCatalog.shared
        let names = ["◷"] + catalog.groups.map { $0.1.first?.glyph ?? "☺" }
        let tabs = scroll(horizontal: true)
        let search = key("⌕", style: 2, accessible: L("Search emoji", "Поиск эмодзи")) { [weak self] in self?.beginSearch(.emoji) }
        search.widthAnchor.constraint(equalToConstant: 42).isActive = true
        tabs.addArrangedSubview(search)
        for (index, glyph) in names.enumerated() {
            let tab = key(glyph, style: category == index && searchText.isEmpty ? 2 : 1, size: 16) { [weak self] in
                self?.searchText = ""
                self?.category = index
                self?.renderPanel()
            }
            tab.widthAnchor.constraint(equalToConstant: 37).isActive = true
            tabs.addArrangedSubview(tab)
        }
        let entries: [EmojiEntry]
        if !searchText.isEmpty { entries = catalog.search(searchText) }
        else if category == 0 && !recentEmoji.isEmpty {
            entries = recentEmoji.map { EmojiEntry(index: 0, glyph: $0, variants: [], keywords: "") }
        } else if !catalog.groups.isEmpty {
            entries = catalog.groups[min(max(0, category - 1), catalog.groups.count - 1)].1
        } else { entries = [] }
        let list = scroll()
        let choices = Array(entries.prefix(480))
        let columns = 8
        for start in stride(from: 0, to: choices.count, by: columns) {
            var items: [UIView] = choices[start..<min(start + columns, choices.count)].map { entry in
                let button = key(entry.glyph, size: 21) { [weak self] in self?.chooseEmoji(entry.glyph) }
                if let image = catalog.image(entry.glyph, style: preferences.emojiStyle) {
                    button.setTitle(nil, for: .normal)
                    button.setImage(image.withRenderingMode(.alwaysOriginal), for: .normal)
                    button.imageView?.contentMode = .scaleAspectFit
                }
                if !entry.variants.isEmpty {
                    button.hold = { [weak self] in
                        guard let self else { return }
                        self.clear(self.content)
                        self.grid(entry.variants, columns: 6) { [weak self] value in self?.chooseEmoji(value) }
                    }
                }
                return button
            }
            while items.count < columns { items.append(UIView()) }
            let line = row(items)
            line.heightAnchor.constraint(equalToConstant: 34).isActive = true
            list.addArrangedSubview(line)
        }
        if choices.isEmpty { list.addArrangedSubview(label(L("No emoji found", "Эмодзи не найдены"))) }
    }

    func chooseEmoji(_ emoji: String) {
        insert(emoji)
        if !privateInput {
            recentEmoji.removeAll { $0 == emoji }
            recentEmoji.insert(emoji, at: 0)
            recentEmoji = Array(recentEmoji.prefix(48))
            defaults.set(recentEmoji, forKey: "emoji")
        }
    }

    func showClipboard() {
        let list = scroll()
        guard !privateInput else {
            list.addArrangedSubview(label(L("Clipboard history is paused in incognito.", "В инкогнито история буфера приостановлена.")))
            return
        }
        let read = key(L("Read clipboard", "Прочитать буфер"), style: 2, size: 14) { [weak self] in
            guard let self else { return }
            guard let value = UIPasteboard.general.string, !value.isEmpty else {
                self.setStatus(L("The clipboard is empty or unavailable.", "Буфер пуст или недоступен."))
                return
            }
            let text = String(value.prefix(4_000))
            self.clipboard.removeAll { $0 == text }
            self.clipboard.insert(text, at: 0)
            self.clipboard = Array(self.clipboard.prefix(24))
            self.defaults.set(self.clipboard, forKey: "clipboard")
            self.renderPanel()
        }
        read.heightAnchor.constraint(equalToConstant: 36).isActive = true
        list.addArrangedSubview(read)
        for value in Array(NSOrderedSet(array: snippets + clipboard)).compactMap({ $0 as? String }) {
            let button = key(String(value.prefix(58)), size: 14) { [weak self] in self?.insert(value) }
            let pin = key(snippets.contains(value) ? "★" : "☆", style: 1, accessible: L("Pin", "Закрепить")) { [weak self] in
                guard let self else { return }
                if self.snippets.contains(value) { self.snippets.removeAll { $0 == value } }
                else { self.snippets = [value] + Array(self.snippets.prefix(19)) }
                self.defaults.set(self.snippets, forKey: "snippets")
                self.renderPanel()
            }
            pin.widthAnchor.constraint(equalToConstant: 41).isActive = true
            let remove = key("×", style: 1, accessible: L("Remove", "Удалить")) { [weak self] in
                guard let self else { return }
                self.clipboard.removeAll { $0 == value }
                self.snippets.removeAll { $0 == value }
                self.defaults.set(self.clipboard, forKey: "clipboard")
                self.defaults.set(self.snippets, forKey: "snippets")
                self.renderPanel()
            }
            remove.widthAnchor.constraint(equalToConstant: 41).isActive = true
            let line = row([button, pin, remove], distribution: .fill)
            line.heightAnchor.constraint(equalToConstant: 36).isActive = true
            list.addArrangedSubview(line)
        }
    }

    func showPlugins() {
        let list = scroll()
        guard !privateInput else { list.addArrangedSubview(label(L("Plugins are paused in incognito.", "Плагины приостановлены в инкогнито."))); return }
        for plugin in preferences.activePlugins {
            let catalog = runtimes[plugin.id]?.catalog["panels"] ?? []
            guard !plugin.actions.isEmpty || !plugin.symbols.isEmpty || !catalog.isEmpty || runtimes[plugin.id]?.error != nil else { continue }
            list.addArrangedSubview(label(plugin.name, size: 13))
            for (index, panel) in catalog.enumerated() {
                let button = key(panel["title"] as? String ?? plugin.name, style: 1, size: 14) { [weak self] in
                    self?.switchPanel(.script(plugin.id, index))
                }
                button.heightAnchor.constraint(equalToConstant: 36).isActive = true
                list.addArrangedSubview(button)
            }
            if let error = runtimes[plugin.id]?.error { list.addArrangedSubview(label(error, size: 11)) }
            for index in stride(from: 0, to: plugin.actions.count, by: 3) {
                let buttons = plugin.actions[index..<min(index + 3, plugin.actions.count)].map { action in
                    self.key(action.title, size: 11) { [weak self] in self?.run(action) }
                }
                let line = row(buttons)
                line.heightAnchor.constraint(equalToConstant: 34).isActive = true
                list.addArrangedSubview(line)
            }
            for symbol in plugin.symbols {
                list.addArrangedSubview(label(symbol.title, size: 12))
                grid(symbol.items, columns: symbol.items.allSatisfy { $0.count < 4 } ? 8 : 3, into: list, size: 13) { [weak self] in self?.insert($0) }
            }
        }
    }

    func run(_ action: Plugin.Action) {
        if action.type == "insert", let text = action.text {
            insert(Plugin.expand(text))
        } else if let key = action.key {
            runNamedKey(key)
        } else if let url = action.url, let value = URL(string: url), value.scheme == "https" {
            insert(value.absoluteString)
        }
        updateHeader()
    }

    func runNamedKey(_ key: String) {
        switch key {
        case "copy", "cut":
            if let selected = textDocumentProxy.selectedText, !selected.isEmpty {
                UIPasteboard.general.string = selected
                if key == "cut" { erase(1) }
            }
        case "paste":
            if let text = UIPasteboard.general.string { insert(text) }
        case "home": textDocumentProxy.adjustTextPosition(byCharacterOffset: -context.count)
        case "end": textDocumentProxy.adjustTextPosition(byCharacterOffset: textDocumentProxy.documentContextAfterInput?.count ?? 0)
        case "left": textDocumentProxy.adjustTextPosition(byCharacterOffset: -1)
        case "right": textDocumentProxy.adjustTextPosition(byCharacterOffset: 1)
        case "delete_word": deleteWord()
        case "tab": insert("\t")
        case "enter": enter()
        case "space": space()
        case "backspace", "delete": backspace()
        case "shift": toggleShift()
        case "undo":
            if let undo = composingUndo, context.hasSuffix(undo.corrected + " ") { backspace() }
            else { setStatus(L("Use the host app’s Undo.", "Отмену можно сделать в приложении.")) }
        case "redo", "select_all": setStatus(L("Use the host app’s editing menu.", "Используйте меню редактирования приложения."))
        default: if key.count <= 12 { type(key) }
        }
    }

    func showGIFs() {
        let search = key(searchText.isEmpty ? L("Search GIFs", "Поиск GIF") : searchText, style: 2, size: 14) { [weak self] in self?.beginSearch(.gifs) }
        search.heightAnchor.constraint(equalToConstant: 33).isActive = true
        content.addArrangedSubview(search)
        let list = scroll()
        let results = gifResults.isEmpty ? Self.defaultGIFs.filter { searchText.isEmpty || $0.0.localizedCaseInsensitiveContains(searchText) } : gifResults
        if results.isEmpty { list.addArrangedSubview(label(L("No GIFs found", "GIF не найдены"))) }
        for start in stride(from: 0, to: results.count, by: 3) {
            let buttons = results[start..<min(start + 3, results.count)].map { name, url in
                let button = key(name, size: 13) { [weak self] in self?.insert(url.absoluteString) }
                button.hold = { [weak self] in self?.copyGIF(url) }
                return button
            }
            let line = row(buttons)
            line.heightAnchor.constraint(equalToConstant: 40).isActive = true
            list.addArrangedSubview(line)
        }
        list.addArrangedSubview(label(L("Tap to insert a link. Hold to copy the GIF.", "Касание вставляет ссылку. Удержание копирует GIF."), size: 11))
        list.addArrangedSubview(label("Powered by GIPHY", size: 11))
    }

    func copyGIF(_ url: URL) {
        guard hasFullAccess, !privateInput else {
            setStatus(L("Copying GIFs requires Full Access.", "Для копирования GIF нужен полный доступ."))
            return
        }
        pendingNetwork?.cancel()
        pendingNetwork = Task { [weak self] in
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let self, !Task.isCancelled, case .gifs = self.panel else { return }
                guard response.mimeType == "image/gif", data.count <= 5_000_000 else {
                    self.setStatus(L("GIF unavailable or too large.", "GIF недоступен или слишком большой."))
                    return
                }
                UIPasteboard.general.setData(data, forPasteboardType: UTType.gif.identifier)
                self.setStatus(L("GIF copied. Paste it in your app.", "GIF скопирован. Вставьте его в приложении."))
            } catch {
                if !Task.isCancelled { self?.setStatus(L("GIF download failed", "Ошибка загрузки GIF")) }
            }
        }
    }

    static var defaultGIFs: [(String, URL)] {
        [("Happy", "111ebonMs90YLu"), ("Thanks", "osjgQPWRx3cac"), ("Wow", "5VKbvrjxpVJCM"),
         ("Hello", "ASd0Ukj0y3qMM"), ("Laugh", "10JhviFuU2gWD6"), ("Love", "MDJ9IbxxvDUQM")].compactMap { name, id in
            URL(string: "https://media.giphy.com/media/\(id)/giphy.gif").map { (name, $0) }
         }
    }

    func fetchGIFs() {
        pendingNetwork?.cancel()
        gifResults = []
        renderPanel()
        guard hasFullAccess, !privateInput, !preferences.gifKey.isEmpty else { return }
        var address = URLComponents(string: "https://api.giphy.com/v1/gifs/\(searchText.isEmpty ? "trending" : "search")")!
        address.queryItems = [URLQueryItem(name: "api_key", value: preferences.gifKey),
                              URLQueryItem(name: "limit", value: "24"), URLQueryItem(name: "rating", value: "pg-13")]
        if !searchText.isEmpty { address.queryItems?.append(URLQueryItem(name: "q", value: searchText)) }
        guard let url = address.url else { return }
        pendingNetwork = Task { [weak self] in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let self, !Task.isCancelled, case .gifs = self.panel else { return }
                let dataObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let rows = dataObject?["data"] as? [[String: Any]] ?? []
                self.gifResults = rows.compactMap { row in
                    guard let id = row["id"] as? String,
                          id.range(of: "^[a-zA-Z0-9]+$", options: .regularExpression) != nil,
                          let url = URL(string: "https://media.giphy.com/media/\(id)/giphy.gif") else { return nil }
                    return (row["title"] as? String ?? "GIF", url)
                }
                self.renderPanel()
            } catch { if !Task.isCancelled { self?.setStatus(L("GIF search failed", "Ошибка поиска GIF")) } }
        }
    }

    func showTranslate() {
        let list = scroll()
        let source = searchText.isEmpty ? (textDocumentProxy.selectedText ?? "") : searchText
        list.addArrangedSubview(label(source.isEmpty ? L("Select text or type a phrase.", "Выделите текст или введите фразу.") : source))
        let input = key(L("Type a phrase", "Ввести фразу"), style: 1, size: 14) { [weak self] in self?.beginSearch(.translate) }
        let translate = key(L("Translate to", "Перевести на") + " " + preferences.translationTarget.uppercased(), style: 2, size: 14) { [weak self] in
            self?.translate(source)
        }
        let actions = row([input, translate])
        actions.heightAnchor.constraint(equalToConstant: 37).isActive = true
        list.addArrangedSubview(actions)
        if !translation.isEmpty {
            list.addArrangedSubview(label(translation))
            let insert = key(L("Insert translation", "Вставить перевод"), style: 1, size: 14) { [weak self] in
                if let self { self.insert(self.translation); self.switchPanel(.typing) }
            }
            insert.heightAnchor.constraint(equalToConstant: 36).isActive = true
            list.addArrangedSubview(insert)
        }
    }

    func translate(_ input: String) {
        guard !input.isEmpty else { return }
        guard hasFullAccess, !privateInput else { setStatus(L("Translation requires Full Access.", "Для перевода нужен полный доступ.")); return }
        pendingNetwork?.cancel()
        setStatus(L("Translating…", "Перевод…"))
        var address = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        address.queryItems = [("client", "gtx"), ("sl", "auto"), ("tl", preferences.translationTarget),
                              ("dt", "t"), ("q", String(input.prefix(1_000)))].map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = address.url else { return }
        pendingNetwork = Task { [weak self] in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let self, !Task.isCancelled, case .translate = self.panel else { return }
                let result = try JSONSerialization.jsonObject(with: data) as? [Any]
                let segments = result?.first as? [[Any]] ?? []
                self.translation = segments.compactMap { $0.first as? String }.joined()
                self.setStatus(self.translation.isEmpty ? L("Translation unavailable", "Перевод недоступен") : "")
                self.renderPanel()
            } catch { if !Task.isCancelled { self?.setStatus(L("Translation failed", "Ошибка перевода")) } }
        }
    }

    func showVoice() {
        let list = scroll()
        list.addArrangedSubview(label(L("Record in Expressive Keyboard, then return here and insert the transcript.",
                                       "Запишите фразу в Expressive Keyboard, затем вернитесь сюда и вставьте расшифровку.")))
        if let transcript = SharedStore.read(String.self, "dictation.json"), !transcript.isEmpty {
            list.addArrangedSubview(label(transcript))
            let button = key(L("Insert transcript", "Вставить расшифровку"), style: 2, size: 14) { [weak self] in
                self?.insert(transcript)
                self?.switchPanel(.typing)
            }
            button.heightAnchor.constraint(equalToConstant: 38).isActive = true
            list.addArrangedSubview(button)
        }
    }

    func setStatus(_ message: String) {
        status = String(message.prefix(120))
        updateHeader()
        if !message.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
                if self?.status == message { self?.status = ""; self?.updateHeader() }
            }
        }
    }
}
