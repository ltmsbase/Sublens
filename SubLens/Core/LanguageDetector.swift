import Foundation

/// 轻量的语种猜测：不联网、不吃 CPU，按 Unicode 文字块判断。
/// 用在「自动识别源语言」这条路径上——猜错了也不要紧，
/// 苹果的端上翻译在 source 为空时自己还会再判断一次。
enum LanguageDetector {

    static func detect(_ text: String) -> String? {
        var han = false
        var kana = false
        var hangul = false
        var thai = false
        var cyrillic = false
        var arabic = false
        var latin = false

        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF:
                kana = true
            case 0xAC00...0xD7AF, 0x1100...0x11FF:
                hangul = true
            case 0x4E00...0x9FFF, 0x3400...0x4DBF:
                han = true
            case 0x0E00...0x0E7F:
                thai = true
            case 0x0400...0x04FF:
                cyrillic = true
            case 0x0600...0x06FF, 0x0750...0x077F:
                arabic = true
            case 0x0041...0x007A, 0x00C0...0x024F:
                latin = true
            default:
                break
            }
        }

        // 日文一定带假名，先判它，否则会被汉字吃掉
        if kana { return "ja" }
        if hangul { return "ko" }
        if han { return hanIsTraditional(text) ? "zh-Hant" : "zh-Hans" }
        if thai { return "th" }
        if cyrillic { return "ru" }
        if arabic { return "ar" }
        if latin { return latinVariant(text) }
        return nil
    }

    /// 命中几个繁体专用字就当作繁体
    private static func hanIsTraditional(_ text: String) -> Bool {
        let markers: Set<Character> = ["們", "這", "說", "國", "時", "會", "學", "實",
                                       "現", "點", "麼", "樣", "過", "還", "發", "來",
                                       "對", "給", "機", "電", "話", "開", "關", "聽"]
        return text.contains { markers.contains($0) }
    }

    private static func latinVariant(_ text: String) -> String {
        if text.contains(where: { "ñ¿¡".contains($0) }) { return "es" }
        if text.contains(where: { "ãõ".contains($0) }) { return "pt" }
        if text.contains(where: { "äöüß".contains($0) }) { return "de" }
        if text.contains(where: { "àâçéèêëîïôûùœ".contains($0) }) { return "fr" }
        return "en"
    }

    /// 系统首选语言的语种码（用于「自动」模式下的初始识别器）
    static var systemPreferredCode: String {
        guard let raw = Locale.preferredLanguages.first else { return "en" }
        let id = raw.lowercased()
        if id.hasPrefix("zh") {
            if id.contains("hant") || id.contains("tw") || id.contains("hk") || id.contains("mo") {
                return "zh-Hant"
            }
            return "zh-Hans"
        }
        let supported = ["ja", "ko", "fr", "de", "es", "ru", "pt", "it", "th", "vi", "id", "ar", "tr", "nl", "hi"]
        for code in supported where id.hasPrefix(code) {
            return code
        }
        return "en"
    }

    /// 语种码 → 语音识别器用的 locale
    static func recognizerLocale(for code: String) -> String {
        switch code {
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        case "auto": return recognizerLocale(for: systemPreferredCode)
        default: return code
        }
    }
}
