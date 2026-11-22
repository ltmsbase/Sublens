import SwiftUI
import AVFoundation

struct ScreenView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var showHowTo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header

                    if env.isScreenRunning {
                        preview
                    } else {
                        steps
                    }

                    subtitleList

                    if let message = env.statusMessage {
                        StatusBanner(text: message)
                    }
                    if let error = env.pip.lastError {
                        StatusBanner(text: error)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("屏幕字幕")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                actionButton
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showHowTo) {
            HowToSheet()
                .presentationDetents([.medium])
        }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(spacing: 10) {
            LanguageBadge(code: env.sourceLanguage)
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)
            LanguageBadge(code: env.targetLanguage, highlighted: true)
            Spacer()
            if env.isScreenRunning {
                HStack(spacing: 5) {
                    Circle().fill(Palette.accent).frame(width: 6, height: 6)
                    Text("监听中")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Palette.accent)
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - 说明

    private var steps: some View {
        SectionCard(title: "怎么用") {
            VStack(alignment: .leading, spacing: 10) {
                stepRow(1, "点下面的「开始屏幕字幕」，然后回到桌面")
                stepRow(2, "下拉打开控制中心，长按录屏按钮")
                stepRow(3, "在列表里选「译幕 · 屏幕字幕」，再点「开始直播」")
                stepRow(4, "回到你要翻译的 App，字幕会出现在这里和浮窗里")

                Divider().overlay(Color.white.opacity(0.08))

                Text("屏幕内容由 iOS 的录屏扩展提供，App 本身无法直接读取别的 App 画面。")
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stepRow(_ index: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.caption2.weight(.bold))
                .frame(width: 18, height: 18)
                .background(Palette.accent.opacity(0.25), in: Circle())
                .foregroundStyle(Palette.accent)
            Text(text)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 预览 + 浮窗

    private var preview: some View {
        VStack(spacing: 10) {
            SectionCard(title: "浮窗字幕预览") {
                PiPPreviewView(controller: env.pip)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack {
                    Text(env.pip.isActive ? "浮窗已开启，切到别的 App 也能看到" : "开启后会在其他 App 上悬浮显示译文")
                        .font(.caption2)
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        env.togglePiP()
                    } label: {
                        Text(env.pip.isActive ? "关闭浮窗" : "开启浮窗")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                }
            }

            Text(env.screenService.statusText)
                .font(.caption2)
                .foregroundStyle(Palette.secondaryText)
        }
    }

    // MARK: - 字幕列表

    @ViewBuilder
    private var subtitleList: some View {
        if env.screenLines.isEmpty {
            if env.isScreenRunning {
                EmptyHint(icon: "rectangle.dashed",
                          title: "等待画面文字",
                          detail: "切到有文字的页面（聊天、网页、字幕、菜单都行），识别到后这里会出现双语对照。")
            }
        } else {
            SectionCard(title: "最近字幕") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(env.screenLines.suffix(12).reversed()) { line in
                        SubtitleRow(line: line, compact: true)
                    }
                }
            }
        }
    }

    // MARK: - 底部按钮

    private var actionButton: some View {
        Button {
            if env.isScreenRunning {
                env.stopScreen()
            } else {
                env.startScreen()
                showHowTo = true
            }
        } label: {
            HStack {
                Image(systemName: env.isScreenRunning ? "stop.fill" : "rectangle.dashed.badge.record")
                Text(env.isScreenRunning ? "停止屏幕字幕" : "开始屏幕字幕")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .background(env.isScreenRunning ? Color(red: 0.85, green: 0.24, blue: 0.28) : Palette.accent,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(env.isScreenRunning ? .white : .black)
    }
}

// MARK: - 画中画预览容器

struct PiPPreviewView: UIViewRepresentable {
    let controller: PiPSubtitleController

    func makeUIView(context: Context) -> UIView {
        let view = controller.makeHostView()
        DispatchQueue.main.async {
            controller.prepare()
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - 使用说明

struct HowToSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("屏幕字幕依靠 iOS 的「广播上传扩展」工作。每次开始录屏都要手动选一次「译幕」，这是系统限制，任何第三方 App 都一样。")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryText)

                    SectionCard(title: "开启后你可能看不到字幕？") {
                        VStack(alignment: .leading, spacing: 8) {
                            bullet("App 在后台时，字幕会走「浮窗字幕」（画中画）显示，记得先点开启浮窗。")
                            bullet("如果只想要全屏大字幕，就留在本 App 里看。")
                            bullet("停止方式：控制中心的录屏按钮，或本页的停止按钮。")
                        }
                    }

                    SectionCard(title: "识别不到文字") {
                        VStack(alignment: .leading, spacing: 8) {
                            bullet("视频播放类 App 的画面受 DRM 保护，系统不允许录制，这类内容识别不到。")
                            bullet("字体太小或背景太花时，把原页面放大一点再试。")
                            bullet("语言设置要和画面上文字一致。")
                        }
                    }
                }
                .padding(16)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("屏幕字幕说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("知道了") { dismiss() }
                }
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(Palette.accent)
            Text(text)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
