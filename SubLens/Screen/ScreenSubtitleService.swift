import Foundation
import Combine

/// 主 App 侧的屏幕字幕监听：接收广播扩展发来的识别结果，做去重，把新增的行回调出去。
/// 数据来源有两种：App Group 共享文件（付费账号）或回环 TCP（免费账号）。
final class ScreenSubtitleService: ObservableObject {

    @Published var isListening = false
    @Published var statusText = ""
    @Published var region: ScreenRegion = .full
    @Published private(set) var regionApplied = false
    /// 原文语言设成「自动」时，让扩展也自动判断文字语种
    private(set) var autoDetect = false
    /// 是否做屏幕文字识别
    @Published private(set) var ocrEnabled = true
    /// 是否转录正在播放的媒体声音
    @Published private(set) var audioEnabled = false

    /// 收到媒体音频片段（16kHz 单声道 Int16）
    var onAudio: ((Data) -> Void)?
    @Published var snapshotCount = 0
    @Published var transportText = ""

    var onNewLine: ((String) -> Void)?

    private var timer: Timer?
    private var server: BridgeServer?
    private var latest: [RemoteScreenLine] = []
    /// 归一化文本 → 上次上屏时间，用于吃掉 OCR 抖动造成的重复
    private var seen: [String: Date] = [:]
    /// 最近上屏过的行，用于判断「同一句只是被切成了两段」
    private var emitted: [(key: String, at: Date)] = []

    private static let regionKey = "screenRegion"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.regionKey),
           let saved = try? JSONDecoder().decode(ScreenRegion.self, from: data) {
            region = saved.clamped()
        } else {
            region = .full
        }
    }

    /// 用户在选区面板确认后调用：落盘 + 下发扩展
    func applyRegion(_ new: ScreenRegion) {
        let clamped = new.clamped()
        region = clamped
        if let data = try? JSONEncoder().encode(clamped) {
            UserDefaults.standard.set(data, forKey: Self.regionKey)
        }
        pushConfig()
        regionApplied = true
        // 换区域等于重来一遍，清掉历史快照，避免拿旧结果比对
        seen = [:]
        emitted = []
        latest = []
    }

    func applyAutoDetect(_ flag: Bool) {
        autoDetect = flag
        pushConfig()
    }

    /// 屏幕文字 / 媒体声音两种模式的开关
    func setModes(ocr: Bool, audio: Bool) {
        ocrEnabled = ocr
        audioEnabled = audio
        pushConfig()
    }

    private var payload: ScreenConfigPayload {
        ScreenConfigPayload(region: region, autoDetect: autoDetect,
                            ocrEnabled: ocrEnabled, audioEnabled: audioEnabled)
    }

    private func pushConfig() {
        SharedScreenConfig.write(payload)
        server?.sendConfig(payload)
    }

    func start() {
        guard !isListening else { return }
        isListening = true
        statusText = "正在等待屏幕内容…"
        seen = [:]
        emitted = []
        latest = []

        if SharedScreenBus.usesSharedContainer {
            transportText = "App Group 共享容器"
        } else {
            transportText = "回环 TCP 通道"
        }

        // 回环服务端总要起：媒体音频只能走 TCP，即使文字走共享文件也一样
        let server = BridgeServer()
        server.onLines = { [weak self] lines in
            guard !SharedScreenBus.usesSharedContainer else { return }
            DispatchQueue.main.async {
                self?.latest = lines
                self?.poll()
            }
        }
        server.onAudio = { [weak self] pcm in
            self?.onAudio?(pcm)
        }
        server.start()
        self.server = server
        // 一启动就把当前配置推过去，扩展连上后立刻按配置工作
        pushConfig()

        timer?.invalidate()
        if SharedScreenBus.usesSharedContainer {
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.poll()
            }
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        server?.stop()
        server = nil
        isListening = false
        statusText = ""
        snapshotCount = 0
        seen = [:]
        emitted = []
        latest = []
    }

    private func poll() {
        if SharedScreenBus.usesSharedContainer {
            latest = SharedScreenBus.read()
        }

        let rawTexts = latest.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }

        // 同一帧里 Vision 偶尔把同一行吐两遍（框重叠），先按归一化文本压一次
        var uniqueTexts: [String] = []
        var keys: [String] = []
        for text in rawTexts {
            let key = Self.normalizedKey(text)
            guard !key.isEmpty, !keys.contains(key) else { continue }
            keys.append(key)
            uniqueTexts.append(text)
        }
        snapshotCount = uniqueTexts.count

        if uniqueTexts.isEmpty {
            if timer != nil {
                statusText = "还没有收到画面文字，确认录屏已选到「译幕」"
            }
            return
        }
        statusText = region.isFull
            ? "整屏识别 · 已识别 \(uniqueTexts.count) 行"
            : "区域识别 · 已识别 \(uniqueTexts.count) 行"

        let now = Date()
        var fresh: [String] = []

        for (index, text) in uniqueTexts.enumerated() {
            let key = keys[index]
            // 3 秒内见过同一行 → 不重复上屏（闪烁、抖动、来回滚动都算同一行）
            if let last = seen[key], now.timeIntervalSince(last) < 3 {
                seen[key] = now
                continue
            }
            // 同一句被切成两段/被拼成一段，4 秒内也算重复
            if isNearDuplicate(key, at: now) {
                seen[key] = now
                continue
            }
            seen[key] = now
            fresh.append(text)
            emitted.append((key, now))
        }

        // 只保留最近 4 秒的上屏记录，以及 2 分钟内见过的文本，避免无限增长
        emitted = emitted.filter { now.timeIntervalSince($0.at) < 4 }
        if seen.count > 200 {
            seen = seen.filter { now.timeIntervalSince($0.value) < 120 }
        }

        guard !fresh.isEmpty else { return }
        for text in fresh.prefix(4) {
            onNewLine?(text)
        }
    }

    /// 同一句话因 OCR 切分不同而「看起来是新行」：字符几乎一样、或一句包含另一句
    private func isNearDuplicate(_ key: String, at now: Date) -> Bool {
        for item in emitted where now.timeIntervalSince(item.at) < 4 {
            if item.key == key { return true }
            let shorter = min(item.key.count, key.count)
            let longer = max(item.key.count, key.count)
            guard shorter >= 4 else { continue }
            guard Double(longer) <= Double(shorter) * 1.6 + 2 else { continue }
            if item.key.contains(key) || key.contains(item.key) { return true }
        }
        return false
    }

    /// 去空白、去首尾标点、压小写，用来判断两帧内容是否其实是同一段文字
    static func normalizedKey(_ text: String) -> String {
        var core = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let edge = CharacterSet(charactersIn: " \t\n。．.,，；;:：!！?？、·—…\"'“”‘’()（）[]【】<>《》「」『』-")
        core = core.trimmingCharacters(in: edge)
        core = core.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return core.lowercased()
    }
}
