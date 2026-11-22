import Foundation
import Translation

/// 翻译调度器。
///
/// 端上会话用 `TranslationSession(installedSource:target:)` 自己创建，
/// 不用 SwiftUI 的 .translationTask 回调——官方文档说明配置变化后继续用旧会话会 fatalError，
/// 自己持有会话反而更稳，也不依赖界面生命周期。
/// 语言包没装会抛错，这时自动降级到云端兜底。
@MainActor
final class Translator: ObservableObject {

    @Published var lastError: String?
    @Published var isBusy = false
    @Published var engineDescription = "端上翻译"

    // 云端兜底配置（在设置页里填）
    @Published var cloudFallbackEnabled = true
    @Published var openAIBaseURL = "https://api.openai.com/v1"
    @Published var openAIKey = ""

    private var session: TranslationSession?
    private var sessionKey = ""

    var hasOnDeviceSession: Bool { session != nil }

    private func onDeviceSession(source: String, target: String) -> TranslationSession? {
        let key = source + ">" + target
        if key == sessionKey {
            return session
        }

        do {
            let newSession = try TranslationSession(
                installedSource: LanguageOption.option(for: source).locale,
                target: LanguageOption.option(for: target).locale
            )
            session = newSession
            sessionKey = key
            lastError = nil
            engineDescription = "端上翻译"
            return newSession
        } catch {
            session = nil
            sessionKey = key
            lastError = "端上翻译不可用：\(LanguageOption.title(for: source)) → \(LanguageOption.title(for: target)) 的语言包还没装。去系统「翻译」App 下载后即可离线翻译；当前已尝试云端兜底。"
            return nil
        }
    }

    func translate(_ text: String, from source: String, to target: String) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard source != target else { return trimmed }

        isBusy = true
        defer { isBusy = false }

        if let session = onDeviceSession(source: source, target: target) {
            do {
                let response = try await session.translate(trimmed)
                engineDescription = "端上翻译"
                return response.targetText
            } catch {
                lastError = "端上翻译失败：\(error.localizedDescription)"
            }
        }

        guard cloudFallbackEnabled else { return nil }
        let cloud = await cloudTranslate(trimmed, from: source, to: target)
        if cloud != nil { engineDescription = "云端兜底" }
        return cloud
    }

    func resetSession() {
        session = nil
        sessionKey = ""
        lastError = nil
    }

    // MARK: - 云端兜底

    private func cloudTranslate(_ text: String, from source: String, to target: String) async -> String? {
        let key = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            return await requestOpenAICompatible(text, from: source, to: target, key: key)
        }
        return await requestMyMemory(text, from: source, to: target)
    }

    /// 免配置的兜底接口：MyMemory。质量一般，但开箱即用、不需要任何 Key。
    private func requestMyMemory(_ text: String, from source: String, to target: String) async -> String? {
        let from = LanguageOption.option(for: source).cloudCode
        let to = LanguageOption.option(for: target).cloudCode
        var components = URLComponents(string: "https://api.mymemory.translated.net/get")
        components?.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: "\(from)|\(to)")
        ]
        guard let url = components?.url else { return nil }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = json["responseData"] as? [String: Any],
                  let translated = payload["translatedText"] as? String else { return nil }
            let cleaned = translated.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            lastError = "云端翻译失败：\(error.localizedDescription)"
            return nil
        }
    }

    /// 兼容 OpenAI 协议的自建/第三方接口，质量更高，需要自己填 Key。
    private func requestOpenAICompatible(_ text: String, from source: String, to target: String, key: String) async -> String? {
        var base = openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = "https://api.openai.com/v1" }
        let endpoint: URL?
        if base.contains("/chat/completions") {
            endpoint = URL(string: base)
        } else {
            endpoint = URL(string: base.hasSuffix("/") ? base + "chat/completions" : base + "/chat/completions")
        }
        guard let endpoint else { return nil }

        let system = "你是一个实时字幕翻译引擎。把用户给的内容翻译成\(LanguageOption.title(for: target))，只输出译文本身，不要解释，不要加引号。"
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": text]
            ]
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                lastError = "云端接口返回 \(http.statusCode)"
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else { return nil }
            let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            lastError = "云端翻译失败：\(error.localizedDescription)"
            return nil
        }
    }
}
