import Foundation
import SwiftUI
import Combine
import AVFoundation
import UIKit
import Translation

/// 全局状态与服务装配。视图里通过 @EnvironmentObject 访问。
@MainActor
final class AppEnvironment: ObservableObject {

    // MARK: - 设置项

    @Published var sourceLanguage: String = "en" {
        didSet {
            UserDefaults.standard.set(sourceLanguage, forKey: "srcLang")
            detectedSourceLanguage = nil
            rebuildTranslationConfiguration()
            // 屏幕字幕的识别语种也跟着变（扩展侧只认「自动」这个开关）
            if isScreenRunning {
                screenService.applyAutoDetect(LanguageOption.isAuto(sourceLanguage))
            }
        }
    }

    /// 自动模式下猜到的源语言
    @Published var detectedSourceLanguage: String?

    /// 实际用于翻译的源语言
    var effectiveSource: String {
        if sourceLanguage == "auto" {
            return detectedSourceLanguage ?? LanguageDetector.systemPreferredCode
        }
        return sourceLanguage
    }
    @Published var targetLanguage: String = "zh-Hans" {
        didSet {
            UserDefaults.standard.set(targetLanguage, forKey: "dstLang")
            rebuildTranslationConfiguration()
        }
    }

    /// 交给 RootView 的 .translationTask 使用；语种变化时重建，SwiftUI 会带新会话重新回调。
    @Published var translationConfiguration: TranslationSession.Configuration?
    @Published var ttsEnabled: Bool = true {
        didSet { speaker.enabled = ttsEnabled; UserDefaults.standard.set(ttsEnabled, forKey: "ttsEnabled") }
    }

    // MARK: - 服务

    let translator = Translator()
    let speaker = SpeechSynthesizer()
    let speech = SpeechService()
    let screenService = ScreenSubtitleService()
    let pip = PiPSubtitleController()
    let ocr = ImageOCRService()
    private let keeper = SilentAudioKeeper()

    // MARK: - 界面状态

    @Published var liveLines: [SubtitleLine] = []
    @Published var screenLines: [SubtitleLine] = []
    @Published var partialText: String = ""
    @Published var statusMessage: String?
    @Published var isLiveRunning = false
    @Published var isScreenRunning = false
    @Published var isPiPActive = false

    private var pending: [(text: String, kind: SubtitleKind, id: UUID, speak: Bool)] = []
    private var draining = false
    private var cancellables = Set<AnyCancellable>()
    private var backgroundObserver: NSObjectProtocol?
    private var speechTask: Task<Void, Never>?

