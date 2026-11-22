import Foundation
import Speech
import AVFoundation

/// 麦克风实时语音识别。用 SFSpeechAudioBufferRecognitionRequest 做流式识别，
/// 优先走设备本地识别（requiresOnDeviceRecognition），断句后把整句交给翻译器。
final class SpeechService: ObservableObject {

    @Published var isRunning = false
    @Published var partialText = ""
    @Published var level: Float = 0
    @Published var errorMessage: String?

    /// 一句话结束（准备翻译）
    var onFinal: ((String) -> Void)?
    /// 实时中间结果（用于即时字幕）
    var onPartial: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var restartTimer: Timer?
    private var silenceTimer: Timer?
    private var committedCount = 0
    private var lastPartialAt = Date()
    private var localeID = "en-US"

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

    func start(localeID: String) {
        guard !isRunning else { return }
        self.localeID = localeID
        errorMessage = nil
        begin()
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
            self.isRunning = false
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
        committedCount = 0
        lastPartialAt = Date()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                self.lastPartialAt = Date()
                DispatchQueue.main.async {
                    self.partialText = text
                    self.onPartial?(text)
                }
                self.maybeCommit(text, force: result.isFinal)
            }
            if let error {
                let nsError = error as NSError
                // 用户取消、无语音输入属于正常情况，不打扰用户
                if !nsError.domain.contains("AFAssistant") && nsError.code != 203 && nsError.code != 216 {
                    DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
                }
            }
        }
    }

    private func maybeCommit(_ text: String, force: Bool = false) {
        guard text.count > committedCount else { return }
        let suffix = String(text.dropFirst(committedCount)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard suffix.count >= 2 else { return }

        let punctuated = suffix.hasSuffix("。") || suffix.hasSuffix("！") || suffix.hasSuffix("？")
            || suffix.hasSuffix(".") || suffix.hasSuffix("!") || suffix.hasSuffix("?")
        // 门槛放低：标点、18 个字符、或 0.7 秒静音就立刻送去翻译
        guard force || punctuated || suffix.count >= 18 else { return }

        committedCount = text.count
        DispatchQueue.main.async {
            self.onFinal?(suffix)
            self.partialText = ""
        }
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
        // 静音检测跑得更密，断句更快
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self, self.isRunning else { return }
            if Date().timeIntervalSince(self.lastPartialAt) > 0.7 {
                let snapshot = self.partialText
                self.maybeCommit(snapshot, force: true)
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
