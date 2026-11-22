import Foundation
import CoreMedia
import AudioToolbox
import AVFoundation

/// 运行在录屏扩展里的「媒体声音转录管道」。
///
/// 录屏扩展能拿到 `RPSampleBufferType.audioApp`，也就是别的 App 正在播放的声音
/// （受 DRM 保护的画面/音乐除外，那部分系统直接给静音）。
/// 但扩展内存配额只有 ~50MB，跑不下语音识别，所以这里只做两件事：
///   1. 把 48kHz 立体声浮点混成单声道、重采样到 16kHz Int16；
///   2. 通过回环通道丢给主 App，由主 App 用 SFSpeechRecognizer 转写 + 翻译。
/// 一段音频只有几 KB，回环传输毫无压力。
final class AudioRelayWorker {

    /// 主 App 在「媒体声音」模式下才打开，避免没人要的时候白耗电
    var enabled = false

    private let queue = DispatchQueue(label: "com.sublens.audio-relay", qos: .utility)
    /// 跨缓冲区保留的重采样相位，保证重采样连续、不出现咔哒声
    private var fraction: Double = 0
    private var pending: [Int16] = []
    private var lastFlush = Date().timeIntervalSince1970

    private let targetRate: Double = 16000
    /// 每 200ms 发一批（3200 个采样点）
    private let chunkSize = 3200

    func reset() {
        queue.async { [weak self] in
            self?.pending.removeAll()
            self?.fraction = 0
        }
    }

    func handle(_ sampleBuffer: CMSampleBuffer) {
        guard enabled else { return }
        // 转换很轻（一帧 1024 个采样），直接在音频回调线程上做，避免缓冲区被回收
        convert(sampleBuffer)
    }

    private func convert(_ sampleBuffer: CMSampleBuffer) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return }
        let asbd = asbdPointer.pointee

        let rate = asbd.mSampleRate > 0 ? asbd.mSampleRate : 48000
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let channels = Int(asbd.mChannelsPerFrame)
        let frames = Int(CMSampleBufferGetNumSamples(sampleBuffer))
        guard channels > 0, frames > 0 else { return }

        // 取 AudioBufferList（可能多声道两个 buffer，所以按声道数多分配一点）
        let listSize = MemoryLayout<AudioBufferList>.size
            + MemoryLayout<AudioBuffer>.size * max(0, channels - 1)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: listSize, alignment: 16)
        defer { raw.deallocate() }

        var blockBuffer: CMBlockBuffer?
        var needed = 0
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &needed,
            bufferListOut: raw.assumingMemoryBound(to: AudioBufferList.self),
            bufferListSize: listSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))

        // 先混成单声道 Float
        var mono = [Float](repeating: 0, count: frames)
        if isNonInterleaved {
            var used = 0
            for channel in 0..<min(channels, buffers.count) {
                guard let data = buffers[channel].mData else { continue }
                used += 1
                if isFloat {
                    let samples = data.bindMemory(to: Float32.self, capacity: frames)
                    for index in 0..<frames { mono[index] += samples[index] }
                } else {
                    let samples = data.bindMemory(to: Int16.self, capacity: frames)
                    for index in 0..<frames { mono[index] += Float(samples[index]) / 32768 }
                }
            }
            if used > 1 {
                for index in 0..<frames { mono[index] /= Float(used) }
            }
        } else {
            guard let data = buffers.first?.mData else { return }
            if isFloat {
                let samples = data.bindMemory(to: Float32.self, capacity: frames * channels)
                for index in 0..<frames {
                    var sum: Float = 0
                    for channel in 0..<channels { sum += samples[index * channels + channel] }
                    mono[index] = sum / Float(channels)
                }
            } else {
                let samples = data.bindMemory(to: Int16.self, capacity: frames * channels)
                for index in 0..<frames {
                    var sum: Float = 0
                    for channel in 0..<channels {
                        sum += Float(samples[index * channels + channel]) / 32768
                    }
                    mono[index] = sum / Float(channels)
                }
            }
        }

        // 线性重采样到 16kHz，相位跨缓冲区延续
        let ratio = rate / targetRate
        guard ratio > 0 else { return }
        var position = fraction
        while position < Double(frames) {
            let index = Int(position)
            let next = min(index + 1, frames - 1)
            let weight = Float(position - Double(index))
            let value = mono[index] * (1 - weight) + mono[next] * weight
            let clamped = max(-1, min(1, value))
            pending.append(Int16(clamped * 32767))
            position += ratio
        }
        fraction = position - Double(frames)

        let now = Date().timeIntervalSince1970
        if pending.count >= chunkSize || (now - lastFlush > 0.5 && !pending.isEmpty) {
            flush(now: now)
        }
    }

    private func flush(now: TimeInterval) {
        guard !pending.isEmpty else { return }
        var data = Data(count: pending.count * 2)
        data.withUnsafeMutableBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }
            for (index, sample) in pending.enumerated() {
                base[index] = sample
            }
        }
        pending.removeAll(keepingCapacity: true)
        lastFlush = now
        BridgeClient.shared.sendAudio(data)
    }
}
