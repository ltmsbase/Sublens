import SwiftUI

enum Palette {
    static let background = Color(red: 0.05, green: 0.06, blue: 0.09)
    static let card = Color.white.opacity(0.06)
    static let cardStrong = Color.white.opacity(0.10)
    static let accent = Color(red: 0.35, green: 0.92, blue: 0.78)
    static let secondaryText = Color.white.opacity(0.55)
}

struct SectionCard<Content: View>: View {
    var title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.secondaryText)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct LanguageBadge: View {
    let code: String
    var highlighted: Bool = false

    var body: some View {
        Text(LanguageOption.title(for: code))
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(highlighted ? Palette.accent.opacity(0.22) : Color.white.opacity(0.08),
                        in: Capsule())
            .foregroundStyle(highlighted ? Palette.accent : Color.white.opacity(0.85))
    }
}

struct SubtitleRow: View {
    let line: SubtitleLine
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !line.translation.isEmpty {
                Text(line.translation)
                    .font(compact ? .subheadline.weight(.medium) : .title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !line.original.isEmpty {
                Text(line.original)
                    .font(compact ? .caption : .footnote)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

struct StatusBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Palette.accent)
            Text(text)
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct EmptyHint: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.accent.opacity(0.8))
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            Text(detail)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
