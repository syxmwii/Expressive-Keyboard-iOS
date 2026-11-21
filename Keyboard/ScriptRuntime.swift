import Foundation

final class ScriptRuntime {
    let plugin: Plugin
    private var handle: OpaquePointer?
    private var response: UnsafeMutablePointer<CChar>?
    private var host: (String, [Any]) -> Any?
    private(set) var error: String?

    init?(plugin: Plugin, host: @escaping (String, [Any]) -> Any?) {
        guard let script = plugin.script, let data = Resources.data("bootstrap.js"),
              let bootstrap = String(data: data, encoding: .utf8) else { return nil }
        self.plugin = plugin
        self.host = host
        handle = ERCreate({ pointer, method, arguments in
            guard let pointer, let method, let arguments else { return nil }
            let runtime = Unmanaged<ScriptRuntime>.fromOpaque(pointer).takeUnretainedValue()
            let input = Data(String(cString: arguments).utf8)
            let values = (try? JSONSerialization.jsonObject(with: input)) as? [Any] ?? []
            let answer = runtime.host(String(cString: method), values) ?? NSNull()
            let output = (try? JSONSerialization.data(withJSONObject: answer, options: [.fragmentsAllowed])) ?? Data("null".utf8)
            free(runtime.response)
            runtime.response = strdup(String(decoding: output, as: UTF8.self))
            return UnsafePointer(runtime.response)
        }, Unmanaged.passUnretained(self).toOpaque())
        guard handle != nil else { return nil }
        _ = evaluate(bootstrap + "\n" + script, timeout: 120)
    }

    deinit {
        ERFree(handle)
        free(response)
    }

    private func evaluate(_ script: String, timeout: Int32) -> String? {
        guard let handle, error == nil else { return nil }
        var failed: Int32 = 0
        guard let result = EREval(handle, script, timeout, &failed) else { return nil }
        defer { ERFreeString(result) }
        let text = String(cString: result)
        if failed != 0 { error = text; return nil }
        return text
    }

    func event(_ name: String, _ value: Any = NSNull()) -> Any? {
        guard let encoded = try? JSONSerialization.data(withJSONObject: [name, value]),
              let text = evaluate("__expressiveJSON(__expressiveDispatch(...\(String(decoding: encoded, as: UTF8.self))))", timeout: 24)
        else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
    }

    var catalog: [String: [[String: Any]]] { event("$catalog") as? [String: [[String: Any]]] ?? [:] }
}
