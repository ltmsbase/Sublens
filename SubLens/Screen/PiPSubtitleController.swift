import Foundation
import AVFoundation
import AVKit
import UIKit
import CoreMedia
import CoreVideo

/// 画中画的两条字幕通道
enum PiPLane {
    case screen   // 画面文字（OCR）
    case media    // 媒体声音（转写）
}

/// 画中画里的一行字幕
struct PiPRow: Identifiable, Equatable {
    var id: UUID
    var original: String
    var translation: String
}

/// 浮窗字幕（画中画）。
///
/// iOS 不允许第三方 App 直接在别的 App 上盖一层界面，能"合法"浮在最上层的只有画中画。
/// 这里把字幕渲染成视频帧喂给 AVSampleBufferDisplayLayer，再让它在画中画里显示，
/// 于是可以一边刷别的 App，一边在角落看到实时译文。
///
/// 多行滚动：保留最近 3 行，新的一行从底部滑入，旧行整体上移，形成连续滚动而不是整块替换。
final class PiPSubtitleController: NSObject, ObservableObject {

    @Published private(set) var isActive = false
    @Published private(set) var isSupported = AVPictureInPictureController.isPictureInPictureSupported()
    @Published private(set) var lastError: String?

    private var pipController: AVPictureInPictureController?
    private let displayLayer = AVSampleBufferDisplayLayer()
    private var hostView: UIView?
    private var heartbeat: Timer?
    /// 画面文字（OCR）通道
    private var screenRows: [PiPRow] = []
    /// 媒体声音（转写）通道
    private var mediaRows: [PiPRow] = []
    /// 渲染结果缓存：文本没变时复用上一帧，避免每秒重新排版一次 1280×720
    private var renderedImage: CGImage?
    private var renderedKey: String = ""

    /// 每条通道最多留两行，两条通道都开的时候画中画也不会挤成一坨
    private let maxRowsPerLane = 2

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

    /// 新来一行：画面上滚进来。lane 决定它进哪一栏
    func push(original: String, lane: PiPLane, translation: String = "") {
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let row = PiPRow(id: UUID(), original: trimmed, translation: translation)
        switch lane {
        case .screen:
            screenRows.append(row)
            if screenRows.count > maxRowsPerLane {
                screenRows.removeFirst(screenRows.count - maxRowsPerLane)
            }
        case .media:
            mediaRows.append(row)
            if mediaRows.count > maxRowsPerLane {
                mediaRows.removeFirst(mediaRows.count - maxRowsPerLane)
            }
        }

        guard pipController != nil else { return }
        renderFrame()
        startHeartbeat()
        animateIn()
    }

    /// 译文回来了：补到对应那一行上
    func fill(original: String, translation: String) {
        guard !translation.isEmpty else { return }
        if let index = mediaRows.lastIndex(where: { $0.original == original }) {
            mediaRows[index].translation = translation
        } else if let index = screenRows.lastIndex(where: { $0.original == original }) {
            screenRows[index].translation = translation
        }
        guard pipController != nil else { return }
        renderFrame()
    }

    func reset() {
        screenRows.removeAll()
        mediaRows.removeAll()
        renderedKey = ""
        guard pipController != nil else { return }
        renderFrame()
    }

