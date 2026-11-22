import Foundation

/// 主 App 与屏幕广播扩展共用的配置。
/// 默认不带 App Group（免费开发者账号不支持），此时自动走回环 TCP。
enum SharedConfig {
    static let appGroupID = "group.com.sublens.livetranslate"
    static let appBundleID = "com.sublens.livetranslate"
    static let extensionBundleID = "com.sublens.livetranslate.ScreenBroadcast"
    static let linesFileName = "screen-lines.json"

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroupID) ?? .standard }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var linesFileURL: URL? {
        containerURL?.appendingPathComponent(linesFileName)
    }
}

/// 扩展写入主 App 的一条识别结果
struct RemoteScreenLine: Codable, Identifiable, Hashable {
    var id: String
    var text: String
    var ts: Double
}

/// 跨进程的文本总线：
/// - 有 App Group → 写共享 json 文件，主 App 定时读取；
/// - 没有 App Group（免费账号）→ 走 127.0.0.1 回环 TCP。
/// 两种方式都只传"当前画面上所有文本行"的整份快照，主 App 自己比对新增行。
enum SharedScreenBus {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static var usesSharedContainer: Bool {
        SharedConfig.linesFileURL != nil
    }

    static func write(_ lines: [RemoteScreenLine]) {
        guard let url = SharedConfig.linesFileURL else {
            BridgeClient.shared.send(lines)
            return
        }
        guard let data = try? encoder.encode(lines) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read() -> [RemoteScreenLine] {
        guard let url = SharedConfig.linesFileURL,
              let data = try? Data(contentsOf: url),
              let lines = try? decoder.decode([RemoteScreenLine].self, from: data) else {
            return []
        }
        return lines
    }
}
