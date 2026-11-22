import ReplayKit
import Foundation
import CoreMedia

/// 录屏扩展入口。用户在控制中心选择「译幕 · 屏幕字幕」后，系统会把屏幕帧送到这里。
class SampleHandler: RPBroadcastSampleHandler {

    private let worker = ScreenOCRWorker()
    private var running = false

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        running = true
        SharedScreenBus.write([])
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
        case .audioApp, .audioMic:
            // 系统音频这里拿不到可用的转写通道（扩展内存与权限都不足），
            // 音频同传请用主 App 的「同传」模式，通过麦克风采集外放声音。
            break
        default:
            break
        }
    }
}
