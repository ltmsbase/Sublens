import Foundation
import Combine

/// 主 App 侧的屏幕字幕监听：接收广播扩展发来的识别结果，做去重，把新增的行回调出去。
/// 数据来源有两种：App Group 共享文件（付费账号）或回环 TCP（免费账号）。
final class ScreenSubtitleService: ObservableObject {

    @Published var isListening = false
    @Published var statusText = ""
    @Published var snapshotCount = 0
    @Published var transportText = ""

    var onNewLine: ((String) -> Void)?

    private var timer: Timer?
    private var server: BridgeServer?
    private var latest: [RemoteScreenLine] = []
    private var previous: Set<String> = []

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
            let server = BridgeServer()
            server.onLines = { [weak self] lines in
                DispatchQueue.main.async {
                    self?.latest = lines
                    self?.poll()
                }
            }
            server.start()
            self.server = server
        }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            self?.poll()
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
        statusText = "已识别 \(texts.count) 行"

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
