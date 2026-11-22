import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var showPermissionNote = false

    var body: some View {
        NavigationStack {
            Form {
                languagesSection
                speechSection
                engineSection
                limitsSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
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

    private var languagesSection: some View {
        Section {
            Picker("原文语言", selection: $env.sourceLanguage) {
                ForEach(LanguageOption.all) { option in
                    Text(option.title).tag(option.id)
                }
            }
            Picker("译文语言", selection: $env.targetLanguage) {
                ForEach(LanguageOption.all) { option in
                    Text(option.title).tag(option.id)
                }
            }
            Button("交换") {
                let source = env.sourceLanguage
                env.sourceLanguage = env.targetLanguage
                env.targetLanguage = source
            }
        } header: {
            Text("语种")
        } footer: {
            Text("屏幕字幕、识图、同传都用这一组语种。")
        }
    }

    // MARK: - 播报

    private var speechSection: some View {
        Section {
            Toggle(isOn: $env.ttsEnabled) {
                Text("翻译后语音播报")
            }
            .tint(Palette.accent)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("语速")
                    Spacer()
                    Text(String(format: "%.2f", env.speaker.rate))
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
                Slider(value: speechRate, in: 0.3...0.7)
                    .tint(Palette.accent)
            }
        } header: {
            Text("播报")
        }
    }

    // MARK: - 引擎

    private var engineSection: some View {
        Section {
            HStack {
                Text("当前引擎")
                Spacer()
                Text(env.translator.engineDescription)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }

            Button("重新检测端上翻译语言包") {
                env.translator.resetSession()
            }

            Toggle(isOn: cloudFallback) {
                Text("端上失败时使用云端兜底")
            }
            .tint(Palette.accent)

            TextField("接口地址（OpenAI 兼容）", text: baseURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("API Key（可留空，走免 Key 的公共接口）", text: apiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if let error = env.translator.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(Color(red: 0.95, green: 0.55, blue: 0.55))
            }
        } header: {
            Text("翻译引擎")
        } footer: {
            Text("端上翻译在设备本地完成，内容不外传。留空 Key 时使用 MyMemory 公共接口兜底，质量一般、有频率限制，适合临时应急。")
        }
    }

    // MARK: - 能力边界

    private var limitsSection: some View {
        Section {
            limitRow("rectangle.dashed", "屏幕字幕",
                     "通过录屏扩展读取画面文字。受 DRM 保护的视频内容无法识别。")
            limitRow("speaker.wave.2", "播放声音",
                     "iOS 不允许第三方 App 读取其他 App 的音频流。把手机外放着听，用「同传」模式就能翻；戴耳机时麦克风听到的声音会很弱。")
            limitRow("pip", "浮窗字幕",
                     "这是系统唯一允许浮在其他 App 之上的界面（画中画）。开启后切到别的 App 也能看译文。")
        } header: {
            Text("能力边界（先说清楚，免得踩坑）")
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
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Section {
            Button {
                showPermissionNote = true
            } label: {
                Label("检查系统权限", systemImage: "hand.raised.fill")
            }
            HStack {
                Text("版本")
                Spacer()
                Text(appVersion)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
            HStack {
                Text("Bundle ID")
                Spacer()
                Text(Bundle.main.bundleIdentifier ?? "-")
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryText)
            }
        } header: {
            Text("关于译幕")
        } footer: {
            Text("译幕 SubLens · 端上识别与翻译，尽量不上传你的内容。")
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

    private var appVersion: String {        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
