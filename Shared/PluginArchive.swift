import Foundation

enum PluginArchive {
    static func load(_ archive: Data) throws -> Plugin {
        guard (22...8_000_000).contains(archive.count) else { throw Plugin.ImportError.archive }
        let bytes = [UInt8](archive)
        func number(_ offset: Int, _ length: Int = 2) -> Int {
            guard offset >= 0, offset + length <= bytes.count else { return -1 }
            return (0..<length).reduce(0) { $0 | (Int(bytes[offset + $1]) << ($1 * 8)) }
        }
        guard let end = ((max(0, bytes.count - 65_557))...(bytes.count - 22)).reversed().first(where: {
            number($0, 4) == 0x06054b50 && $0 + 22 + number($0 + 20) == bytes.count
        }), number(end + 4) == 0, number(end + 6) == 0 else { throw Plugin.ImportError.archive }
        var offset = number(end + 16, 4)
        guard offset >= 0, offset < end, number(end + 10) <= 256 else { throw Plugin.ImportError.archive }
        var files: [String: Data] = [:]
        for _ in 0..<number(end + 10) {
            guard offset + 46 <= end, number(offset, 4) == 0x02014b50 else { throw Plugin.ImportError.archive }
            let nameSize = number(offset + 28)
            let next = offset + 46 + nameSize + number(offset + 30) + number(offset + 32)
            guard next <= end else { throw Plugin.ImportError.archive }
            let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameSize)], as: UTF8.self)
            defer { offset = next }
            guard ["plugin.json", "main.js"].contains(name) else { continue }
            let method = number(offset + 10)
            let compressed = number(offset + 20, 4), size = number(offset + 24, 4)
            let local = number(offset + 42, 4)
            guard files[name] == nil, number(offset + 8) & 1 == 0, (1...2_000_000).contains(size),
                  compressed > 0, local >= 0, local + 30 <= end, number(local, 4) == 0x04034b50
            else { throw Plugin.ImportError.archive }
            let start = local + 30 + number(local + 26) + number(local + 28)
            guard start + compressed <= end else { throw Plugin.ImportError.archive }
            if method == 0 && compressed == size {
                files[name] = Data(bytes[start..<(start + size)])
            } else if method == 8 {
                var result = Data(count: size)
                let ok = result.withUnsafeMutableBytes { output in
                    bytes.withUnsafeBufferPointer { input in
                        ERInflate(input.baseAddress?.advanced(by: start), compressed,
                                  output.bindMemory(to: UInt8.self).baseAddress, size)
                    }
                }
                guard ok == 1 else { throw Plugin.ImportError.archive }
                files[name] = result
            } else {
                throw Plugin.ImportError.archive
            }
        }
        guard let manifest = files["plugin.json"] else { throw Plugin.ImportError.archive }
        let script = files["main.js"].map { String(decoding: $0, as: UTF8.self) }
        return try Plugin.load(manifest, type: "json", main: script)
    }
}
