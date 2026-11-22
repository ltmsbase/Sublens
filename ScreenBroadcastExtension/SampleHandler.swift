import ReplayKit
import Foundation
import CoreMedia

/// 录屏扩展入口。用户在控制中心选择「译幕 · 屏幕字幕」后，系统会把屏幕帧送到这里。
class SampleHandler: RPBroadcastSampleHandler {

    private let worker = ScreenOCRWorker()
    private let audioWorker = AudioRelayWorker()
    private var running = false

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        running = true
        SharedScreenBus.write([])

        // 主 App 会通过回环连接下发用户选定的识别区域
        BridgeClient.shared.onConfig = { [weak self] config in
            guard let self else { return }
            self.worker.apply(region: config.region,
                              autoDetect: config.autoDetect,
                              ocrEnabled: config.ocrEnabled)
            self.audioWorker.enabled = config.audioEnabled
            if !config.audioEnabled { self.audioWorker.reset() }
        }
        // 有 App Group 时，配置是写在共享文件里的，直接读一次
        if let saved = SharedScreenConfig.read() {
            worker.apply(region: saved.region, autoDetect: saved.autoDetect, ocrEnabled: saved.ocrEnabled)
            audioWorker.enabled = saved.audioEnabled
        }
    }

    override func broadcastPaused() {
        // 用户暂停录屏，不需要特殊处理
    }

    override func broadcastResumed() {
        // 恢复录屏
    }

    override func broadcastFinished() {
        running = false
        SharedScreenBus.write([])
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard running else { return }
        switch sampleBufferType {
        case .video:
            worker.handle(sampleBuffer)
        case .audioApp:
            // 正在播放的媒体声音：这里只做重采样和转发，转写在主 App 里跑
            audioWorker.handle(sampleBuffer)
        case .audioMic:
            // 麦克风音频不需要，麦克风同传在主 App 里直接采集
            break
        default:
            break
        }
    }
}
