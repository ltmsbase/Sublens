import SwiftUI

struct LanguagePickerSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(LanguageOption.sourceOptions) { option in
                        row(option: option, selected: env.sourceLanguage) {
                            env.sourceLanguage = option.id
                        }
                    }
                } header: {
                    Text("原文语言")
                } footer: {
                    Text("选「自动识别」时，语音按听到的内容判断语种，屏幕和识图交给系统判断，适合语种不固定的场景。")
                }
                Section("译文语言") {
                    ForEach(LanguageOption.all) { option in
                        row(option: option, selected: env.targetLanguage) {
                            env.targetLanguage = option.id
                        }
                    }
                }
                Section {
                    Button("交换原文与译文") {
                        guard !LanguageOption.isAuto(env.sourceLanguage) else { return }
                        let source = env.sourceLanguage
                        env.sourceLanguage = env.targetLanguage
                        env.targetLanguage = source
                    }
                    .disabled(LanguageOption.isAuto(env.sourceLanguage))
                } footer: {
                    Text("端上翻译需要系统先下载语言包，首次使用某个语种会稍慢，之后可离线用。")
                }
            }
            .navigationTitle("翻译语种")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func row(option: LanguageOption, selected: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack {
                Text(option.title)
                    .foregroundStyle(.white)
                Spacer()
                if option.id == selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Palette.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
