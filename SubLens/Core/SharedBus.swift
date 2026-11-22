import Foundation
import CoreGraphics

/// 主 App 与屏幕广播扩展共用的配置。
/// 默认不带 App Group（免费开发者账号不支持），此时自动走回环 TCP。
enum SharedConfig {
    static let appGroupID = "group.com.sublens.livetranslate"
    static let appBundleID = "com.sublens.livetranslate"
    static let extensionBundleID = "com.sublens.livetranslate.ScreenBroadcast"
    static let linesFileName = "screen-lines.json"
    static let regionFileName = "screen-region.json"

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroupID) ?? .standard }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var linesFileURL: URL? {
        containerURL?.appendingPathComponent(linesFileName)
    }

    static var regionFileURL: URL? {
        containerURL?.appendingPathComponent(regionFileName)
    }
}

/// 扩展写入主 App 的一条识别结果
struct RemoteScreenLine: Codable, Identifiable, Hashable {
    var id: String
    var text: String
    var ts: Double
}

/// 屏幕识别区域：归一化坐标（0~1），原点在左上角，跟用户看到的屏幕方向一致。
struct ScreenRegion: Codable, Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    static let full = ScreenRegion(x: 0, y: 0, w: 1, h: 1)

    var isFull: Bool { x <= 0.02 && y <= 0.02 && w >= 0.96 && h >= 0.96 }

    var area: Double { w * h }

    /// 夹到画面内，并保证一个最小可操作尺寸
    func clamped() -> ScreenRegion {
        let width = min(max(w, 0.10), 1.0)
        let height = min(max(h, 0.06), 1.0)
        let left = min(max(x, 0.0), 1.0 - width)
        let top = min(max(y, 0.0), 1.0 - height)
        return ScreenRegion(x: left, y: top, w: width, h: height)
    }

    /// Vision 的 regionOfInterest 用左下角原点，这里做一次翻转
    var visionRect: CGRect {
        let c = clamped()
        return CGRect(x: c.x, y: 1.0 - c.y - c.h, width: c.w, height: c.h)
    }

    var summary: String {
        if isFull { return "整屏" }
        let top = Int((y * 100).rounded())
        let bottom = Int(((y + h) * 100).rounded())
        let left = Int((x * 100).rounded())
        let right = Int(((x + w) * 100).rounded())
        return "竖向 \(top)%–\(bottom)% · 横向 \(left)%–\(right)%"
    }
}

/// 屏幕/媒体识别配置：区域、自动语种、是否做文字识别、是否转录媒体音频
struct ScreenConfigPayload: Codable, Equatable {
    var region: ScreenRegion
    var autoDetect: Bool
    var ocrEnabled: Bool
    var audioEnabled: Bool

    init(region: ScreenRegion, autoDetect: Bool, ocrEnabled: Bool = true, audioEnabled: Bool = false) {
        self.region = region
        self.autoDetect = autoDetect
        self.ocrEnabled = ocrEnabled
        self.audioEnabled = audioEnabled
    }

    enum CodingKeys: String, CodingKey {
        case region, autoDetect, ocrEnabled, audioEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        region = ((try container.decodeIfPresent(ScreenRegion.self, forKey: .region)) ?? .full).clamped()
        autoDetect = try container.decodeIfPresent(Bool.self, forKey: .autoDetect) ?? false
        ocrEnabled = try container.decodeIfPresent(Bool.self, forKey: .ocrEnabled) ?? true
        audioEnabled = try container.decodeIfPresent(Bool.self, forKey: .audioEnabled) ?? false
    }
}

/// 识别配置在共享容器里的落盘（有 App Group 时扩展读文件拿配置）
enum SharedScreenConfig {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func write(_ payload: ScreenConfigPayload) {
        guard let url = SharedConfig.regionFileURL else { return }
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read() -> ScreenConfigPayload? {
        guard let url = SharedConfig.regionFileURL,
              let data = try? Data(contentsOf: url),
              let payload = try? decoder.decode(ScreenConfigPayload.self, from: data) else {
            return nil
        }
        return payload
    }
}

/// 跨进程的文本总线：
/// - 有 App Group → 写共享 json 文件，主 App 定时读取；
/// - 没有 App Group（免费账号）→ 走 127.0.0.1 回环 TCP。
enum SharedScreenBus {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static var usesSharedContainer: Bool {
        SharedConfig.linesFileURL != nil
    }

    static func write(_ lines: [RemoteScreenLine]) {
        guard let url = SharedConfig.linesFileURL else {
            BridgeClient.shared.send(.makeLines(lines))
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
