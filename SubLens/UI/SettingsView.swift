import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var showPermissionNote = false

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        ScreenHeader(title: "设置", subtitle: "引擎、语种与能力边界")
                            .padding(.top, 4)

                        languagesCard
                        speechCard
                        engineCard
                        limitsCard
                        aboutCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarHidden(true)
            .alert("需要系统授权", isPresented: $showPermissionNote) {
                Button("去设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("麦克风、语音识别、相册、相机权限都在「设置 - 译幕」里。")
            }
        }
    }

    // MARK: - 语种

    private var languagesCard: some View {
        SectionCard(title: "语种") {
            VStack(spacing: 12) {
                pickerRow(title: "原文语言", selection: $env.sourceLanguage)
                Divider().overlay(Color.white.opacity(0.08))
                pickerRow(title: "译文语言", selection: $env.targetLanguage)

                Button {
                    let source = env.sourceLanguage
                    env.sourceLanguage = env.targetLanguage
                    env.targetLanguage = source
                } label: {
                    Label("交换", systemImage: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle())

                Text("屏幕字幕、识图、同传都用这一组语种。")
                    .font(.caption2)
                    .foregroundStyle(Palette.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func pickerRow(title: String, selection: Binding<String>) -> some View {
        HStack {
            Text(title)
                .font(.callout)
                .foregroundStyle(.white)
            Spacer()
            Picker(selection: selection) {
                ForEach(LanguageOption.all) { option in
                    Text(option.title).tag(option.id)
                }
            } label: {
                Text(title)
            }
            .pickerStyle(.menu)
            .tint(Palette.accent)
            .labelsHidden()
        }
    }

    // MARK: - 播报

    private var speechCard: some View {
        SectionCard(title: "播报") {
            VStack(spacing: 14) {
                Toggle(isOn: $env.ttsEnabled) {
                    Text("翻译后语音播报")
                        .font(.callout)
                        .foregroundStyle(.white)
                }
                .tint(Palette.accent)

                VStack(spacing: 6) {
                    HStack {
                        Text("语速")
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryText)
                        Spacer()
                        Text(String(format: "%.2f", env.speaker.rate))
                            .font(.caption2)
                            .foregroundStyle(Palette.tertiaryText)
                    }
                    Slider(value: speechRate, in: 0.3...0.7)
                        .tint(Palette.accent)
                }
            }
        }
    }

    // MARK: - 引擎

    private var engineCard: some View {
        SectionCard(title: "翻译引擎", tint: Palette.accent) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("当前引擎")
                        .font(.callout)
                        .foregroundStyle(.white)
                    Spacer()
                    Text(env.translator.engineDescription)
                        .font(.caption)
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background {
                            Capsule().fill(Palette.accent.opacity(0.16))
                        }
                }

                Button {
                    env.refreshTranslator()
                } label: {
                    Label("重新检测端上翻译语言包", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle())

                Toggle(isOn: cloudFallback) {
                    Text("端上失败时使用云端兜底")
                        .font(.callout)
                        .foregroundStyle(.white)
                }
                .tint(Palette.accent)

                fieldBox {
                    TextField("接口地址（OpenAI 兼容）", text: baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.caption)
                }

                fieldBox {
                    SecureField("API Key（可留空，走免 Key 的公共接口）", text: apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.caption)
                }

                if let error = env.translator.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(Palette.danger.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("端上翻译在设备本地完成，内容不外传。留空 Key 时走 MyMemory 公共接口，质量一般、有频率限制，适合应急。")
                    .font(.caption2)
                    .foregroundStyle(Palette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fieldBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.28))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    }
            }
    }

    // MARK: - 能力边界

    private var limitsCard: some View {
        SectionCard(title: "能力边界 · 先说清楚") {
            VStack(alignment: .leading, spacing: 12) {
                limitRow("rectangle.dashed", "屏幕字幕",
                         "通过录屏扩展读取画面文字，受 DRM 保护的视频无法识别。")
                Divider().overlay(Color.white.opacity(0.08))
                limitRow("speaker.wave.2", "播放声音",
                         "iOS 不允许第三方 App 读取其他 App 的音频流，请外放后用「同传」采声。")
                Divider().overlay(Color.white.opacity(0.08))
                limitRow("pip", "浮窗字幕",
                         "画中画是系统唯一允许浮在其他 App 之上的界面。")
            }
        }
    }

    private func limitRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .frame(width: 20)
                .foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 关于

    private var aboutCard: some View {
        SectionCard(title: "关于译幕") {
            VStack(spacing: 12) {
                Button {
                    showPermissionNote = true
                } label: {
                    Label("检查系统权限", systemImage: "hand.raised.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle())

                infoRow("版本", appVersion)
                infoRow("Bundle ID", Bundle.main.bundleIdentifier ?? "-")
                infoRow("有效期", "免费账号签名 7 天")

                Text("译幕 SubLens · 端上识别与翻译，尽量不上传你的内容。")
                    .font(.caption2)
                    .foregroundStyle(Palette.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)
            Spacer()
            Text(value)
                .font(.caption2)
                .foregroundStyle(Palette.tertiaryText)
        }
    }

    // MARK: - 绑定

    private var cloudFallback: Binding<Bool> {
        Binding(get: { env.translator.cloudFallbackEnabled },
                set: { env.translator.cloudFallbackEnabled = $0 })
    }

    private var baseURL: Binding<String> {
        Binding(get: { env.translator.openAIBaseURL },
                set: { env.translator.openAIBaseURL = $0 })
    }

    private var apiKey: Binding<String> {
        Binding(get: { env.translator.openAIKey },
                set: { env.translator.openAIKey = $0 })
    }

    private var speechRate: Binding<Double> {
        Binding(get: { Double(env.speaker.rate) },
                set: { env.speaker.rate = Float($0) })
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
