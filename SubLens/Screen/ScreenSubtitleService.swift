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
    private var previous: Set<String> = []

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
        previous = []
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
        previous = []
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
        previous = []
        latest = []
    }

    private func poll() {
        if SharedScreenBus.usesSharedContainer {
            latest = SharedScreenBus.read()
        }

        let texts = latest.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
        snapshotCount = texts.count

        if texts.isEmpty {
            if timer != nil {
                statusText = "还没有收到画面文字，确认录屏已选到「译幕」"
            }
            return
        }
        statusText = region.isFull
            ? "整屏识别 · 已识别 \(texts.count) 行"
            : "区域识别 · 已识别 \(texts.count) 行"

        var fresh: [String] = []
        for text in texts where !previous.contains(text) {
            fresh.append(text)
        }
        previous = Set(texts)
        guard !fresh.isEmpty else { return }

        for text in fresh.prefix(4) {
            onNewLine?(text)
        }
    }
}
