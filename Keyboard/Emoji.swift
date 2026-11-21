import UIKit
import ImageIO

struct EmojiEntry {
    let index: Int
    let glyph: String
    let variants: [String]
    let keywords: String
}

final class EmojiCatalog {
    static let shared = EmojiCatalog()
    let groups: [(String, [EmojiEntry])]
    private var indices: [String: Int] = [:]
    private var availability: [String: [UInt8]] = [:]
    private let sheets = NSCache<NSString, CGImage>()

    private init() {
        var groups: [(String, [EmojiEntry])] = []
        var index = 0
        let data = Resources.data("emoji/emoji.txt") ?? Data()
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            if parts.count == 1, line.first == "#" {
                groups.append((String(line.dropFirst()), []))
            } else if parts.count >= 5, !groups.isEmpty {
                let glyph = String(parts[0])
                let variants = parts[1].split(separator: " ").map(String.init)
                groups[groups.count - 1].1.append(EmojiEntry(index: index, glyph: glyph, variants: variants,
                                                               keywords: parts[2...].joined(separator: " ").lowercased()))
                for item in [glyph] + variants { indices[item] = index; index += 1 }
            }
        }
        self.groups = groups
        sheets.countLimit = 2
    }

    func search(_ query: String) -> [EmojiEntry] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace)
        return Array(groups.lazy.flatMap(\.1).filter { entry in terms.allSatisfy { entry.keywords.contains($0) } }.prefix(96))
    }

    func image(_ glyph: String, style: String) -> UIImage? {
        guard ["twemoji", "noto", "blob", "openmoji"].contains(style), let index = indices[glyph] else { return nil }
        if availability[style] == nil, let data = Resources.data("emoji/\(style)/index.txt") {
            availability[style] = Array(data)
        }
        guard let bits = availability[style], bits.indices.contains(index), bits[index] == 49 else { return nil }
        let key = "\(style)/\(index / 256)" as NSString
        var image = sheets.object(forKey: key)
        if image == nil, let url = Resources.url("emoji/\(key).webp"),
           let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            if let image { sheets.setObject(image, forKey: key) }
        }
        let local = index % 256
        let rect = CGRect(x: (local % 16) * 64, y: (local / 16) * 64, width: 64, height: 64)
        return image?.cropping(to: rect).map { UIImage(cgImage: $0, scale: 2, orientation: .up) }
    }
}
