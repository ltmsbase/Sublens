import SwiftUI

// MARK: - 设计系统（Liquid Glass 风格）
//
// 原生 .glassEffect / GlassEffectContainer 属于 iOS 26 SDK。
// 这里用「多层材质 + 高光描边 + 柔和投影 + 弹簧动效」在 iOS 18 上还原同一套视觉语言，
// 任何系统版本看起来都一致，云端编译也不依赖新版 SDK。

enum Palette {
    static let background = Color(red: 0.035, green: 0.043, blue: 0.06)
    static let backgroundLift = Color(red: 0.06, green: 0.07, blue: 0.095)

    static let glassTint = Color.white.opacity(0.035)
    static let hairline = Color.white.opacity(0.10)

    static let accent = Color(red: 0.36, green: 0.94, blue: 0.79)
    static let accentDeep = Color(red: 0.16, green: 0.72, blue: 0.62)
    static let cyan = Color(red: 0.35, green: 0.78, blue: 0.98)
    static let violet = Color(red: 0.55, green: 0.45, blue: 0.98)
    static let danger = Color(red: 0.92, green: 0.34, blue: 0.42)

    static let secondaryText = Color.white.opacity(0.58)
    static let tertiaryText = Color.white.opacity(0.38)

    /// 兼容旧代码
    static let card = Color.white.opacity(0.055)
    static let cardStrong = Color.white.opacity(0.09)

    static let specular = LinearGradient(
        colors: [Color.white.opacity(0.32), Color.white.opacity(0.06), accent.opacity(0.22)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - 玻璃卡片

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 26
    var padding: CGFloat = 18
    var tint: Color = .clear
    var glow: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Palette.glassTint)
                    }
                    .overlay {
                        if tint != .clear {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(tint.opacity(0.14))
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Palette.specular, lineWidth: 1)
                    }
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(Color.white.opacity(0.22))
                            .frame(height: 1)
                            .padding(.horizontal, 30)
                    }
                    .shadow(color: .black.opacity(0.45), radius: glow ? 26 : 16, y: glow ? 14 : 8)
                    .shadow(color: tint == .clear ? .clear : tint.opacity(0.22), radius: 22, y: 6)
            }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 26,
                   padding: CGFloat = 18,
                   tint: Color = .clear,
                   glow: Bool = false) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, padding: padding, tint: tint, glow: glow))
    }
}

// MARK: - 流动背景（玻璃背后的光斑）

struct LiquidBackground: View {
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Palette.background

                blob(color: Palette.accent, size: 420)
                    .offset(x: -geo.size.width * 0.30 + sin(phase) * 26,
                            y: -geo.size.height * 0.08 + cos(phase * 1.3) * 34)

                blob(color: Palette.violet, size: 460)
                    .offset(x: geo.size.width * 0.28 + cos(phase * 0.9) * 30,
                            y: geo.size.height * 0.05 + sin(phase * 1.1) * 26)

                blob(color: Palette.cyan, size: 380)
                    .offset(x: geo.size.width * 0.12 + sin(phase * 1.4) * 22,
                            y: geo.size.height * 0.32 + cos(phase * 0.8) * 30)
            }
            .blur(radius: 62)
            .opacity(0.40)
            .overlay {
                LinearGradient(colors: [Palette.background.opacity(0.50),
                                        Palette.background.opacity(0.86),
                                        Palette.background.opacity(0.97)],
                               startPoint: .top, endPoint: .bottom)
            }
            .clipped()
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }

    private func blob(color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: 42)
    }
}

// MARK: - 玻璃按钮

struct GlassButtonStyle: ButtonStyle {
    var tint: Color = .clear
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(prominent ? Color.black : Color.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background {
                ZStack {
                    if prominent {
                        Capsule().fill(
                            LinearGradient(colors: [Palette.accent, Palette.accentDeep],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(tint == .clear ? Palette.glassTint : tint.opacity(0.16))
                    }
                    Capsule().strokeBorder(
                        prominent ? Color.white.opacity(0.38) : Color.white.opacity(0.16),
                        lineWidth: 1
                    )
                }
            }
            .shadow(color: prominent ? Palette.accent.opacity(0.42) : .black.opacity(0.30),
                    radius: prominent ? 18 : 10, y: prominent ? 8 : 4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - 卡片与行

struct SectionCard<Content: View>: View {
    var title: String?
    var tint: Color = .clear
    let content: Content

    init(title: String? = nil, tint: Color = .clear, @ViewBuilder content: () -> Content) {
        self.title = title
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Palette.tertiaryText)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: tint)
    }
}

struct LanguageBadge: View {
    let code: String
    var highlighted: Bool = false

    var body: some View {
        Text(LanguageOption.title(for: code))
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule().fill(highlighted ? Palette.accent.opacity(0.20) : Color.white.opacity(0.05))
                    }
                    .overlay {
                        Capsule().strokeBorder(
                            highlighted ? Palette.accent.opacity(0.55) : Color.white.opacity(0.14),
                            lineWidth: 1
                        )
                    }
            }
            .foregroundStyle(highlighted ? Palette.accent : Color.white.opacity(0.86))
    }
}

struct SubtitleRow: View {
    let line: SubtitleLine
    var compact: Bool = false

    private var isPending: Bool {
        line.translation.isEmpty && !line.original.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            if line.kind == .screen || line.kind == .media {
                HStack(spacing: 4) {
                    Image(systemName: line.kind == .media ? "waveform" : "text.viewfinder")
                        .font(.system(size: 9, weight: .bold))
                    Text(line.kind == .media ? "媒体" : "画面")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(line.kind == .media ? Palette.accent : Palette.secondaryText)
            }

            if isPending {
                // 译文还在路上：原文先用正文大小占位，后面补译文时不会跳版
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(line.original)
                        .font(compact ? .subheadline.weight(.medium) : .title3.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                    PendingDots()
                }
            }
            if !line.translation.isEmpty {
                Text(line.translation)
                    .font(compact ? .subheadline.weight(.medium) : .title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !line.original.isEmpty && !isPending {
                Text(line.original)
                    .font(compact ? .caption : .footnote)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, line.translation.isEmpty ? 0 : 10)
                    .overlay(alignment: .leading) {
                        if !line.translation.isEmpty {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Palette.accent.opacity(0.55))
                                .frame(width: 2)
                                .padding(.vertical, 1)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, compact ? 4 : 7)
    }
}

struct StatusBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle.fill")
                .font(.footnote)
                .foregroundStyle(Palette.accent)
            Text(text)
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
        }
    }
}

struct EmptyHint: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Palette.accent.opacity(0.10))
                    .frame(width: 68, height: 68)
                    .blur(radius: 8)
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Palette.accent)
            }
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            Text(detail)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.secondaryText)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

// MARK: - 翻译中指示

struct PendingDots: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Palette.accent.opacity(0.65))
                    .frame(width: 4, height: 4)
                    .scaleEffect(animating ? 1 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.55)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.16),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
        .accessibilityHidden(true)
    }
}

// MARK: - 音频脉冲

struct PulseRing: View {
    var level: Float
    var color: Color = Palette.accent

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                let progress = Double(index) / 3.0
                Circle()
                    .stroke(color.opacity(0.42 * (1 - progress)), lineWidth: 1.5)
                    .scaleEffect(1 + progress * 0.55 + Double(level) * 0.5)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: level)
    }
}

// MARK: - 页面标题

struct ScreenHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [Color.white, Color.white.opacity(0.70)],
                                   startPoint: .top, endPoint: .bottom)
                )
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Palette.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
