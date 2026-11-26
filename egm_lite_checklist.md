# EGM-Lite Checklist — исправления и визуальный паритет

**Задача:** закрыть подтверждённые дефекты, подтянуть внешний вид клавиатуры и приложения к скинам upstream, начать паритет поведения.
**Review baseline:** коммит `898e7bd`. До начала правок в дереве уже были `?? .gigatool/` (служебное) и `?? egm_lite_alternatives.md` (артефакт критики). Их в диффе задачи не смешивать.

## Проверено до реализации

- QuickJS-мост собран и прогнан (`gcc`, `Runtime/*.c` + `Tests/QuickJSChecks.c`): тест пройден, дедлайн `while(true){}` срабатывает.
- `ExpressiveKeyboard.xcodeproj/project.pbxproj` совпадает с `Scripts/project.py` (повторная генерация дала побайтово тот же файл).
- Данные: 205 раскладок с уникальными id; 42 согласных ↔ 42 эфиопских скаляра; 3781 запись эмодзи = длина `index.txt` во всех четырёх стилях; все 12 JSON-манифестов плагинов валидны.
- Скины содержат поля, которые iOS-тема не читает: роли `keys.*` (`*`, `func`, `space`, `enter`, `mode`, `shift`), `dark`, `keyboard.pattern/orbs/trail/corner/font`, `pressedBackground`, `border`, `shadow`, `fontScale`. Это и есть основной разрыв «не похоже».
- Swift/UIKit на этой машине не собрать: всё, что ниже помечено как UI-поведение, проверяется на Mac/устройстве.

---

## A. Дефекты (этот цикл)

- [x] **A1. Касания для плагинов.** Убрать `needsText: true` у события `touch`, иначе `studio.js` без права `read_text` не получает точки. Добавить событие `cancel` для `.cancelled/.failed` и не отправлять `up` вместо отмены. [KeyboardController.swift:822-866](Keyboard/KeyboardController.swift:822), [ScriptPanels.swift:19](Keyboard/ScriptPanels.swift:19), [bootstrap.js:51](KeyboardData/bootstrap.js:51)
- [x] **A2. Ошибка плагина не должна убивать runtime навсегда.** Разделить ошибку инициализации и ошибку обработчика: `event` возвращает `nil`, пишет `lastEventError` для показа в списке плагинов, но не блокирует следующие вызовы. [ScriptRuntime.swift:35-50](Keyboard/ScriptRuntime.swift:35)
- [x] **A3. Заглушка `kb.tone`.** `studio.js:36` зовёт `kb.tone`, которого нет в API, — `TypeError` на первом тапе по пианино. Добавить no-op рядом с `speak/particles`. [bootstrap.js:31-68](KeyboardData/bootstrap.js:31)
- [x] **A4. Автозаглавные для `.asciiCapable`.** Сейчас работает только для `.default/.twitter`, хотя поле `asciiCapable` — обычный текст. Расширить список текстовых типов и вынести его в одно место. [KeyboardController.swift:531-540](Keyboard/KeyboardController.swift:531)
- [x] **A5. Статус не гаснет для длинных сообщений.** Сравнивать с уже обрезанным значением, иначе таймер сброса не срабатывает. [Panels.swift:486-493](Keyboard/Panels.swift:486)
- [x] **A6. Терпимое декодирование `Preferences`.** Синтезированный `Codable` падает на отсутствующем ключе, `load()` молча отдаёт дефолты — добавление поля стирает настройки. Реализовать `init(from:)` через `decodeIfPresent`, покрыть round-trip и «старый файл без нового поля» в `Tests/CoreChecks.swift`. [Settings.swift:90-139](Shared/Settings.swift:90), [Settings.swift:246-251](Shared/Settings.swift:246)
- [x] **A7. Диктовка не доходит до клавиатуры.** `dictation.json` пишется только при наличии app group, которого нет, — панель «Диктовка» тупиковая. Дать панели чтение расшифровки из буфера (с проверкой полного доступа) и убрать текст, обещающий файл. [Panels.swift:471-484](Keyboard/Panels.swift:471), [VoiceView.swift:18-31](App/VoiceView.swift:18)
- [x] **A8. Кадровый таймер в инкогнито.** Инвалидировать при переходе в приватный режим и перезапускать при выходе, иначе 30 Гц тикают впустую. [KeyboardController.swift:216](Keyboard/KeyboardController.swift:216), [KeyboardController.swift:128-133](Keyboard/KeyboardController.swift:128)
- [x] **A9. Комбинируемые знаки в словах.** — снято: `Character.isLetter` для графемы с базовым символом уже истинно, дефект чтением API не подтверждён; нужна проверка на устройстве, кода не меняли. `prefix`/`learn` считают словом только `isLetter`, поэтому индийские раскладки не дают подсказок и не обучаются. Добавить `nonBaseCharacters` по образцу условия в `type(_:)`. [KeyboardController.swift:186-188](Keyboard/KeyboardController.swift:186), [:791-793](Keyboard/KeyboardController.swift:791)
- [x] **A10. `home`/`end` в UTF-16.** `context.count` — графемы, а смещение курсора — UTF-16; на эмодзи уезжает. Считать `utf16.count`. [Panels.swift:333-334](Keyboard/Panels.swift:333)
- [x] **A11. Мёртвые entitlements.** `Group.entitlements` генерируются, capability объявлена, `CODE_SIGN_ENTITLEMENTS` нигде не задан — app group не работает никогда. Решение: удалить файлы и capability, оставить перенос через буфер (так и написано в README); альтернатива — подключать entitlements только при непустом `EXPRESSIVE_APP_GROUP`. [project.py:74-81](Scripts/project.py:74), [project.py:162-163](Scripts/project.py:162)
- [x] **A12. ZIP с пустым файлом.** Требование `compressed > 0` отвергает корректный пустой `main.js`; разрешить `size == 0` при `method == 0`. [PluginArchive.swift:28](Shared/PluginArchive.swift:28)
- [x] **A13. Имя appex в `Resources.url`.** Захардкожено `ExpressiveExtension.appex`; брать единственный `.appex` из `builtInPlugInsURL`, чтобы переименование цели не ломало ресурсы. [Settings.swift:33](Shared/Settings.swift:33)

