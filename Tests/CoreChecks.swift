import Foundation

@main
struct CoreChecks {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let resources = root.appendingPathComponent("KeyboardData")
        let layouts = try JSONDecoder().decode([KeyboardLayout].self, from: Data(contentsOf: resources.appendingPathComponent("layouts.json")))
        precondition(layouts.count == 205 && Set(layouts.map(\.id)).count == 205)
        precondition(layouts.allSatisfy { !$0.rows.isEmpty && $0.rows.allSatisfy { !$0.isEmpty } })
        precondition(Composition.hangul("ㅎㅏㄴㄱㅡㄹ") == "한글")
        precondition(Composition.hangul("ㄱㅗㅏ") == "과")
        precondition(Composition.hangul("ㅎㅏㄴㅏ") == "하나")
        precondition(Composition.telex("tieengs") == "tiếng")
        precondition(Composition.kana("nihongo") == "にほんご")
        precondition(Composition.kana("gakkou") == "がっこう")
        precondition(Composition.ethiopic("selam") == "ሰላም")
        precondition(Composition.myanmar("ေန") == "နေ")
        let database = Lexicon(url: resources.appendingPathComponent("lexicon.sqlite3"))
        precondition(database.correction("пожалуста", language: "ru") == "пожалуйста")
        precondition(database.complete("hell", language: "en").contains("hello"))
        precondition(database.complete("ni", language: "zh_cn").contains("你"))
        precondition(database.complete("あい", language: "ja").contains("会い"))
        precondition(database.glide(["h", "e", "l", "o"], language: "en").contains("hello"))
        precondition(!database.follow(["я", "не"], language: "ru").isEmpty)
        let script = try Data(contentsOf: resources.appendingPathComponent("plugins/calculator.js"))
        let plugin = try Plugin.load(script, type: "js")
        precondition(plugin.id == "builtin.calculator" && plugin.script != nil)
        precondition(!Plugin.expand("Before {date:yyyy-MM-dd} after").contains("{date"))
        let zipped = try PluginArchive.load(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
        precondition(zipped.id == "example.archive" && zipped.script == "const ready = true;")
        var settings = Preferences()
        settings.width = 0
        settings.languages = ["en", "en"]
        settings.normalize()
        precondition(settings.width == 0.72 && settings.languages == ["en"])
        let legacy = try JSONDecoder().decode(Preferences.self, from: Data(#"{"design":"classic","height":40,"languages":["ru"]}"#.utf8))
        precondition(legacy.design == .classic && legacy.height == 40 && legacy.languages == ["ru"])
        precondition(legacy.numberRow == false && legacy.emojiStyle == "system")
        precondition(legacy.layouts.isEmpty && legacy.plugins.isEmpty && legacy.disabledPlugins.isEmpty)
        let custom = try JSONDecoder().decode(Preferences.self, from: Data(#"{"layouts":{"en":[["q","w"]]},"disabledPlugins":["builtin.notes"]}"#.utf8))
        precondition(custom.layouts["en"] == [["q", "w"]] && custom.disabledPlugins == ["builtin.notes"])
        let wrongType = try JSONDecoder().decode(Preferences.self, from: Data(#"{"height":"40","shapes":"x"}"#.utf8))
        precondition(wrongType.height == 46.0 && wrongType.shapes == 1)
        let unknown = try JSONDecoder().decode(Preferences.self, from: Data(#"{"design":"future"}"#.utf8))
        precondition(unknown.design == .expressive)
        let project = root.appendingPathComponent("ExpressiveKeyboard.xcodeproj/project.pbxproj")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: project), options: [], format: nil) as? [String: Any]
        let objects = plist?["objects"] as? [String: [String: Any]] ?? [:]
        precondition(objects.values.filter { $0["isa"] as? String == "PBXNativeTarget" }.count == 2)
        for item in objects.values where item["sourceTree"] as? String == "SOURCE_ROOT" {
            let path = item["path"] as? String ?? ""
            precondition(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
        }
        print("Passed 205 layouts, six input modes, lexicon, ZIP import, preferences, and the Xcode project structure.")
    }
}
