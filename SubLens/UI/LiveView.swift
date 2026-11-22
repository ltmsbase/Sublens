import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var showLanguagePicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackground()

                VStack(spacing: 0) {
                    headerBlock
                        .padding(.horizontal, 18)
                        .padding(.top, 6)

                    transcript
                        .padding(.horizontal, 18)
                        .padding(.top, 12)

                    Spacer(minLength: 0)
                }
            }
            .safeAreaInset(edge: .bottom) { controls }
            .navigationBarHidden(true)
            .sheet(isPresented: $showLanguagePicker) {
                LanguagePickerSheet()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
            }
        }
    }

    // MARK: - 顶部

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                ScreenHeader(title: "实时同传",
                             subtitle: env.isLiveRunning ? "正在听 · 端上识别与翻译" : "麦克风同传")
                Spacer()
                Button {
                    showLanguagePicker = true
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 38, height: 38)
                }
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay { Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                LanguageBadge(code: env.sourceLanguage)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(Palette.tertiaryText)
                LanguageBadge(code: env.targetLanguage, highlighted: true)
                Spacer()
                if env.speech.isRunning {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Palette.accent)
                            .frame(width: 5, height: 5)
                        Text("识别中")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Palette.accent)
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    // MARK: - 字幕区

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if env.liveLines.isEmpty && env.speech.partialText.isEmpty {
                        EmptyHint(icon: "waveform",
                                  title: "还没有字幕",
                                  detail: "点下方麦克风开始收音，把手机放在说话人附近，或对着外放的声音。")
                    }

                    if !env.speech.partialText.isEmpty {
                        partialCard
                            .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .bottom)),
                                                    removal: .opacity))
                    }

                    ForEach(env.liveLines.suffix(30)) { line in
                        SubtitleRow(line: line)
                            .id(line.id)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white.opacity(0.045))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                                    }
                            }
                            .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .bottom)),
                                                    removal: .opacity))
                    }
                }
                .padding(.bottom, 16)
                .animation(.spring(response: 0.42, dampingFraction: 0.86), value: env.liveLines.count)
            }
            .scrollIndicators(.hidden)
            .onChange(of: env.liveLines.count) { _, _ in
                guard let last = env.liveLines.last else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .mask {
            // 上下淡出，滚动时更"液体"
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .white, location: 0.06),
                .init(color: .white, location: 0.92),
                .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
    }

    private var partialCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Palette.danger.opacity(0.9))
                    .frame(width: 6, height: 6)
                Text("正在听")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.secondaryText)
            }
            Text(env.speech.partialText)
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20, padding: 16, tint: Palette.accent, glow: true)
    }

    // MARK: - 控制区

    private var controls: some View {
        VStack(spacing: 14) {
            if let message = env.statusMessage {
                StatusBanner(text: message)
            } else if let error = env.speech.errorMessage {
                StatusBanner(text: error)
            }

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(env.isLiveRunning ? "正在同传" : "点击开始")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(env.isLiveRunning ? "说完一句会自动断句翻译" : "识别 → 翻译 → 字幕")
                        .font(.caption2)
                        .foregroundStyle(Palette.tertiaryText)
                }

                Spacer(minLength: 0)

                Button {
                    toggle()
                } label: {
                    ZStack {
                        PulseRing(level: env.speech.level,
                                  color: env.isLiveRunning ? Palette.accent : Palette.tertiaryText)
                            .frame(width: 76, height: 76)
                            .opacity(env.isLiveRunning ? 1 : 0.45)

                        Circle()
                            .fill(
                                env.isLiveRunning
                                ? LinearGradient(colors: [Palette.danger, Color(red: 0.72, green: 0.18, blue: 0.26)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Palette.accent, Palette.accentDeep],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 64, height: 64)
                            .overlay {
                                Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                            }
                            .shadow(color: (env.isLiveRunning ? Palette.danger : Palette.accent).opacity(0.45),
                                    radius: 18, y: 6)

                        Image(systemName: env.isLiveRunning ? "stop.fill" : "mic.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(env.isLiveRunning ? .white : .black)
                    }
                    .frame(width: 84, height: 84)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .glassCard(cornerRadius: 26, padding: 0, glow: env.isLiveRunning)

            Toggle(isOn: $env.ttsEnabled) {
                Label("译文播报", systemImage: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
            .toggleStyle(.switch)
            .tint(Palette.accent)
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func toggle() {
        if env.isLiveRunning {
            env.stopLive()
        } else {
            Task { await env.startLive() }
        }
    }
}
