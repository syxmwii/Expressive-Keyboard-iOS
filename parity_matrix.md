# Матрица паритета: upstream 11.2.9 → iOS-порт

> **BLUF:** Поведение повторяется примерно на две трети: ввод, языки, эмодзи, панели, скины и базовый API плагинов уже есть. Дорогие и рискованные расхождения — графика/видео/ИИ/датчики; дешёвые и полезные — пароли, шифрование ключей, бэкап выученных слов, онбординг и поиск по настройкам. Их и стоит брать следующими.

Источник: `kotlalipopus/Expressive-Keyboard`, коммит `28ee86b` (11.2.9). Вердикты `✅ есть`, `🟡 адаптируется`, `⛔ нет/нерентабельно`; цена `S` ≤ день, `M` ≤ неделя, `L` — больше.

## Ввод

| Возможность | Upstream | Порт | Вердикт | Цена |
|---|---|---|---|---|
| Подсказки, автозамена, свайп | `WordPredictor.kt`, `GlideTyping.kt` | `suggestions()`, `space()`, `trackGlide` | ✅ | — |
| Динамические зоны клавиш | `DynamicZones.kt` (вероятность следующей буквы сдвигает границы) | нет | 🟡 нужен словарь биграмм на устройстве | M |
| Подсказки в пароле отключены | `KeyboardSettings`/`KeyboardState` | нет проверки `isSecureTextEntry` — утечка подсказок | 🟡 | S |
| Отмена автозамены, backspace по слову | 11.2.2 | `composingUndo`, `deleteWord()` | ✅ | — |
| Свои звуки нажатия | `KeySounds.kt` (7 синтезированных стилей) | системный клик `playInputClick` | 🟡 генерация в extension под вопросом `[⚠️ UNVERIFIED]` | M |
| Клавиатура «Новое»/энергосбережение, масштаб в альбомной | `NewFeatures.kt` | фиксированный клампинг в `updateHeight()` | 🟡 | S |

## Языки и тексты

| Возможность | Upstream | Порт | Вердикт | Цена |
|---|---|---|---|---|
| 90+ раскладок | `Languages.kt` | 205 в `layouts.json` | ✅ | — |
| Pinyin, kanji, Indic, амхарский | `Cjk.kt`, `Ethiopic.kt`, `MyanmarInput.kt` | `Composition.swift`, `Lexicon` | ✅ | — |
| Язык интерфейса | RU/EN + `I18nEs.kt`, `I18nExtra.kt` | RU/EN через `L()` | 🟡 | S |
| Бэкап выученных слов | `LearnedBackup.kt` | `learned` живёт в UserDefaults, в бэкап не попадает | 🟡 | S |

## Оформление

| Возможность | Upstream | Порт | Вердикт | Цена |
|---|---|---|---|---|
| 9 дизайнов и скины | `Skins.kt`, `Theme.kt` | `Theme.swift` + скины, теперь с `dark`, ролями и нажатиями | ✅ | — |
| Стекло, фаска, свечение, узоры | `GlassMerge.kt`, `KeyView.kt` | фон-паттерны и тени есть; glass/bevel/glow нет | 🟡 | M |
| OpenGL-эффекты и шейдеры | `GlLayer.kt`, `PluginGl.kt`, `GlTextures.kt` | нет | ⛔ в extension жёсткий лимит памяти `[⚠️ UNVERIFIED]`; Metal-порт — отдельный проект | L |
| Видео-фон | `KeyboardVideo.kt` | нет | ⛔/🟡 память и энергия в appex `[⚠️ UNVERIFIED]` | L |
| Material You (цвета из обоев) | `DynamicZones`/`ThemeUi.kt` | палитра скина и акцент | ⛔ системного API на iOS нет | — |
| Свои шрифты и фото | `FontRepository.kt`, `UserPictures.kt` | есть | ✅ | — |

## Панели

| Возможность | Upstream | Порт | Вердикт | Цена |
|---|---|---|---|---|
| Эмодзи, GIF, буфер, перевод | `Panels.kt`, `Clipboard.kt`, `Emoji.kt` | `Panels.swift` | ✅ | — |
| Диктовка в клавиатуре | `VoiceActivity.kt` | запись в приложении, вставка из буфера; файл `dictation.json` — только при app group | 🟡 | S |
| Секретные вставки из буфера | 11.2.2 | нет | 🟡 | S |

## Плагины и моды

| Возможность | Upstream | Порт | Вердикт | Цена |
|---|---|---|---|---|
| JSON/JS/ZIP, панели, события, storage | `Plugins.kt`, `ScriptEngine.kt`, `PluginArchive.kt` | `Plugin.swift`, `bootstrap.js`, `ScriptPanels.swift` | ✅ | — |
| API 4: звук, TTS, частицы, GL, датчики, сеть | `PLUGINS.md`, `ModEffects.kt`, `PluginInputEvents.kt` | `tone` — заглушка, `speak` без реализации, `particles`/`keyboardEffect` — no-op | 🟡 честные no-op + `kb.supports` | M |
| Редактор конфигов мода | `ModConfigEditor.kt`, `ModScreen.kt` | `config` читается, UI нет | 🟡 | M |
| Индикатор доступа плагина | `PluginAccessIndicator.kt` | нет | 🟡 | S |
| Сетевые вызовы модов | `PluginGl.kt`, network | нет | 🟡 только при полном доступе | M |

## Настройки и приватность

| Возможность | Upstream | Порт | Вердикт | Цена |
|---|---|---|---|---|
| Онбординг первого запуска | `Onboarding.kt` | подсказки в списке | 🟡 | M |
| Поиск по настройкам | `SettingsSearch.kt` | нет | 🟡 | S |
| Бэкап настроек | `SettingsBackup.kt` | есть; `gifKey` вырезается и теряется при импорте | 🟡 | S |
| Инкогнито | `KeyboardSettings` | есть | ✅ | — |
| Шифрование API-ключей | `SecretBox.kt` (Keystore, AES-GCM) | `gifKey` в открытом `preferences.json` | 🟡 Keychain | S |
| Обновление приложения | `Updater.kt` | App Store | ⛔ | — |
| ИИ-исправление текста | `AiFix.kt`, `AiCustomUi.kt` (Anthropic, ML Kit) | нет | 🟡 сеть + ключ, только при полном доступе | L |

## Что нельзя повторить буквально

- Compose-анимации и `MaterialShapes` — на iOS переносятся только как приближение на UIKit/Core Animation.
- Material You и системные Android-субтипы (`Subtypes.kt`) — прямых аналогов нет.
- OpenGL-шейдеры, видео-фон и датчики в расширении клавиатуры требуют отдельного прототипа и проверки лимитов памяти на устройстве.

## Предлагаемый порядок после этого цикла

1. `S`: `isSecureTextEntry` в `canSuggest`, `gifKey` → Keychain, бэкап выученных слов, поиск по настройкам.
2. `M`: онбординг, редактор конфигов модов, честные `kb.supports` и no-op для API 4, динамические зоны.
3. `L`: материалы (glass/bevel/glow), затем прототип видео/эффектов с замером памяти.
