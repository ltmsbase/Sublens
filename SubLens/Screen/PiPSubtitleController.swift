import Foundation
import AVFoundation
import AVKit
import UIKit
import CoreMedia
import CoreVideo

/// 浮窗字幕（画中画）。
///
/// iOS 不允许第三方 App 直接在别的 App 上盖一层界面，能"合法"浮在最上层的只有画中画。
/// 这里把字幕渲染成视频帧喂给 AVSampleBufferDisplayLayer，再让它在画中画里显示，
/// 于是可以一边刷别的 App，一边在角落看到实时译文。
final class PiPSubtitleController: NSObject, ObservableObject {

    @Published private(set) var isActive = false
    @Published private(set) var isSupported = AVPictureInPictureController.isPictureInPictureSupported()
    @Published private(set) var lastError: String?

    private var pipController: AVPictureInPictureController?
    private let displayLayer = AVSampleBufferDisplayLayer()
    private var hostView: UIView?
    private var heartbeat: Timer?
    private var currentOriginal = ""
    private var currentTranslation = ""
    /// 渲染结果缓存：文本没变时复用上一帧，避免每秒重新排版一次 1280×720
    private var renderedImage: CGImage?
    private var renderedKey: String = ""

    // MARK: - 视图

    func makeHostView() -> UIView {
        if let hostView { return hostView }
        let view = SubtitleHostView(frame: CGRect(x: 0, y: 0, width: 340, height: 191))
        view.backgroundColor = .black
        view.clipsToBounds = true
        view.displayLayer = displayLayer
        displayLayer.frame = view.bounds
        displayLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(displayLayer)
        hostView = view
        return view
    }

    func prepare() {
        guard isSupported else { return }
        guard pipController == nil else { return }
        guard hostView != nil else { return }

        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        pipController = controller

        // 先铺一帧，否则画中画拿不到尺寸
        renderFrame()
        startHeartbeat()
    }

    func startIfPossible() {
        prepare()
        guard let pipController else { return }
        guard pipController.isPictureInPicturePossible else { return }
        pipController.startPictureInPicture()
    }

    func start() {
        startIfPossible()
    }

    func stop() {
        heartbeat?.invalidate()
        heartbeat = nil
        pipController?.stopPictureInPicture()
    }

    // MARK: - 字幕更新

    func update(original: String, translation: String) {
        currentOriginal = original
        currentTranslation = translation
        if pipController == nil {
            // 预览视图还没建好时只记住文本，等 prepare 后再统一渲染
            return
        }
        renderFrame()
        startHeartbeat()
    }

    private func startHeartbeat() {
        heartbeat?.invalidate()
        // 画中画的视频层需要持续有新帧，否则会被系统回收
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.renderFrame()
        }
    }

    private func renderFrame() {
        let key = currentOriginal + "\u{1F}" + currentTranslation
        if key != renderedKey || renderedImage == nil {
            renderedImage = TextFrameRenderer.makeImage(original: currentOriginal, translation: currentTranslation)
            renderedKey = key
        }
        guard let image = renderedImage,
              let pixelBuffer = TextFrameRenderer.makePixelBuffer(from: image) else { return }
        guard let sampleBuffer = TextFrameRenderer.makeSampleBuffer(from: pixelBuffer) else { return }
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        displayLayer.enqueue(sampleBuffer)
    }
}

// MARK: - 画中画代理

extension PiPSubtitleController: AVPictureInPictureControllerDelegate {

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async {
            self.isActive = true
            self.startHeartbeat()
        }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async {
            self.isActive = false
            self.heartbeat?.invalidate()
            self.heartbeat = nil
        }
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        DispatchQueue.main.async {
            self.isActive = false
            self.lastError = "浮窗字幕启动失败：\(error.localizedDescription)"
        }
    }
}

extension PiPSubtitleController: AVPictureInPictureSampleBufferPlaybackDelegate {

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    setPlaying playing: Bool) {
        // 字幕不是真正的播放器，忽略播放/暂停
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        // 用户调整了浮窗大小，无需处理
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    skipByInterval skipInterval: CMTime,
                                    completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        false
    }
}

// MARK: - 字幕帧渲染

final class SubtitleHostView: UIView {
    weak var displayLayer: AVSampleBufferDisplayLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer?.frame = bounds
        CATransaction.commit()
    }
}

enum TextFrameRenderer {

    static let canvas = CGSize(width: 1280, height: 720)

    static func makeImage(original: String, translation: String) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)

        let image = renderer.image { context in
            let cg = context.cgContext
            cg.clear(CGRect(origin: .zero, size: canvas))

            let bandHeight: CGFloat = 230
            let band = CGRect(x: 0, y: canvas.height - bandHeight, width: canvas.width, height: bandHeight)
            cg.setFillColor(UIColor.black.withAlphaComponent(0.78).cgColor)
            cg.fill(band)

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail

            let primary = translation.isEmpty ? original : translation
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 44, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            (primary as NSString).draw(in: band.insetBy(dx: 48, dy: 34), withAttributes: attributes)

            if !translation.isEmpty && !original.isEmpty {
                let secondary = original as NSString
                let secondaryAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 26, weight: .regular),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.65),
                    .paragraphStyle: paragraph
                ]
                let secondaryRect = CGRect(x: 48, y: canvas.height - bandHeight + 12,
                                           width: canvas.width - 96, height: 32)
                secondary.draw(in: secondaryRect, withAttributes: secondaryAttributes)
            }
        }
        return image.cgImage
    }

    static func makePixelBuffer(original: String, translation: String) -> CVPixelBuffer? {
        guard let image = makeImage(original: original, translation: translation) else { return nil }
        return makePixelBuffer(from: image)
    }

    static func makePixelBuffer(from cgImage: CGImage) -> CVPixelBuffer? {
        let width = Int(canvas.width)
        let height = Int(canvas.height)
        let attributes: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                        kCVPixelFormatType_32BGRA,
                                        attributes as CFDictionary, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let context = CGContext(data: base,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                        | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    static func makeSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                     imageBuffer: pixelBuffer,
                                                     formatDescriptionOut: &formatDescription)
        guard let format = formatDescription else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                 imageBuffer: pixelBuffer,
                                                 formatDescription: format,
                                                 sampleTiming: &timing,
                                                 sampleBufferOut: &sampleBuffer)
        return sampleBuffer
    }
}
