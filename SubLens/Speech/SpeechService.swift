import Foundation
import Speech
import AVFoundation

/// 麦克风实时语音识别。用 SFSpeechAudioBufferRecognitionRequest 做流式识别，
/// 优先走设备本地识别（requiresOnDeviceRecognition），断句后把整句交给翻译器。
///
/// 关键点：
/// - 系统每给出一次 final 结果，这条识别任务就结束了；必须立刻重建，否则「继续说话没反应」。
/// - 已提交的文本用「已提交前缀」对齐，只显示未提交的尾巴，避免上屏的字来回改。
/// - 原文语言设成「自动」时，按识别出来的文字判断语种，必要时换识别器。
final class SpeechService: ObservableObject {

    @Published var isRunning = false
    @Published var partialText = ""
    @Published var level: Float = 0
    @Published var errorMessage: String?

    /// 一句话结束（准备翻译）；Bool 表示是否是真正的句子结尾（可播报）
    var onFinal: ((String, Bool) -> Void)?
    /// 实时中间结果（用于即时字幕）
    var onPartial: ((String) -> Void)?
    /// 自动模式下判断出来的源语言
    var onDetectedLanguage: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var restartTimer: Timer?
    private var silenceTimer: Timer?

    /// 已经提交给翻译的那部分文本（用于计算未提交的尾巴，避免系统改写导致重复）
    private var committedPrefix = ""
    private var lastFullText = ""
    private var lastPartialAt = Date()
    private var localeID = "en-US"
    private var autoDetect = false
    private var restarting = false
    /// 音频流模式下，外部喂进来的 PCM 都排在这条队列上
    private let feedQueue = DispatchQueue(label: "com.sublens.speech.feed", qos: .userInitiated)

    // MARK: - 权限

    static func requestPermissions() async -> (mic: Bool, speech: Bool) {
        let mic: Bool = await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        let speech: Bool = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        return (mic, speech)
    }

    // MARK: - 生命周期

    func start(localeID: String, autoDetect: Bool = false) {
        guard !isRunning else { return }
        self.localeID = localeID
        self.autoDetect = autoDetect
        errorMessage = nil
        begin()
    }

    /// 音频流模式：不采集麦克风，由录屏扩展转来的媒体音频驱动识别
    func startFeed(localeID: String, autoDetect: Bool = false) {
        guard !isRunning else { return }
        self.localeID = localeID
        self.autoDetect = autoDetect
        errorMessage = nil

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else {
            fail("当前语种的语音识别不可用")
            return
        }
        self.recognizer = recognizer

        DispatchQueue.main.async { self.isRunning = true }
        startTask()
        scheduleTimers()
    }

    /// 追加一段 16kHz 单声道 Int16 的 PCM，喂给识别请求
    func appendPCM(_ data: Data) {
        guard !data.isEmpty else { return }
        feedQueue.async { [weak self] in
            guard let self, self.isRunning else { return }
            guard let buffer = Self.makeBuffer(fromPCM16: data, sampleRate: 16000) else { return }
            self.request?.append(buffer)
            self.estimateLevel(buffer)
        }
    }

