import Foundation
import AVFoundation

/// 译文语音播报。同传模式下会被频繁调用，这里做「只播最新一句」的处理，避免排队延迟。
final class SpeechSynthesizer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    @Published var isSpeaking = false
    @Published var enabled = true
    @Published var rate: Float = 0.5

    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String, targetLanguage: String) {
        guard enabled else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: LanguageOption.option(for: targetLanguage).speechLocale)
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0
        synth.speak(utterance)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = true }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
}
