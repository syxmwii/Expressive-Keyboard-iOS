import Foundation

enum Composition {
    static func render(_ raw: String, kind: String) -> String {
        switch kind {
        case "hangul": return hangul(raw)
        case "telex": return telex(raw)
        case "kana": return kana(raw)
        case "ethiopic": return ethiopic(raw)
        case "myanmar": return myanmar(raw)
        default: return raw
        }
    }

    private static let initial = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    private static let middle = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    private static let final = Array("\u{0}ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")
    private static let vowels: [String: Character] = ["ㅗㅏ":"ㅘ", "ㅗㅐ":"ㅙ", "ㅗㅣ":"ㅚ", "ㅜㅓ":"ㅝ", "ㅜㅔ":"ㅞ", "ㅜㅣ":"ㅟ", "ㅡㅣ":"ㅢ"]
    private static let endings: [String: Character] = [
        "ㄱㅅ":"ㄳ", "ㄴㅈ":"ㄵ", "ㄴㅎ":"ㄶ", "ㄹㄱ":"ㄺ", "ㄹㅁ":"ㄻ", "ㄹㅂ":"ㄼ",
        "ㄹㅅ":"ㄽ", "ㄹㅌ":"ㄾ", "ㄹㅍ":"ㄿ", "ㄹㅎ":"ㅀ", "ㅂㅅ":"ㅄ"
    ]

    static func hangul(_ raw: String) -> String {
        var output = ""
        var lead: Int?, vowel: Int?, tail = 0
        func flush() {
            if let lead, let vowel, let scalar = UnicodeScalar(0xAC00 + (lead * 21 + vowel) * 28 + tail) {
                output.unicodeScalars.append(scalar)
            } else if let lead {
                output.append(initial[lead])
            } else if let vowel {
                output.append(middle[vowel])
            }
            lead = nil
            vowel = nil
            tail = 0
        }
        for key in raw {
            if let nextVowel = middle.firstIndex(of: key) {
                if let currentVowel = vowel {
                    if tail != 0 {
                        var moved = final[tail]
                        if let pair = endings.first(where: { $0.value == moved })?.key {
                            tail = pair.first.flatMap { final.firstIndex(of: $0) } ?? 0
                            moved = pair.last ?? moved
                        } else {
                            tail = 0
                        }
                        flush()
                        lead = initial.firstIndex(of: moved)
                    } else if let combined = vowels["\(middle[currentVowel])\(key)"], let index = middle.firstIndex(of: combined) {
                        vowel = index
                        continue
                    } else {
                        flush()
                    }
                }
                vowel = nextVowel
            } else if let nextLead = initial.firstIndex(of: key) {
                if lead != nil, vowel != nil, tail == 0, let index = final.firstIndex(of: key) {
                    tail = index
                } else if tail != 0, let combined = endings["\(final[tail])\(key)"], let index = final.firstIndex(of: combined) {
                    tail = index
                } else {
                    flush()
                    lead = nextLead
                }
            } else {
                flush()
                output.append(key)
            }
        }
        flush()
        return output
    }

    private static let tones = [
        "aăâeêioôơuưy", "áắấéếíóốớúứý", "àằầèềìòồờùừỳ", "ảẳẩẻểỉỏổởủửỷ", "ãẵẫẽễĩõỗỡũữỹ", "ạặậẹệịọộợụựỵ"
    ].map(Array.init)
    private static let toneKeys = Array("sfrxj")
    private static let vowelEdits: [String: Character] = ["aa":"â", "aw":"ă", "ee":"ê", "oo":"ô", "ow":"ơ", "uw":"ư"]
    private static let toned = Dictionary(uniqueKeysWithValues: tones.enumerated().flatMap { tone, row in
        row.enumerated().map { ($0.element, (vowel: $0.offset, tone: tone)) }
    })