## V1. Визуальная близость клавиатуры (этот цикл)

- [x] **V1.0. Кэш скина.** Файловые скины кэшируются по `design`, скины плагинов — по `id|hash(definition)`; повторный `redraw` больше не читает диск. [Theme.swift:133-148](Shared/Theme.swift:133)
- [x] **V1.1. Тёмные варианты скинов.** Скины задают `dark.colors/keys/panel/popup`, тема их игнорирует — в тёмной теме classic/nothing/liquid_glass выглядят светлыми. Сливать `dark` поверх базы. [Theme.swift:22-29](Keyboard/Theme.swift:22)
- [x] **V1.2. Роли клавиш.** Ввести роль (`normal/func/accent/space/enter/mode/shift`) в `key()` и разрешать стиль из `keys[role]` → `keys["*"]`: фон, текст, радиус, `pressedRadius`, `border/borderWidth`, `shadow/shadowY/shadowColor`, `fontScale`, `fontWeight`. Сейчас стилей три и `space/enter/mode` неразличимы. [KeyboardController.swift:239-262](Keyboard/KeyboardController.swift:239), [Panels.swift:20-57](Keyboard/Panels.swift:20)
- [x] **V1.3. Нажатие как в скине.** `ExpressiveButton` реагирует только альфой; добавить `pressedBackground/pressedText` и `press` (`scale/bounce/sink`) через transform. [Theme.swift:76-107](Keyboard/Theme.swift:76)
- [x] **V1.4. Фон клавиатуры.** Паттерны `dots/pixels`, орбы и `trail` из скина подключены. `keyboard.corner` не переносим: на iOS клавиатура во всю ширину, скругление обрезало бы клавиши — зафиксировано как отклонение.
- [x] **V1.5. Типографика.** `textShadow`, `fontScale`, `fontWeight`, `keyboard.font == "pixel"` → моноширинный фолбэк. [KeyboardController.swift:250-256](Keyboard/KeyboardController.swift:250)
- [x] **V1.6. Превью в приложении.** Сейчас мок нарисован белым по фиолетовому независимо от темы; красить реальной палитрой скина и показывать имя текущего скина. [ExpressiveApp.swift:155-176](App/ExpressiveApp.swift:155)
- [ ] **V1.7. Проверка на устройстве.** Сравнить Light/Dark для всех девяти дизайнов с эталоном скина; зафиксировать расхождения списком.

## P. Поведение (только инвентаризация в этом цикле)

- [x] **P0. Матрица паритета.** Свести возможности upstream 11.2.9 (README, `PLUGINS.md`, `Languages.kt`, настройки) с портом; на каждый пункт вердикт «есть / адаптируется / невозможно» и цена. Результат — `parity_matrix.md`. Без неё переносить поведение нельзя: получится угадывание.
- [ ] **P1. API плагинов 4.** По `PLUGINS-Android.md` и `bootstrap.js` зафиксировать пробелы (`tone`, `speak`, `particles`, `keyboardEffect`, датчики) и решение по каждому: рабочая реализация, честный no-op или `kb.supports(...) == false`. [bootstrap.js:31-69](KeyboardData/bootstrap.js:31)
- [ ] **P2. Экран первого запуска.** У upstream он есть; в порте только подсказки в настройках. Внести в матрицу как отдельный пункт с макетом. [ExpressiveApp.swift:44-78](App/ExpressiveApp.swift:44)

