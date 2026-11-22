import Foundation
import CoreMedia
import CoreVideo
import Vision

/// 运行在录屏扩展里的文字识别器。
///
/// 两条提速思路：
/// 1. 直接把 CVPixelBuffer 交给 Vision，省掉「CIImage → CGImage」那一次全画面重编码；
/// 2. 用户选定的识别区域交给 `regionOfInterest`，Vision 只处理这一小块，面积越小越快。
///
/// 扩展的内存配额很小（约 50MB），所以这里只做识别、不做翻译，结果写进共享通道就结束。
final class ScreenOCRWorker {

    private let queue = DispatchQueue(label: "com.sublens.screen-ocr", qos: .userInitiated)
    private let lock = NSLock()

    private var lastRun: TimeInterval = 0
    private var lastJoined = ""

    private var _region: ScreenRegion = .full
    private var autoDetect = false
    private var ocrEnabled = true
    private var regionSnapshot: ScreenRegion {
        lock.lock()
        defer { lock.unlock() }
        return _region
    }

    private func setRegion(_ region: ScreenRegion) {
        lock.lock()
        _region = region
        lock.unlock()
    }

    /// 主 App 下发了新的识别配置
    func apply(region: ScreenRegion, autoDetect: Bool, ocrEnabled: Bool) {
        let clamped = region.clamped()
        queue.async { [weak self] in
            guard let self else { return }
            let changed = clamped != self.regionSnapshot
                || autoDetect != self.autoDetect
                || ocrEnabled != self.ocrEnabled
            guard changed else { return }
            self.setRegion(clamped)
            self.autoDetect = autoDetect
            self.ocrEnabled = ocrEnabled
            self.lastJoined = ""       // 配置变了，允许下一次识别结果立刻上屏
        }
    }

    func handle(_ sampleBuffer: CMSampleBuffer) {
        guard ocrEnabled else { return }
        let now = Date().timeIntervalSince1970
        // 选区越小，单次识别越便宜，可以跑得更勤
        let interval: TimeInterval = regionSnapshot.isFull ? 0.45 : 0.28
        guard now - lastRun >= interval else { return }
        lastRun = now
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        queue.async { [weak self] in
            self?.recognize(pixelBuffer)
        }
    }

    private func recognize(_ pixelBuffer: CVPixelBuffer) {
        guard CVPixelBufferGetWidth(pixelBuffer) > 0 else { return }

        // 有 App Group 时配置走共享文件（文件极小，每次读一下最省心）
        if let payload = SharedScreenConfig.read() {
            if payload.region != regionSnapshot || payload.autoDetect != autoDetect || payload.ocrEnabled != ocrEnabled {
                setRegion(payload.region)
                autoDetect = payload.autoDetect
                ocrEnabled = payload.ocrEnabled
                lastJoined = ""
            }
        }

        let region = regionSnapshot
        let lines = performOCR(on: pixelBuffer, region: region, autoDetect: autoDetect)

        guard !lines.isEmpty else {
            // 画面上没字了，把上一次的结果清掉，避免主 App 一直显示过期字幕
            if !lastJoined.isEmpty {
                lastJoined = ""
                SharedScreenBus.write([])
            }
            return
        }

        // 按归一化文本比较：只差标点、空格、大小写的重新识别不算变化，避免同一行被反复重发
        let joined = lines.map { Self.normalizedKey($0) }.joined(separator: "\n")
        guard joined != lastJoined else { return }
        lastJoined = joined

        let timestamp = Date().timeIntervalSince1970
        let payload: [RemoteScreenLine] = lines.enumerated().map { item in
            let identifier = String(format: "%.0f-%d", timestamp * 1000, item.offset)
            return RemoteScreenLine(id: identifier, text: item.element, ts: timestamp)
        }
        SharedScreenBus.write(payload)
    }

    /// 去空白、去首尾标点、压小写，用来判断两帧内容是否其实是同一段文字
    static func normalizedKey(_ text: String) -> String {
        var core = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let edge = CharacterSet(charactersIn: " \t\n。．.,，；;:：!！?？、·—…\"'“”‘’()（）[]【】<>《》「」『』-")
        core = core.trimmingCharacters(in: edge)
        core = core.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return core.lowercased()
    }

    private func performOCR(on pixelBuffer: CVPixelBuffer, region: ScreenRegion, autoDetect: Bool) -> [String] {
        if autoDetect, let results = run(on: pixelBuffer, region: region, languages: nil), !results.isEmpty {
            return results
        }
        let preferred = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
        if let results = run(on: pixelBuffer, region: region, languages: preferred), !results.isEmpty {
            return results
        }
        // 某些设备上个别语种不可用，退回系统默认语言列表
        if let results = run(on: pixelBuffer, region: region, languages: nil), !results.isEmpty {
            return results
        }
        return []
    }

    private func run(on pixelBuffer: CVPixelBuffer, region: ScreenRegion, languages: [String]?) -> [String]? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        // 只识别用户框出来的那一块
        request.regionOfInterest = region.visionRect
        if let languages {
            request.recognitionLanguages = languages
        } else {
            // 自动判断文字语种
            request.automaticallyDetectsLanguage = true
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        var ordered: [(y: CGFloat, text: String)] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 2 else { continue }
            ordered.append((observation.boundingBox.midY, text))
        }

        // Vision 的 y 轴朝上，按屏幕从上到下的顺序排一下，字幕顺序才正常
        ordered.sort { $0.y > $1.y }
        return Array(ordered.map { $0.text }.prefix(8))
    }
}