    static func telex(_ raw: String) -> String {
        var word: [Character] = []
        func lower(_ c: Character) -> Character { c.lowercased().first ?? c }
        func formatted(_ c: Character, like original: Character) -> Character {
            original.isUppercase ? (c.uppercased().first ?? c) : c
        }
        for key in raw {
            let k = lower(key)
            if let last = word.last, let position = toned[lower(last)],
               let next = vowelEdits["\(tones[0][position.vowel])\(k)"],
               let nextIndex = tones[0].firstIndex(of: next) {
                word[word.count - 1] = formatted(tones[position.tone][nextIndex], like: last)
                continue
            }
            if k == "d", let last = word.last, lower(last) == "d" {
                word[word.count - 1] = formatted("đ", like: last)
                continue
            }
            if let target = k == "z" ? 0 : toneKeys.firstIndex(of: k).map({ $0 + 1 }) {
                var indices = word.indices.filter { toned[lower(word[$0])] != nil }
                let spelling = String(word).lowercased()
                if indices.count > 1 && (spelling.hasPrefix("qu") || spelling.hasPrefix("gi")) { indices.removeAll { $0 < 2 } }
                if let first = indices.first, let last = indices.last {
                    let preferred = indices.last { "ăâêôơư".contains(lower(word[$0])) }
                    let index = preferred ?? (last < word.count - 1 ? last : (indices.count >= 3 ? indices[1] : first))
                    if let current = toned[lower(word[index])] {
                        let repeatTone = target != 0 && current.tone == target
                        word[index] = formatted(tones[repeatTone ? 0 : target][current.vowel], like: word[index])
                        if repeatTone { word.append(key) }
                        continue
                    }
                }
            }
            if k == "w", word.last.flatMap({ toned[lower($0)] }) == nil {
                word.append(formatted("ư", like: key))
            } else {
                word.append(key)
            }
        }
        return String(word)
    }

    private static let kanaTable: [String: String] = {
        let vowels = Array("aiueo")
        var table: [String: String] = [:]
        let rows = ["":"あいうえお", "k":"かきくけこ", "g":"がぎぐげご", "s":"さしすせそ", "z":"ざじずぜぞ", "t":"たちつてと",
                    "d":"だぢづでど", "n":"なにぬねの", "h":"はひふへほ", "b":"ばびぶべぼ", "p":"ぱぴぷぺぽ", "m":"まみむめも", "r":"らりるれろ"]
        for (prefix, row) in rows {
            for (vowel, kana) in zip(vowels, row) { table[prefix + String(vowel)] = String(kana) }
        }
        let yoon = ["ky":"き", "gy":"ぎ", "sh":"し", "sy":"し", "j":"じ", "jy":"じ", "zy":"じ", "ch":"ち",
                    "cy":"ち", "ty":"ち", "dy":"ぢ", "ny":"に", "hy":"ひ", "by":"び", "py":"ぴ", "my":"み", "ry":"り"]
        for (prefix, kana) in yoon {
            for (vowel, small) in ["a":"ゃ", "u":"ゅ", "o":"ょ"] { table[prefix + vowel] = kana + small }
        }
        let aliases = ["ya":"や", "yu":"ゆ", "yo":"よ", "wa":"わ", "wo":"を", "shi":"し", "chi":"ち", "tsu":"つ", "fu":"ふ", "ji":"じ",
                       "n":"ん", "nn":"ん", "n'":"ん", "-":"ー", "xa":"ぁ", "xi":"ぃ", "xu":"ぅ", "xe":"ぇ", "xo":"ぉ", "xtsu":"っ",
                       "xya":"ゃ", "xyu":"ゅ", "xyo":"ょ", "she":"しぇ", "je":"じぇ", "che":"ちぇ", "fa":"ふぁ", "fi":"ふぃ", "fe":"ふぇ", "fo":"ふぉ",
                       "ti":"ち", "si":"し", "tu":"つ", "hu":"ふ", "zi":"じ", "di":"ぢ", "du":"づ", "wi":"うぃ", "we":"うぇ",
                       "va":"ゔぁ", "vi":"ゔぃ", "vu":"ゔ", "ve":"ゔぇ", "vo":"ゔぉ"]
        table.merge(aliases) { _, new in new }
        return table
    }()

