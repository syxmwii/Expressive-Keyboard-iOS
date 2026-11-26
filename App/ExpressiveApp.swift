import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import ImageIO
import CoreText

@main
struct ExpressiveApp: App {
    var body: some Scene {
        WindowGroup { SettingsView() }
    }
}

func L(_ english: String, _ russian: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("ru") == true ? russian : english
}

struct SettingsView: View {
    enum ImportKind { case plugin, font, backup }

    @State private var preferences = SharedStore.load()
    @State private var trial = ""
    @State private var finding = ""
    @State private var error = ""
    @State private var importing = false
    @State private var importKind = ImportKind.plugin
    @State private var photo: PhotosPickerItem?
    @State private var pendingPlugin: Plugin?
    @State private var confirmPlugin = false
    @State private var export = false
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    private let accent = Color(red: 0.43, green: 0.30, blue: 0.71)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    hero
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section(L("Set up", "Подключение")) {
                    if !FileManager.default.fileExists(atPath: Bundle.main.builtInPlugInsURL?.appendingPathComponent("ExpressiveExtension.appex/Info.plist").path ?? "") {
                        Text(L("Keyboard extension missing. Reinstall the IPA and keep app extensions when signing.",
                               "Расширение клавиатуры отсутствует. Переустановите IPA, сохранив расширения при подписи."))
                            .foregroundStyle(.red)
                    }
                    if !preferences.setup {
                        Text(L("Add Expressive Keyboard in Settings → General → Keyboard → Keyboards → Add New Keyboard.",
                               "Добавьте Expressive Keyboard в Настройки → Основные → Клавиатура → Клавиатуры → Новые клавиатуры."))
                        Text(L("Then hold the globe key to switch. Full Access enables online tools and shared features.",
                               "Затем удерживайте глобус для переключения. Полный доступ включает онлайн-инструменты и общие функции."))
                            .foregroundStyle(.secondary)
                        Button(L("Open Settings", "Открыть настройки")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        Button(L("I’ve added the keyboard", "Я добавил клавиатуру")) { preferences.setup = true }
                    }
                    if SharedStore.sharedContainer == nil {
                        Button(L("Copy settings for keyboard", "Скопировать настройки для клавиатуры")) {
                            do {
                                let data = try SharedStore.transfer(preferences)
                                guard data.count <= 32_000_000 else { throw CocoaError(.fileReadTooLarge) }
                                UIPasteboard.general.setItems([[SharedStore.transferType: data]],
                                    options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(300)])
                                error = L("Open Expressive Keyboard → ⚙ → Apply settings within five minutes.",
                                          "В течение пяти минут откройте Expressive Keyboard → ⚙ → Применить настройки.")
                            } catch { self.error = error.localizedDescription }
                        }
                        Text(L("After changing settings, copy them here and apply them in the keyboard. Clipboard transfer needs Full Access. Quick settings are also available directly on the keyboard.",
                               "После изменений скопируйте настройки здесь и примените их в клавиатуре. Для переноса через буфер нужен полный доступ. Быстрые настройки можно менять прямо на клавиатуре."))
                            .font(.footnote)
                    }
                    TextField(L("Try typing here", "Попробуйте печатать здесь"), text: $trial, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section(L("Keyboard", "Клавиатура")) {
                    NavigationLink { languageList } label: {
                        Label(L("Languages and layouts", "Языки и раскладки"), systemImage: "globe")
                    }
                    NavigationLink { appearance } label: {
                        Label(L("Appearance", "Оформление"), systemImage: "paintpalette")
                    }
                    NavigationLink { typing } label: {
                        Label(L("Typing", "Ввод"), systemImage: "keyboard")
                    }
                    NavigationLink { pluginList } label: {
                        Label(L("Plugins and mods", "Плагины и моды"), systemImage: "puzzlepiece.extension")
                    }
                    NavigationLink { VoiceView(language: preferences.enabledLayouts.first?.locale ?? "en-US") } label: {
                        Label(L("Dictation", "Диктовка"), systemImage: "mic")
                    }
                }
                Section(L("Data", "Данные")) {
                    Button(L("Export settings", "Экспортировать настройки")) { export = true }
                    Button(L("Import settings", "Импортировать настройки")) { pick(.backup) }
                    Link("Expressive Keyboard · GitHub", destination: URL(string: "https://github.com/kotlalipopus/Expressive-Keyboard")!)
                    NavigationLink(L("Open-source credits", "Открытые компоненты")) { credits }
                }
            }
            .navigationTitle("Expressive")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(accent)
        .onChange(of: encodedPreferences) { _, _ in persist() }
        .onChange(of: photo) { _, item in
            if let item { Task { await importPhoto(item) } }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: fileTypes) { result in
            do { try importFile(result.get()) } catch { self.error = error.localizedDescription }
        }
        .fileExporter(isPresented: $export, document: SettingsBackup(preferences: preferences),
                      contentType: .json, defaultFilename: "Expressive-iOS-settings") { result in
            if case .failure(let error) = result { self.error = error.localizedDescription }
        }
        .alert(L("Import plugin", "Импорт плагина"), isPresented: $confirmPlugin, presenting: pendingPlugin) { plugin in
            Button(L("Install", "Установить")) {
                preferences.plugins.removeAll { $0.id == plugin.id }
                preferences.plugins.append(plugin)
                preferences.disabledPlugins.remove(plugin.id)
            }
            Button(L("Cancel", "Отмена"), role: .cancel) { pendingPlugin = nil }
        } message: { plugin in
            Text(plugin.permissions.isEmpty ? plugin.name : plugin.name + "\n" + L("Requested access", "Разрешения") + " · " + plugin.permissions.joined(separator: ", "))
        }
        .alert(L("Expressive Keyboard", "Expressive Keyboard"), isPresented: Binding(
            get: { !error.isEmpty }, set: { if !$0 { error = "" } })
        ) { Button("OK") { error = "" } } message: { Text(error) }
    }