    /// 逐帧上移，做出"滚动"的观感（约 0.2 秒）
    private func animateIn() {
        let steps: [CGFloat] = [0.9, 0.6, 0.32, 0.12, 0]
        for (index, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.045) { [weak self] in
                self?.renderFrame(shift: step)
            }
        }
    }

    private func startHeartbeat() {
        heartbeat?.invalidate()
        // 画中画的视频层需要持续有新帧，否则会被系统回收
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.renderFrame()
        }
    }

    private func renderFrame(shift: CGFloat = 0) {
        let signature = (screenRows + mediaRows).map { $0.original + "\u{1F}" + $0.translation }.joined(separator: "\u{1E}")
        let layout = "\(screenRows.count)-\(mediaRows.count)"
        let key = "\(shift)|\(layout)|\(signature)"

        if key != renderedKey || renderedImage == nil {
            renderedImage = TextFrameRenderer.makeImage(screenRows: screenRows, mediaRows: mediaRows, shift: shift)
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
    /// 媒体通道的原文用一点薄荷色，和画面文字区分开
    static let mediaTint = UIColor(red: 0.36, green: 0.94, blue: 0.79, alpha: 1)
    /// 单行字幕的高度（含原文小字）
    static let rowHeight: CGFloat = 104

    /// 两栏渲染：媒体人声在最下面（贴近视频声音的位置），画面文字在它上面，中间一条细分隔线
    static func makeImage(screenRows: [PiPRow], mediaRows: [PiPRow], shift: CGFloat = 0) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)

        let image = renderer.image { context in
            let cg = context.cgContext
            cg.clear(CGRect(origin: .zero, size: canvas))
            guard !screenRows.isEmpty || !mediaRows.isEmpty else { return }

            let padding: CGFloat = 24
            let gap: CGFloat = 16
            let lineCount = CGFloat(screenRows.count + mediaRows.count)
            let bandHeight = min(canvas.height, lineCount * rowHeight + padding * 2 + gap)
            let band = CGRect(x: 0, y: canvas.height - bandHeight, width: canvas.width, height: bandHeight)

            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: [UIColor.black.withAlphaComponent(0).cgColor,
                                                  UIColor.black.withAlphaComponent(0.82).cgColor] as CFArray,
                                         locations: [0, 1]) {
                cg.saveGState()
                cg.clip(to: band)
                cg.drawLinearGradient(gradient,
                                      start: CGPoint(x: 0, y: band.minY),
                                      end: CGPoint(x: 0, y: band.maxY),
                                      options: [])
                cg.restoreGState()
            }

            var cursor = canvas.height - padding + shift * rowHeight

            // 媒体通道（下方的）
            for (index, row) in mediaRows.reversed().enumerated() {
                let top = cursor - rowHeight
                let alpha: CGFloat = index == 0 ? max(0.35, 1 - shift * 0.7) : 1
                drawRow(row, top: top, alpha: alpha, tinted: true)
                cursor = top
            }

            if !screenRows.isEmpty && !mediaRows.isEmpty {
                cursor -= gap / 2
                let divider = CGRect(x: 220, y: cursor, width: canvas.width - 440, height: 2)
                cg.setFillColor(TextFrameRenderer.mediaTint.withAlphaComponent(0.45).cgColor)
                cg.fill(divider)
                cursor -= gap / 2
            }

            // 画面文字通道（上方的）
            for (index, row) in screenRows.reversed().enumerated() {
                let top = cursor - rowHeight
                let alpha: CGFloat = index == 0 ? max(0.35, 1 - shift * 0.7) : 1
                drawRow(row, top: top, alpha: alpha, tinted: false)
                cursor = top
            }
        }
        return image.cgImage
    }

    private static func drawRow(_ row: PiPRow, top: CGFloat, alpha: CGFloat, tinted: Bool) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail

        if row.translation.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 42, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(alpha),
                .paragraphStyle: paragraph
            ]
            (row.original as NSString).draw(
                in: CGRect(x: 48, y: top + (rowHeight - 58) / 2, width: canvas.width - 96, height: 58),
                withAttributes: attributes
            )
            return
        }

        let translationAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 40, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(alpha),
            .paragraphStyle: paragraph
        ]
        (row.translation as NSString).draw(
            in: CGRect(x: 48, y: top + 6, width: canvas.width - 96, height: 54),
            withAttributes: translationAttributes
        )

        let originalColor = tinted
            ? TextFrameRenderer.mediaTint.withAlphaComponent(alpha * 0.75)
            : UIColor.white.withAlphaComponent(alpha * 0.62)
        let originalAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .regular),
            .foregroundColor: originalColor,
            .paragraphStyle: paragraph
        ]
        (row.original as NSString).draw(
            in: CGRect(x: 48, y: top + 62, width: canvas.width - 96, height: 32),
            withAttributes: originalAttributes
        )
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