    init() {
        if let saved = UserDefaults.standard.string(forKey: "srcLang") { sourceLanguage = saved }
        if let saved = UserDefaults.standard.string(forKey: "dstLang") { targetLanguage = saved }
        if UserDefaults.standard.object(forKey: "ttsEnabled") != nil {
            ttsEnabled = UserDefaults.standard.bool(forKey: "ttsEnabled")
        }
        speaker.enabled = ttsEnabled

        // 把子对象的变化转发给外层，SwiftUI 才能刷新
        speech.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        screenService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        pip.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        translator.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        wireSpeech()
        wireScreen()

        rebuildTranslationConfiguration()

        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.pip.startIfPossible() }
        }
    }

    private func rebuildTranslationConfiguration() {
        guard sourceLanguage != targetLanguage else {
            translationConfiguration = nil
            return
        }
        // source 传 nil 表示「自动识别原文语言」
        let source = LanguageOption.isAuto(sourceLanguage)
            ? nil
            : Locale.Language(identifier: sourceLanguage)
        translationConfiguration = TranslationSession.Configuration(
            source: source,
            target: Locale.Language(identifier: targetLanguage)
        )
    }

    /// 设置页「重新检测端上翻译语言包」：清缓存并重新挂载 translationTask
    func refreshTranslator() {
        translator.resetSession()
        translationConfiguration = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            rebuildTranslationConfiguration()
        }
    }

    private func wireSpeech() {
        speech.onPartial = { [weak self] text in
            guard let self else { return }
            self.partialText = text
            // 又开口了：取消还没播出去的译文，避免「边识别边念上一句」
            self.speechTask?.cancel()
            self.speechTask = nil
        }
        speech.onFinal = { [weak self] text, isSentenceEnd in
            self?.enqueue(text, kind: .microphone, speak: isSentenceEnd)
        }
        speech.onDetectedLanguage = { [weak self] code in
            guard let self else { return }
            if self.sourceLanguage == "auto" {
                self.detectedSourceLanguage = code
            }
        }
    }

    private func wireScreen() {
        screenService.onNewLine = { [weak self] text in
            self?.enqueue(text, kind: .screen)
        }
    }

    // MARK: - 麦克风同传

    func startLive() async {
        guard !isLiveRunning else { return }
        let permissions = await SpeechService.requestPermissions()
        guard permissions.mic else {
            statusMessage = "没有麦克风权限，请到「设置 - 译幕」中开启"
            return
        }
        guard permissions.speech else {
            statusMessage = "没有语音识别权限，请到「设置 - 译幕」中开启"
            return
        }
        liveLines.removeAll()
        partialText = ""
        isLiveRunning = true
        let auto = LanguageOption.isAuto(sourceLanguage)
        let locale = auto
            ? LanguageDetector.recognizerLocale(for: LanguageDetector.systemPreferredCode)
            : LanguageOption.option(for: sourceLanguage).recognizerLocale
        speech.start(localeID: locale, autoDetect: auto)
    }

    func stopLive() {
        speechTask?.cancel()
        speechTask = nil
        speech.stop()
        isLiveRunning = false
        partialText = ""
        if isScreenRunning {
            // 语音识别关掉会释放音频会话，屏幕字幕的保活得重新抢回来
            keeper.reactivate()
        } else {
            speaker.stop()
        }
    }

    // MARK: - 屏幕字幕

    func startScreen() {
        guard !isScreenRunning else { return }
        isScreenRunning = true
        screenLines.removeAll()
        keeper.start()
        pip.reset()
        screenService.applyAutoDetect(LanguageOption.isAuto(sourceLanguage))
        screenService.start()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            statusMessage = "音频会话切换失败：\(error.localizedDescription)"
        }
        pip.prepare()
        statusMessage = "请在控制中心开始「录屏」并选择「译幕 · 屏幕字幕」，然后回到你要翻译的 App。"
    }

    func stopScreen() {
        screenService.stop()
        pip.reset()
        pip.stop()
        keeper.stop()
        isScreenRunning = false
        isPiPActive = false
        speaker.stop()
        statusMessage = nil
    }

    func togglePiP() {
        if pip.isActive {
            pip.stop()
            isPiPActive = false
        } else {
            pip.prepare()
            pip.startIfPossible()
            isPiPActive = pip.isActive
        }
    }

    // MARK: - 识图翻译

    func translateImage(image: UIImage) async -> [RecognizedBlock] {
        var languages = ["en-US", "zh-Hans"]
        let source = LanguageOption.option(for: sourceLanguage)
        switch source.id {
        case "zh-Hans": languages = ["zh-Hans", "en-US"]
        case "zh-Hant": languages = ["zh-Hant", "zh-Hans", "en-US"]
        case "ja": languages = ["ja-JP", "en-US"]
        case "ko": languages = ["ko-KR", "en-US"]
        default: languages = [source.recognizerLocale, "en-US"]
        }

        let autoDetect = LanguageOption.isAuto(sourceLanguage)
        do {
            var blocks = try await ocr.recognize(in: image, languages: languages, autoDetect: autoDetect)
            guard !blocks.isEmpty else {
                statusMessage = "没有识别到文字，换个角度或更清晰的图片试试"
                return []
            }
            for index in blocks.indices {
                let translated = await translator.translate(blocks[index].text,
                                                            from: effectiveSource,
                                                            to: targetLanguage) ?? ""
                blocks[index].translation = translated
            }
            return blocks
        } catch {
            statusMessage = "文字识别失败：\(error.localizedDescription)"
            return []
        }
    }

    // MARK: - 翻译队列（串行，保证字幕顺序不乱）

    private func enqueue(_ text: String, kind: SubtitleKind, speak: Bool = true) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }

        // 乐观渲染：原文先上屏，译文到了再原地补上，感知延迟直接砍掉翻译耗时
        let placeholder = SubtitleLine(original: trimmed, translation: "", kind: kind)
        appendLine(placeholder)
        if kind == .screen {
            pip.push(original: trimmed)
        }

        pending.append((trimmed, kind, placeholder.id, speak))
        if pending.count > 10 {
            pending.removeFirst(pending.count - 10)
        }
        Task { await drain() }
    }

    private func appendLine(_ line: SubtitleLine) {
        switch line.kind {
        case .screen:
            screenLines.append(line)
            if screenLines.count > 80 { screenLines.removeFirst(screenLines.count - 80) }
        case .microphone, .image:
            liveLines.append(line)
            if liveLines.count > 80 { liveLines.removeFirst(liveLines.count - 80) }
        }
    }

    /// 译文回来后，按 id 找到原占位行并原地替换译文
    private func fillTranslation(id: UUID, with translation: String) {
        if let index = screenLines.firstIndex(where: { $0.id == id }) {
            screenLines[index].translation = translation
        } else if let index = liveLines.firstIndex(where: { $0.id == id }) {
            liveLines[index].translation = translation
        }
    }

    private func drain() async {
        guard !draining else { return }
        draining = true
        while !pending.isEmpty {
            let item = pending.removeFirst()
            let translation = await translator.translate(item.text,
                                                          from: effectiveSource,
                                                          to: targetLanguage) ?? ""
            guard !translation.isEmpty || translator.lastError == nil else { continue }

            // 原地补译文，不新增行，避免重复和跳动
            fillTranslation(id: item.id, with: translation)

            // 只有「句子真的说完了」才播报，并且留 0.35 秒缓冲：用户一继续说话就撤销
            if ttsEnabled, item.speak, !translation.isEmpty {
                speechTask?.cancel()
                speechTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard !Task.isCancelled else { return }
                    speaker.speak(translation, targetLanguage: targetLanguage)
                }
            }

            if item.kind == .screen {
                pip.fill(original: item.text, translation: translation)
                isPiPActive = pip.isActive
            }
        }
        draining = false
    }
}
