import Foundation
import UIKit
import Vision
import ImageIO

enum OCRError: LocalizedError {
    case noImage
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noImage: return "无法读取这张图片"
        case .failed(let message): return message
        }
    }
}

/// 图片文字识别。使用 Vision 的 VNRecognizeTextRequest，中文识别效果明显好于旧版 CIDetector。
struct ImageOCRService {

    func recognize(in image: UIImage, languages: [String], autoDetect: Bool = false) async throws -> [RecognizedBlock] {
        guard let cgImage = image.cgImage else { throw OCRError.noImage }
        let orientation = CGImagePropertyOrientation(uiOrientation: image.imageOrientation)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                if autoDetect {
                    // 交给 Vision 自己判断文字是哪种语言
                    request.automaticallyDetectsLanguage = true
                } else {
                    request.recognitionLanguages = languages
                }

                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: OCRError.failed(error.localizedDescription))
                    return
                }

                let observations = request.results ?? []
                var blocks: [RecognizedBlock] = []
                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard text.count >= 1 else { continue }
                    let box = observation.boundingBox
                    // Vision 的坐标原点在左下角，这里翻成左上角并归一化
                    let rect = CGRect(x: box.minX,
                                      y: 1.0 - box.maxY,
                                      width: box.width,
                                      height: box.height)
                    blocks.append(RecognizedBlock(text: text, rect: rect))
                }
                continuation.resume(returning: blocks)
            }
        }
    }
}

extension CGImagePropertyOrientation {
    init(uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        default: self = .up
        }
    }
}