    /// Int16 → AVAudioPCMBuffer（Float32 单声道）
    static func makeBuffer(fromPCM16 data: Data, sampleRate: Double) -> AVAudioPCMBuffer? {
        let frameCount = data.count / 2
        guard frameCount > 0,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: 1,
                                         interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let out = buffer.floatChannelData?[0] else { return nil }
        data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: Int16.self).baseAddress else { return }
            for index in 0..<frameCount {
                out[index] = Float(base[index]) / 32768.0
            }
        }
        return buffer
    }

    private func begin() {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            fail("当前语种的语音识别不可用")
            return
        }
        self.recognizer = recognizer

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord,
                                   mode: .default,
                                   options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            fail("音频会话启动失败：\(error.localizedDescription)")
            return
        }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail("没有可用的麦克风输入")
            return
        }

        if !tapInstalled {
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self else { return }
                self.request?.append(buffer)
                self.estimateLevel(buffer)
            }
            tapInstalled = true
        }

        if !engine.isRunning {
            engine.prepare()
            do {
                try engine.start()
            } catch {
                fail("音频引擎启动失败：\(error.localizedDescription)")
                return
            }
        }

        startTask()
        scheduleTimers()
        DispatchQueue.main.async {
            self.isRunning = true
        }
    }

    func stop() {
        restartTimer?.invalidate()
        restartTimer = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning {
            engine.stop()
        }
        DispatchQueue.main.async {
            self.isRunning = false
            self.partialText = ""
            self.level = 0
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func fail(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
        }
        stop()
    }

    // MARK: - 识别任务

    private func startTask() {
        task?.cancel()
        guard let recognizer else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if #available(iOS 16.0, *), recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request
        // 新任务的转写从零开始，已提交指针跟着重置
        committedPrefix = ""
        lastFullText = ""
        lastPartialAt = Date()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                self.handle(result)
            }
            if let error {
                let nsError = error as NSError
                // 用户取消、无语音输入属于正常情况，不打扰用户
                if !nsError.domain.contains("AFAssistant") && nsError.code != 203 && nsError.code != 216 {
                    DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
                }
                // 任务因为超时/静音结束了，也要重建，否则后面说的话全丢
                self.restartTaskSoon()
            }
        }
    }

    private func handle(_ result: SFSpeechRecognitionResult) {
        let text = result.bestTranscription.formattedString
        lastPartialAt = Date()
        lastFullText = text

        // 自动语种：认出是别的语言就换识别器
        if autoDetect, text.count >= 4, let detected = LanguageDetector.detect(text) {
            let wanted = LanguageDetector.recognizerLocale(for: detected)
            DispatchQueue.main.async { self.onDetectedLanguage?(detected) }

            if wanted != localeID {
                // 先把已经听到的内容交出去，再换识别器，不然这句就丢了
                let pendingTail = tailText(of: text)
                if !pendingTail.isEmpty {
                    DispatchQueue.main.async { self.onPartial?(pendingTail) }
                }
                maybeCommit(tail: pendingTail, fullText: text, force: true, speak: false)
                switchRecognizer(to: wanted)
                return
            }
        }

        let tail = tailText(of: text)

        DispatchQueue.main.async {
            self.partialText = tail
        }
        if !tail.isEmpty {
            DispatchQueue.main.async { self.onPartial?(tail) }
        }

        maybeCommit(tail: tail, fullText: text, force: result.isFinal)

        // 系统给了 final，这条任务就结束了，立刻重建才能接着听
        if result.isFinal {
            restartTaskSoon()
        }
    }

    /// 算出「还没提交给翻译」的那一段
    private func tailText(of text: String) -> String {
        guard !committedPrefix.isEmpty else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.hasPrefix(committedPrefix) {
            return String(text.dropFirst(committedPrefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 系统改写了已提交部分：按最长公共前缀对齐
        let common = commonPrefixLength(committedPrefix, text)
        if common >= committedPrefix.count - 3, common > 0 {
            return String(text.dropFirst(common))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 改得太多（整句重来），把提交指针挪过去：宁可少一次补译，也不要卡住不动
        committedPrefix = text
        return ""
    }

    private func maybeCommit(tail: String, fullText: String, force: Bool = false, speak: Bool = true) {
        guard tail.count >= (force ? 1 : 2) else { return }

        // 只有三种情况才算「一句话说完」：系统给出最终结果、出现终止标点、静音超过阈值。
        // 不按字数硬切——那正是「一句话被切成两半、后一半又被纠正」的根源。
        let punctuated = tail.hasSuffix("。") || tail.hasSuffix("！") || tail.hasSuffix("？")
            || tail.hasSuffix(".") || tail.hasSuffix("!") || tail.hasSuffix("?")
        let silent = Date().timeIntervalSince(lastPartialAt) > 0.9

        guard force || punctuated || silent else { return }

        committedPrefix = fullText
        let isSentenceEnd = speak && (force || punctuated)
        DispatchQueue.main.async {
            self.onFinal?(tail, isSentenceEnd)
            self.partialText = ""
        }
    }

    /// 换识别器（自动语种模式下用）
    private func switchRecognizer(to newLocale: String) {
        localeID = newLocale
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: newLocale)) ?? SFSpeechRecognizer()
        restartTaskSoon()
    }

    /// 重建识别任务：final、错误、静默失效都走这里
    private func restartTaskSoon() {
        guard isRunning, !restarting else { return }
        restarting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.restarting = false
            guard self.isRunning else { return }
            self.startTask()
        }
    }

    private func commonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        var count = 0
        for (left, right) in zip(lhs, rhs) {
            if left == right {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    private func scheduleTimers() {
        restartTimer?.invalidate()
        // 系统识别任务跑太久容易静默失效，定期重建一次
        restartTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.startTask()
            DispatchQueue.main.async { self.partialText = "" }
        }

        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self, self.isRunning else { return }

            // 任务已经自己结束了（没有回调告诉我们），直接重建
            if self.task == nil || self.task?.state == .completed {
                self.restartTaskSoon()
                return
            }

            if Date().timeIntervalSince(self.lastPartialAt) > 0.9, !self.partialText.isEmpty {
                self.maybeCommit(tail: self.partialText, fullText: self.lastFullText, force: false)
            }
        }
    }

    // MARK: - 电平

    private func estimateLevel(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        var sum: Float = 0
        for index in 0..<frames {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frames))
        let normalized = min(1.0, max(0.0, rms * 6))
        DispatchQueue.main.async { self.level = normalized }
    }
}