    private var skinTitle: String {
        guard let skin = preferences.activePlugins.first(where: { $0.id == preferences.skinPlugin }) else {
            return preferences.design.title
        }
        return "\(preferences.design.title) · \(skin.name)"
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "keyboard")
                    .font(.system(size: 24, weight: .semibold))
                    .padding(11)
                    .background(.white.opacity(0.17), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Expressive Keyboard").font(.title2.weight(.semibold))
                    Text(skinTitle).font(.subheadline)
                }
                Spacer()
            }
            preview
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(LinearGradient(colors: [Color(red: 0.35, green: 0.23, blue: 0.64), Color(red: 0.55, green: 0.36, blue: 0.75)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 29))
        .accessibilityHidden(false)
    }

    private var preview: some View {
        let palette = KeyboardTheme(preferences, dark: colorScheme == .dark)
        return VStack(spacing: 4) {
            ForEach(Array(preferences.enabledLayouts[0].rows.prefix(4).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 3) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, key in
                        Text(key)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 23)
                            .foregroundStyle(Color(uiColor: palette.text))
                            .background(Color(uiColor: palette.key), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            HStack(spacing: 4) {
                Text("123").frame(width: 38, height: 23)
                    .foregroundStyle(Color(uiColor: palette.functionText))
                    .background(Color(uiColor: palette.function), in: RoundedRectangle(cornerRadius: 8))
                Text(preferences.enabledLayouts[0].space).frame(maxWidth: .infinity).frame(height: 23)
                    .foregroundStyle(Color(uiColor: palette.text))
                    .background(Color(uiColor: palette.key), in: RoundedRectangle(cornerRadius: 8))
                Text("↵").frame(width: 40, height: 23)
                    .foregroundStyle(Color(uiColor: palette.accentText))
                    .background(Color(uiColor: palette.accent), in: RoundedRectangle(cornerRadius: 8))
            }
            .font(.system(size: 11, weight: .semibold))
        }
        .accessibilityHidden(true)
    }

    private var languageList: some View {
        List {
            ForEach(preferences.allLayouts.filter {
                finding.isEmpty || [$0.displayName, $0.title, $0.space, $0.id].contains { $0.localizedCaseInsensitiveContains(finding) }
            }) { layout in
                let isEnabled = preferences.languages.contains(layout.id)
                HStack {
                    Button {
                        if isEnabled {
                            if preferences.languages.count > 1 { preferences.languages.removeAll { $0 == layout.id } }
                        } else { preferences.languages.append(layout.id) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(layout.displayName)
                                if layout.displayName != layout.space { Text(layout.space).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                        }
                    }
                    .buttonStyle(.borderless)
                    NavigationLink {
                        LayoutEditor(layout: layout, rows: Binding(
                            get: { preferences.layouts[layout.id] },
                            set: { preferences.layouts[layout.id] = $0 }))
                    } label: {
                        Image(systemName: "pencil")
                            .accessibilityLabel(L("Edit layout", "Изменить раскладку"))
                    }
                    .fixedSize()
                }
            }
        }
        .navigationTitle(L("Languages", "Языки"))
        .searchable(text: $finding)
    }

    private var appearance: some View {
        Form {
            Section(L("Design", "Стиль")) {
                Picker(L("Keyboard style", "Дизайн клавиатуры"), selection: $preferences.design) {
                    ForEach(Design.allCases) { value in Text(value.title).tag(value) }
                }
                .onChange(of: preferences.design) { _, value in
                    preferences.radius = value.radius
                    preferences.skinPlugin = ""
                }
                Picker(L("Expressive shapes", "Фигуры"), selection: $preferences.shapes) {
                    Text(L("Off", "Без фигур")).tag(0)
                    Text(L("Accent keys", "Акцентные клавиши")).tag(1)
                    Text(L("All keys", "Все клавиши")).tag(2)
                }
                TextField(L("Accent color · #6C49AB", "Цвет акцента · #6C49AB"), text: $preferences.tint)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Picker(L("Emoji style", "Стиль эмодзи"), selection: $preferences.emojiStyle) {
                    Text(L("System", "Системный")).tag("system")
                    Text("Twemoji").tag("twemoji")
                    Text("Noto").tag("noto")
                    Text("Blob").tag("blob")
                    Text("OpenMoji").tag("openmoji")
                }
                if preferences.activePlugins.contains(where: { $0.skin != nil }) {
                    Picker(L("Plugin skin", "Оформление из плагина"), selection: $preferences.skinPlugin) {
                        Text(L("From design", "По стилю")).tag("")
                        ForEach(preferences.activePlugins.filter { $0.skin != nil }) { Text($0.name).tag($0.id) }
                    }
                }
            }
            Section(L("Size and placement", "Размер и положение")) {
                metric(L("Key height", "Высота клавиш"), $preferences.height, 34...62)
                metric(L("Spacing", "Отступы"), $preferences.spacing, 2...8)
                metric(L("Corner radius", "Скругление"), $preferences.radius, 0...24)
                metric(L("Width", "Ширина"), $preferences.width, 0.72...1, percent: true)
                Picker(L("One-handed", "Одной рукой"), selection: $preferences.hand) {
                    Text(L("Off", "Выкл.")).tag(0)
                    Text(L("Left", "Левая")).tag(-1)
                    Text(L("Right", "Правая")).tag(1)
                }
            }
            Section(L("Custom assets", "Свои материалы")) {
                PhotosPicker(L("Choose background photo", "Выбрать фото для фона"), selection: $photo, matching: .images)
                if preferences.hasPhoto {
                    Button(L("Remove photo", "Удалить фото"), role: .destructive) {
                        preferences.hasPhoto = false
                        if let url = SharedStore.file("background.jpg") { try? FileManager.default.removeItem(at: url) }
                    }
                }
                Button(L("Import font", "Импортировать шрифт")) { pick(.font) }
                if preferences.hasFont {
                    Button(L("Remove font", "Удалить шрифт"), role: .destructive) {
                        preferences.hasFont = false
                        if let url = SharedStore.file("font") { try? FileManager.default.removeItem(at: url) }
                    }
                }
            }
        }
        .navigationTitle(L("Appearance", "Оформление"))
    }

    private var typing: some View {
        Form {
            Section(L("Input", "Ввод")) {
                Toggle(L("Number row", "Ряд цифр"), isOn: $preferences.numberRow)
                Toggle(L("Suggestions", "Подсказки"), isOn: $preferences.suggestions)
                Toggle(L("Autocorrect", "Автоисправление"), isOn: $preferences.autocorrect)
                Toggle(L("Auto-capitalization", "Автозаглавная"), isOn: $preferences.autoCap)
                Toggle(L("Glide typing", "Ввод свайпом"), isOn: $preferences.glide)
            }
            Section(L("Feedback", "Отклик")) {
                Toggle(L("Haptics", "Вибрация"), isOn: $preferences.haptics)
                if preferences.haptics { metric(L("Intensity", "Сила"), $preferences.intensity, 0.1...1, percent: true) }
                Toggle(L("Key sounds", "Звук клавиш"), isOn: $preferences.sound)
            }
            Section(L("Privacy", "Конфиденциальность")) {
                Toggle(L("Incognito", "Инкогнито"), isOn: $preferences.incognito)
                Toggle(L("Learn words", "Запоминать слова"), isOn: $preferences.learn)
            }
            Section(L("Online tools", "Онлайн-инструменты")) {
                SecureField(L("GIPHY API key", "Ключ API GIPHY"), text: $preferences.gifKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker(L("Translation language", "Язык перевода"), selection: $preferences.translationTarget) {
                    ForEach(["ar","de","en","es","fr","hi","it","ja","ko","pl","pt","ru","tr","uk","vi","zh-CN"], id: \.self) { value in
                        Text(Locale.current.localizedString(forIdentifier: value) ?? value).tag(value)
                    }
                }
                Text(L("Search sends the query to GIPHY. Translate sends the chosen phrase to Google Translate.",
                       "Поиск отправляет запрос в GIPHY. Перевод отправляет выбранную фразу в Google Translate."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L("Typing", "Ввод"))
    }

    private var pluginList: some View {
        List {
            Button(L("Import JSON, JavaScript or ZIP", "Импорт JSON, JavaScript или ZIP")) { pick(.plugin) }
            Button(L("Import from Clipboard", "Импорт из буфера")) {
                guard let text = UIPasteboard.general.string else { return }
                do {
                    pendingPlugin = try Plugin.load(Data(text.utf8), type: text.contains("/* @plugin") ? "js" : "json")
                    confirmPlugin = true
                } catch { self.error = error.localizedDescription }
            }
            ForEach(preferences.availablePlugins) { plugin in
                VStack(alignment: .leading, spacing: 5) {
                    Toggle(plugin.name, isOn: Binding(
                        get: { preferences.activePlugins.contains(plugin) },
                        set: { preferences.setPlugin(plugin, enabled: $0) }))
                    if let description = plugin.object["description"] as? String {
                        Text(description).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    if preferences.plugins.contains(plugin) {
                        Button(L("Remove", "Удалить"), role: .destructive) {
                            preferences.plugins.removeAll { $0.id == plugin.id }
                            if preferences.skinPlugin == plugin.id { preferences.skinPlugin = "" }
                        }
                    }
                }
            }
        }
        .navigationTitle(L("Plugins and mods", "Плагины и моды"))
    }

    private var credits: some View {
        List {
            Text("Expressive Keyboard · kotlalipopus · MIT")
            Text("QuickJS · Fabrice Bellard and Charlie Gordon · MIT")
            Link("Twemoji · CC BY 4.0", destination: URL(string: "https://github.com/twitter/twemoji")!)
            Link("Noto and Blob · Apache 2.0", destination: URL(string: "https://github.com/googlefonts/noto-emoji")!)
            Link("OpenMoji · CC BY-SA 4.0", destination: URL(string: "https://openmoji.org/")!)
        }
        .navigationTitle(L("Credits", "Авторы"))
    }

    private func metric(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, percent: Bool = false) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: percent ? "\(Int(value.wrappedValue * 100))%" : "\(Int(value.wrappedValue)) pt")
            Slider(value: value, in: range, step: percent ? 0.01 : 1).accessibilityLabel(title)
        }
    }

    private var encodedPreferences: Data { (try? JSONEncoder.ordered.encode(preferences)) ?? Data() }

    private func persist() {
        do { try SharedStore.save(preferences) }
        catch { self.error = L("Settings could not be saved. Check available device storage.", "Не удалось сохранить настройки. Проверьте свободное место на устройстве.") }
    }

    private var fileTypes: [UTType] {
        switch importKind {
        case .plugin: return [.json, .javaScript, .zip]
        case .font: return [UTType(filenameExtension: "ttf"), UTType(filenameExtension: "otf")].compactMap { $0 }
        case .backup: return [.json]
        }
    }

    private func pick(_ kind: ImportKind) {
        importKind = kind
        importing = true
    }

    private func importFile(_ url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 8_000_000 { throw Plugin.ImportError.invalid }
        let data = try Data(contentsOf: url)
        switch importKind {
        case .plugin:
            pendingPlugin = try url.pathExtension.lowercased() == "zip" ? PluginArchive.load(data) : Plugin.load(data, type: url.pathExtension.lowercased())
            confirmPlugin = true
        case .font:
            guard let provider = CGDataProvider(data: data as CFData), CGFont(provider) != nil,
                  let destination = SharedStore.file("font") else { throw CocoaError(.fileReadCorruptFile) }
            try data.write(to: destination, options: .atomic)
            preferences.hasFont = true
        case .backup:
            var restored = try JSONDecoder().decode(Preferences.self, from: data)
            restored.hasFont = preferences.hasFont
            restored.hasPhoto = preferences.hasPhoto
            for plugin in restored.plugins { restored.disabledPlugins.insert(plugin.id) }
            try SharedStore.save(restored)
            preferences = SharedStore.load()
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1280
                  ] as CFDictionary),
                  let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.8),
                  let target = SharedStore.file("background.jpg") else { throw CocoaError(.fileReadCorruptFile) }
            try jpeg.write(to: target, options: .atomic)
            preferences.hasPhoto = true
        } catch { self.error = error.localizedDescription }
    }
}

