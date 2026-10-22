import Foundation

// Installed `codex --version` and the newest release on GitHub. Shown only: Codexy never runs the update.

public enum CodexVersion {
    /// "codex-cli 0.163.0" or "rust-v0.163.0" -> "0.163.0".
    public static func parse(_ s: String) -> String? {
        s.split(whereSeparator: { !($0.isNumber || $0 == ".") }).map(String.init).first { $0.contains(".") }
    }

    /// True when `a` is a higher dotted number than `b` ("0.170.0" > "0.163.2").
    public static func isNewer(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }

    public static func installed() -> String? {
        guard let exe = CodexCLI.path, let d = CodexCLI.run(exe, ["--version"], timeout: 5) else { return nil }
        return parse(String(decoding: d, as: UTF8.self))
    }

    public static func latest() async -> String? {
        guard let url = URL(string: "https://api.github.com/repos/openai/codex/releases/latest"),
              let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              j["prerelease"] as? Bool != true, let tag = j["tag_name"] as? String else { return nil }
        return parse(tag)
    }
}
