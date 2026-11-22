import Foundation
import AVFoundation

/// 屏幕字幕模式下让 App 在后台保持运行。
///
/// 录屏扩展把识别结果发到主 App 的本地端口，所以主 App 必须活着才能收。
/// 做法是声明 `audio` 后台模式并播放一段静音音频——这是系统允许的合法后台执行方式，
/// 音频会话一旦激活，进程就不会被立刻挂起。
final class SilentAudioKeeper {

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?
    private var running = false
    private var configured = false

    func start() {
        guard !running else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            if !configured {
                engine.attach(player)
                guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2) else { return }
                engine.connect(player, to: engine.mainMixerNode, format: format)
                engine.mainMixerNode.outputVolume = 0

                let frames: AVAudioFrameCount = 4096
                guard let silent = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
                silent.frameLength = frames
                if let channels = silent.floatChannelData {
                    for index in 0..<Int(format.channelCount) {
                        memset(channels[index], 0, Int(frames) * MemoryLayout<Float>.size)
                    }
                }
                buffer = silent
                configured = true
            }

            try engine.start()
            if let buffer {
                player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            }
            player.play()
            running = true
        } catch {
            running = false
        }
    }

    /// 同传停止时会释放音频会话，屏幕保活需要把会话重新抢回来
    func reactivate() {
        guard running else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            if !engine.isRunning { try engine.start() }
            if !player.isPlaying { player.play() }
            engine.mainMixerNode.outputVolume = 0
        } catch {
            running = false
        }
    }

    func stop() {
        guard running else { return }
        player.stop()
        engine.stop()
        running = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
