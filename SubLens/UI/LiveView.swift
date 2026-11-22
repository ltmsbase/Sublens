import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var showLanguagePicker = false

    private var latest: SubtitleLine? { env.liveLines.last }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                languageBar

                liveTranscript

                statusArea

                controls
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("实时同传")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showLanguagePicker = true
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                }
            }
        }
        .sheet(isPresented: $showLanguagePicker) {
            LanguagePickerSheet()
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - 语种

    private var languageBar: some View {
        HStack(spacing: 10) {
            LanguageBadge(code: env.sourceLanguage)
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)
            LanguageBadge(code: env.targetLanguage, highlighted: true)
            Spacer()
            if env.speech.isRunning {
                Text("识别中")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Palette.accent)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - 字幕区

    private var liveTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if env.liveLines.isEmpty && env.speech.partialText.isEmpty {
                        EmptyHint(icon: "waveform",
                                  title: "还没有字幕",
                                  detail: "点下方按钮开始收音，把手机放在说话人附近，或对着外放的声音。")
                    }

                    if !env.speech.partialText.isEmpty {
                        partialCard
                    }

                    ForEach(env.liveLines.suffix(30)) { line in
                        SubtitleRow(line: line)
                        Divider().overlay(Color.white.opacity(0.08))
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxHeight: .infinity)
    }

    private var partialCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red.opacity(0.9))
                    .frame(width: 6, height: 6)
                Text("正在听")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.secondaryText)
            }
            Text(env.speech.partialText)
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.cardStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var statusArea: some View {
        if let message = env.statusMessage {
            StatusBanner(text: message)
        } else if let error = env.speech.errorMessage {
            StatusBanner(text: error)
        } else if env.isLiveRunning {
            Text("端上识别 · 端上翻译 · 不上传内容")
                .font(.caption2)
                .foregroundStyle(Palette.secondaryText)
        }
    }

    // MARK: - 控制区

    private var controls: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Palette.accent.opacity(0.25), lineWidth: 2)
                    .frame(width: 96, height: 96)
                    .scaleEffect(1 + CGFloat(env.speech.level) * 0.35)
                    .animation(.easeOut(duration: 0.18), value: env.speech.level)

                Button {
                    toggle()
                } label: {
                    ZStack {
                        Circle()
                            .fill(env.isLiveRunning ? Color(red: 0.85, green: 0.24, blue: 0.28) : Palette.accent)
                        Image(systemName: env.isLiveRunning ? "stop.fill" : "mic.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(env.isLiveRunning ? .white : .black)
                    }
                    .frame(width: 72, height: 72)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 104)

            HStack(spacing: 16) {
                Toggle(isOn: $env.ttsEnabled) {
                    Label("译文播报", systemImage: "speaker.wave.2.fill")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .tint(Palette.accent)
                .fixedSize()
            }
        }
        .padding(.bottom, 4)
    }

    private func toggle() {
        if env.isLiveRunning {
            env.stopLive()
        } else {
            Task { await env.startLive() }
        }
    }
}
