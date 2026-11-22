import SwiftUI

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        TabView {
            LiveView()
                .tabItem { Label("同传", systemImage: "waveform") }

            ScreenView()
                .tabItem { Label("屏幕", systemImage: "rectangle.on.rectangle") }

            ImageTranslateView()
                .tabItem { Label("识图", systemImage: "photo") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}
