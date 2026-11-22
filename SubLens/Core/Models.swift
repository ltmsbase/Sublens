import Foundation

/// 字幕来源
enum SubtitleKind: String, Codable, Hashable {
    case screen      // 屏幕内容
    case microphone  // 麦克风同传
    case image       // 识图翻译
}

/// 一条双语字幕
struct SubtitleLine: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var original: String
    var translation: String
    var kind: SubtitleKind
    var date: Date = Date()

    var isEmpty: Bool { original.isEmpty && translation.isEmpty }
}

/// 识图翻译得到的一个文本块
struct RecognizedBlock: Identifiable {
    var id: UUID = UUID()
    var text: String
    var translation: String = ""
    /// 归一化坐标，原点在左上角
    var rect: CGRect
}

/// 语言选项（用固定列表而不是全套 Locale，避免界面上出现大量生僻语种）
struct LanguageOption: Identifiable, Hashable {
    let id: String
    let title: String

    /// 苹果端上翻译使用的标识
    var locale: Locale {
        if id == "auto" { return Locale(identifier: LanguageDetector.recognizerLocale(for: LanguageDetector.systemPreferredCode)) }
        return Locale(identifier: id)
    }

    /// 语音合成使用的 BCP-47 标识
    var speechLocale: String {
        switch id {
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        default: return id
        }
    }

    /// 语音识别使用的标识
    var recognizerLocale: String {
        switch id {
        case "auto": return LanguageDetector.recognizerLocale(for: LanguageDetector.systemPreferredCode)
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        default: return id
        }
    }

    /// 云端兜底接口使用的两位/区段代码
    var cloudCode: String {
        switch id {
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        default: return id
        }
    }

    /// 「自动识别」只用于原文语言
    static let auto = LanguageOption(id: "auto", title: "自动识别")

    static let all: [LanguageOption] = [
        .init(id: "en", title: "英语"),
        .init(id: "zh-Hans", title: "简体中文"),
        .init(id: "zh-Hant", title: "繁体中文"),
        .init(id: "ja", title: "日语"),
        .init(id: "ko", title: "韩语"),
        .init(id: "fr", title: "法语"),
        .init(id: "de", title: "德语"),
        .init(id: "es", title: "西班牙语"),
        .init(id: "ru", title: "俄语"),
        .init(id: "pt", title: "葡萄牙语"),
        .init(id: "it", title: "意大利语"),
        .init(id: "th", title: "泰语"),
        .init(id: "vi", title: "越南语"),
        .init(id: "id", title: "印尼语"),
        .init(id: "ar", title: "阿拉伯语"),
        .init(id: "tr", title: "土耳其语"),
        .init(id: "nl", title: "荷兰语"),
        .init(id: "hi", title: "印地语")
    ]

    /// 原文语言候选：自动识别排在最前
    static var sourceOptions: [LanguageOption] { [auto] + all }

    static func title(for id: String) -> String {
        if id == "auto" { return auto.title }
        return all.first(where: { $0.id == id })?.title ?? id
    }

    static func isAuto(_ id: String) -> Bool { id == "auto" }

    static func option(for id: String) -> LanguageOption {
        all.first(where: { $0.id == id }) ?? LanguageOption(id: id, title: id)
    }
}