private struct LayoutEditor: View {
    let layout: KeyboardLayout
    @Binding var rows: [[String]]?
    @State private var draft = ""
    @State private var invalid = false

    var body: some View {
        Form {
            Text(L("One row per line. Separate multi-character keys with spaces.", "Каждый ряд с новой строки. Отделяйте клавиши из нескольких символов пробелами."))
                .font(.footnote)
            TextEditor(text: $draft).font(.system(.body, design: .monospaced)).frame(minHeight: 150)
            Button(L("Save layout", "Сохранить раскладку")) {
                let values = draft.split(whereSeparator: \.isNewline).map { KeyboardLayout.tokens(String($0)) }
                guard (1...6).contains(values.count),
                      values.allSatisfy({ (1...18).contains($0.count) && $0.allSatisfy { $0.count <= 12 } }) else { invalid = true; return }
                rows = values
            }
            Button(L("Restore default", "Восстановить"), role: .destructive) {
                rows = nil
                populate()
            }
        }
        .navigationTitle(layout.space)
        .onAppear { populate() }
        .alert(L("Enter 1–6 rows of 1–18 keys.", "Введите 1–6 рядов из 1–18 клавиш."), isPresented: $invalid) { Button("OK") {} }
    }

    private func populate() { draft = (rows ?? layout.rows).map { $0.joined(separator: " ") }.joined(separator: "\n") }
}

struct SettingsBackup: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var preferences: Preferences

    init(preferences: Preferences) {
        var value = preferences
        value.gifKey = ""
        value.hasPhoto = false
        value.hasFont = false
        self.preferences = value
    }

    init(configuration: ReadConfiguration) throws {
        preferences = try JSONDecoder().decode(Preferences.self, from: configuration.file.regularFileContents ?? Data())
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try JSONEncoder.ordered.encode(preferences))
    }
}

private extension JSONEncoder {
    static var ordered: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
