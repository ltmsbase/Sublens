import Foundation
import Translation

/// 翻译调度器。
///
/// TranslationSession 没有公开构造器，只能由 SwiftUI 的 .translationTask 回调交给我们，
/// 所以 RootView 挂了一个常驻的 translationTask，把会话注入这里。
/// 语种一变，SwiftUI 会带着新会话重新回调，旧会话随之被替换，不会踩「复用过期会话」的坑。
/// 语言包没装时翻译会抛错，这时自动降级到云端兜底。
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

    /// 译文缓存：屏幕 OCR 会反复识别到同样的行，命中缓存直接返回，省掉整轮翻译耗时
    private var cache: [String: String] = [:]
    private var cacheOrder: [String] = []
    private let cacheLimit = 400
    /// 端上翻译连续失败时先走云端，避免每句都先卡一次超时
    private var onDeviceFailed = false

    var hasOnDeviceSession: Bool { session != nil }

    /// 由 .translationTask 回调注入会话
    func install(_ session: TranslationSession) {
        self.session = session
        self.onDeviceFailed = false
        self.lastError = nil
        self.engineDescription = "端上翻译"
    }

    /// 清掉会话缓存，让 AppEnvironment 重新挂一次 translationTask
    func resetSession() {
        session = nil
        onDeviceFailed = false
        lastError = nil
        engineDescription = "端上翻译"
        cache.removeAll()
        cacheOrder.removeAll()
    }

    func translate(_ text: String, from source: String, to target: String) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // 「自动」时先用猜到的语种，猜不到就让端上翻译自己判断
        let from = source == "auto" ? LanguageDetector.systemPreferredCode : source
        guard from != target else { return trimmed }

        let cacheKey = "\(from)>\(target)|\(trimmed)"
        if let hit = cache[cacheKey] {
            return hit
        }

        isBusy = true
        defer { isBusy = false }

        if let session, !onDeviceFailed, from != target {
            do {
                let response = try await session.translate(trimmed)
                engineDescription = "端上翻译"
                lastError = nil
                store(cacheKey, response.targetText)
                return response.targetText
            } catch {
                onDeviceFailed = true
                lastError = "端上翻译失败（多为语言包未下载）：\(error.localizedDescription)。已切到云端兜底，去系统「翻译」App 下载语言包后可恢复离线。"
                engineDescription = "云端兜底"
            }
        }

        guard cloudFallbackEnabled else { return nil }
        let cloud = await cloudTranslate(trimmed, from: from, to: target)
        if let cloud {
            engineDescription = "云端兜底"
            store(cacheKey, cloud)
        }
        return cloud
    }

    private func store(_ key: String, _ value: String) {
        if cache[key] == nil {
            cacheOrder.append(key)
            if cacheOrder.count > cacheLimit {
                let old = cacheOrder.removeFirst()
                cache.removeValue(forKey: old)
            }
        }
        cache[key] = value
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
