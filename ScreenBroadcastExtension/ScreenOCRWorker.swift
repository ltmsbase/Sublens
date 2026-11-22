import Foundation
import CoreMedia
import CoreVideo
import CoreImage
import Vision

/// 运行在录屏扩展里的文字识别器。
/// 扩展的内存配额很小（约 50MB），所以这里把画面缩到 720px 宽、每秒最多识别 1~2 次，
/// 只把文字结果写进 App Group，不做翻译（翻译在主 App 里做）。
final class ScreenOCRWorker {

    private let queue = DispatchQueue(label: "com.sublens.screen-ocr", qos: .userInitiated)
    private let context = CIContext()
    private var lastRun: TimeInterval = 0
    private var lastJoined = ""
    private let interval: TimeInterval = 0.7

    func handle(_ sampleBuffer: CMSampleBuffer) {
        let now = Date().timeIntervalSince1970
        guard now - lastRun >= interval else { return }
        lastRun = now
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        queue.async { [weak self] in
            self?.recognize(pixelBuffer)
        }
    }

    private func recognize(_ pixelBuffer: CVPixelBuffer) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        guard width > 0 else { return }

        let targetWidth: CGFloat = 720
        let scale = min(1.0, targetWidth / CGFloat(width))
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return }

        let lines = performOCR(on: cgImage)
        guard !lines.isEmpty else { return }

        let joined = lines.prefix(10).joined(separator: "\n")
        guard joined != lastJoined else { return }
        lastJoined = joined

        let timestamp = Date().timeIntervalSince1970
        let payload: [RemoteScreenLine] = lines.prefix(10).enumerated().map { item in
            let identifier = String(format: "%.0f-%d", timestamp * 1000, item.offset)
            return RemoteScreenLine(id: identifier, text: item.element, ts: timestamp)
        }
        SharedScreenBus.write(Array(payload))
    }

    private func performOCR(on image: CGImage) -> [String] {
        let preferred = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
        if let results = runRequest(on: image, languages: preferred), !results.isEmpty {
            return results
        }
        // 某些设备上个别语种不可用，退回系统默认语言列表
        if let results = runRequest(on: image, languages: nil), !results.isEmpty {
            return results
        }
        return []
    }

    private func runRequest(on image: CGImage, languages: [String]?) -> [String]? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        if let languages {
            request.recognitionLanguages = languages
        }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        var lines: [String] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.count >= 2 {
                lines.append(text)
            }
        }
        return lines
    }
}