    static func kana(_ raw: String) -> String {
        var remaining = raw.lowercased()[...]
        var result = ""
        while let first = remaining.first {
            if remaining.dropFirst().first == first, first.isASCII, first.isLetter, !"aiueon".contains(first) {
                result += "っ"
                remaining = remaining.dropFirst()
            } else if let length = (1...min(4, remaining.count)).reversed().first(where: { kanaTable[String(remaining.prefix($0))] != nil }),
                      let kana = kanaTable[String(remaining.prefix(length))] {
                result += kana
                remaining = remaining.dropFirst(length)
            } else {
                result.append(first)
                remaining = remaining.dropFirst()
            }
        }
        return result
    }

    private static let consonants: [Character: UnicodeScalar] = Dictionary(uniqueKeysWithValues:
        zip("hlHmrsxqQbvtcXnNkKwzZydDjgGT CPSfFpBVL MRYJW".filter { $0 != " " },
            "ሀለሐመረሰሸቀቐበቨተቸኀነኘከኸወዘዠየደዸጀገጘጠጨጰጸፈፈፐበቨለመረየጀወ".unicodeScalars))
    private static let orders: [Character: UInt32] = ["e":0, "u":1, "U":1, "i":2, "I":2, "a":3, "A":3, "E":4, "o":6, "O":6]
    private static let standalone: [Character: UnicodeScalar] = Dictionary(uniqueKeysWithValues: zip("aAuUiIeEoO", "አኣኡኡኢእእኤኦኦ".unicodeScalars))
    private static let digraphs: [String: UInt32] = ["sh":0x1238, "ch":0x1278, "ny":0x1298, "zh":0x12E0, "Sh":0x1238, "Ch":0x1328]

    static func ethiopic(_ raw: String) -> String {
        var result = String.UnicodeScalarView()
        var previous: Character?, live = false
        for letter in raw {
            if let consonant = consonants[letter] {
                let digraph = previous.flatMap { digraphs[String($0) + letter.lowercased()] }
                if live, let digraph, let replacement = UnicodeScalar(digraph + 5) {
                    result.removeLast()
                    result.append(replacement)
                } else if let scalar = UnicodeScalar(consonant.value + 5) {
                    result.append(scalar)
                }
                live = true
            } else if let order = orders[letter] {
                if live, previous == "w", letter == "a" || letter == "A", result.count > 1,
                   let preceding = result.dropLast().last, preceding.value % 8 == 5,
                   let replacement = UnicodeScalar(preceding.value + 2), replacement.properties.generalCategory != .unassigned {
                    result.removeLast()
                    result.removeLast()
                    result.append(replacement)
                    live = false
                } else if live, let last = result.last, last.value % 8 == 5,
                          let replacement = UnicodeScalar(last.value - 5 + order), replacement.properties.generalCategory != .unassigned {
                    result.removeLast()
                    result.append(replacement)
                    live = order == 2
                } else if live, letter == "e", previous == "i", let last = result.last, let replacement = UnicodeScalar(last.value + 2) {
                    result.removeLast()
                    result.append(replacement)
                    live = false
                } else {
                    if let scalar = standalone[letter] { result.append(scalar) }
                    live = false
                }
            } else {
                result.append(contentsOf: letter.unicodeScalars)
                live = false
            }
            previous = letter
        }
        return String(result)
    }

    static func myanmar(_ raw: String) -> String {
        var result = ""
        var prefixes: [UnicodeScalar] = []
        for scalar in raw.unicodeScalars {
            switch scalar {
            case "ေ", "ြ":
                if !prefixes.contains(scalar) { prefixes.append(scalar) }
            default:
                if (0x1000...0x1021).contains(scalar.value) || scalar == "ဿ" {
                    result.unicodeScalars.append(scalar)
                    result.unicodeScalars.append(contentsOf: prefixes.sorted { $0.value > $1.value })
                } else {
                    result.unicodeScalars.append(contentsOf: prefixes)
                    result.unicodeScalars.append(scalar)
                }
                prefixes.removeAll()
            }
        }
        result.unicodeScalars.append(contentsOf: prefixes)
        return result
    }
}
