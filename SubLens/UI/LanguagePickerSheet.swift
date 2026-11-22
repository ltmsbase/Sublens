import SwiftUI

struct LanguagePickerSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("原文语言") {
                    ForEach(LanguageOption.all) { option in
                        row(option: option, selected: env.sourceLanguage) {
                            env.sourceLanguage = option.id
                        }
                    }
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
                        let source = env.sourceLanguage
                        env.sourceLanguage = env.targetLanguage
                        env.targetLanguage = source
                    }
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