## R. Правки после дифф-ревью (этот цикл)

- [x] **R1.** `try?`-флэттенинг в `Preferences.init(from:)` ломал сборку — заменить на `(try? …) ?? fallback`. [Settings.swift:138-140](Shared/Settings.swift:138)
- [x] **R2.** Ошибки обработчиков плагинов теперь видны в списке плагинов (`lastEventError`). [Panels.swift:288-301](Keyboard/Panels.swift:288)
- [x] **R3.** Орбы вставляются с нарастающим индексом, z-порядок совпадает с `theme.orbs`. [KeyboardController.swift:252-264](Keyboard/KeyboardController.swift:252)
- [x] **R4.** `pressedRadius` клампится тем же `min(22, …)`, что и `idleRadius`, для expressive-форм. [KeyboardController.swift:319-330](Keyboard/KeyboardController.swift:319)
- [x] **R5.** Кадровый таймер перезапускается при поздней подписке на `frame`. [ScriptPanels.swift:36-41](Keyboard/ScriptPanels.swift:36)
- [x] **R6.** Анимация нажатия пропускается при `pressMode == "none"`. [Theme.swift:90-100](Keyboard/Theme.swift:90)
- [x] **R7.** Тест старого файла настроек проверяет `layouts`, `plugins`, `disabledPlugins` и неверные типы. [CoreChecks.swift:37-44](Tests/CoreChecks.swift:37)
- [x] **R8.** `keyboard.font == "pixel"` даёт моноширинный шрифт (доделка V1.5). [KeyboardController.swift:305-312](Keyboard/KeyboardController.swift:305)

## Принятые CONTEST (дифф-ревью)

- `home`/`end` остаются переходом к началу/концу документа — смена трактовки на «начало строки» меняет контракт `pressKey`.
- `.shift` без собственного `keys.shift` наследует цвет функции — это данные скина; активный регистр через акцент намеренный.
- Радиусы скинов не масштабируются: dp и pt одинаково density-independent.
- Словарные `background` клавиш (minecraft) — материал этапа V2, регресса нет.
- `OverlayView` (`radius/stroke/fill`) этим диффом не менялся и вне объёма A/V1.
- `pressedColor` не перетирает фон в `layoutSubviews`; transform сбрасывается в `else`.
- Гейт `read_text` для `key`/`glide` законен: они отдают текст; `touch` уже без гейта.
- Статический кэш не гоняет между процессами app/extension; вызовы с главного потока.
- `sharedContainer` оставлен как ручной путь; README говорит, что App Groups не требуются.
- Таймер статуса сбрасывает только совпадающий обрезанный текст — одинаковое сообщение и должно исчезать.
- Пустой deflate-поток отвергается `ERInflate`/`PluginArchive`, падения нет.
- Swift не собирался в этой среде: выводы по компиляции сделаны чтением типов, сборка на Mac остаётся отложенной проверкой.

## Отложено (не в этом цикле, до матрицы и проверки на устройстве)

- Материалы `glass/bevel/glow/grain`, шейдерные эффекты, видео-фоны, датчики — отдельный этап V2/P.
- Массовый перенос разделов настроек и «много форм» вместо `shapes 0…2`.
- Ассеты и скриншоты: в upstream README скриншоты закомментированы, эталона для попиксельного сравнения нет.

## Отложенные проверки

- [ ] Сборка на Mac: `xcodebuild -project ExpressiveKeyboard.xcodeproj -scheme ExpressiveKeyboard -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`.
- [ ] Устройство: набор/сдвиг/капс в Notes и Safari, свайп, автозамена, перенос настроек через буфер, диктовка, копирование GIF, рисование в «Студии», пианино без падения плагина.
- [ ] Повторить прогон QuickJS после правок `bootstrap.js`/`ScriptRuntime`; `CoreChecks` — на macOS, нужен ZIP-фикстур (сейчас передаётся аргументом, генератора в репозитории нет).
- [ ] `cut` в плагинах: `deleteBackward()` при выделении удаляет выделение — проверить на устройстве, а не «чинить» вслепую.

## Риски и допущения

- `[⚠️ UNVERIFIED]` Лимит памяти расширения клавиатуры и доступность CoreMotion/аудио в appex — проверить на устройстве до этапа V2/P.
- `[⏳ ACK]` «Очень похоже» оценивается по данным скинов, а не по скриншотам upstream: эталона изображений в репозитории нет.
- Визуальные правки V1 меняют вид всех девяти дизайнов — нужен один проход глазами на устройстве, иначе регресс не заметить.

---
### 🔍 Assumption Lifecycle Legend:
- `[⚠️ UNVERIFIED]`: Siloed external contract. Requires indisputable evidence to verify.
- `[⏳ ACK]`: Acknowledged assumption. Factual evidence unavailable; risk accepted and opaque-box empirical test strictly scheduled.
