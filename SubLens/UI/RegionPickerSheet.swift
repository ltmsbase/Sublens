import SwiftUI

/// 屏幕字幕的识别区域选择器。
///
/// 主 App 读不到别的 App 的画面，所以这里用一块「和真机同比例」的画布来定位置：
/// 拖动中间那块圆角矩形就是识别范围，右下角的小圆点用来缩放，
/// 也可以直接点常用预设（字幕通常在底部）。
struct RegionPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initial: ScreenRegion
    let onConfirm: (ScreenRegion) -> Void

    @State private var region: ScreenRegion
    @State private var moveStart: ScreenRegion?
    @State private var resizeStart: ScreenRegion?

    init(initial: ScreenRegion, onConfirm: @escaping (ScreenRegion) -> Void) {
        self.initial = initial
        self.onConfirm = onConfirm
        _region = State(initialValue: initial.clamped())
    }

    private let presets: [(String, ScreenRegion)] = [
        ("整屏", .full),
        ("上半屏", ScreenRegion(x: 0.02, y: 0.10, w: 0.96, h: 0.40)),
        ("中间三分之一", ScreenRegion(x: 0.02, y: 0.34, w: 0.96, h: 0.34)),
        ("底部四分之一", ScreenRegion(x: 0.02, y: 0.68, w: 0.96, h: 0.28)),
        ("底部三分之一", ScreenRegion(x: 0.02, y: 0.58, w: 0.96, h: 0.38)),
        ("窄字幕带", ScreenRegion(x: 0.06, y: 0.72, w: 0.88, h: 0.20))
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SectionCard(title: "拖动框选出要识别的地方") {
                        VStack(spacing: 12) {
                            HStack {
                                Spacer(minLength: 0)
                                canvas
                                    .frame(width: 172, height: 172 * 19.5 / 9.0)
                                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                                    }
                                Spacer(minLength: 0)
                            }

                            Text(region.summary)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Palette.secondaryText)
                        }
                    }

                    SectionCard(title: "常用位置") {
                        VStack(spacing: 8) {
                            ForEach(Array(presets.enumerated()), id: \.offset) { item in
                                let name = item.element.0
                                let target = item.element.1
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        region = target.clamped()
                                    }
                                } label: {
                                    HStack {
                                        Text(name)
                                            .font(.footnote)
                                        Spacer()
                                        if target == region {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(Palette.accent)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 6)
                            }
                        }
                    }

                    Text("框得越准越快：Vision 只处理框内那一小块，面积越小识别越勤；也能自动躲开状态栏、弹幕、广告和聊天列表这类不想要的内容。")
                        .font(.caption2)
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding(16)
            }
            .background { LiquidBackground() }
            .navigationTitle("识别区域")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("应用") {
                        onConfirm(region.clamped())
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - 画布

    private var canvas: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack(alignment: .topLeading) {
                phoneMock

                // 没有被框住的部分压暗，选区更直观
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    path.addRect(rect(for: region, in: size))
                }
                .fill(Color.black.opacity(0.42))

                selection(size: size)
            }
        }
    }

    /// 用一个和真机同比例的空壳来示意屏幕
    private var phoneMock: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.08)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 10) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 62, height: 5)
                    .padding(.top, 14)
                Spacer()
                VStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        Capsule()
                            .fill(Color.white.opacity(index == 2 ? 0.10 : 0.16))
                            .frame(width: index == 1 ? 150 : 200, height: 9)
                    }
                }
                Spacer()
                // 底部字幕示意
                VStack(spacing: 7) {
                    Capsule().fill(Color.white.opacity(0.26)).frame(width: 210, height: 10)
                    Capsule().fill(Color.white.opacity(0.18)).frame(width: 160, height: 10)
                }
                .padding(.bottom, 34)
            }
        }
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 110, height: 4)
                .padding(.bottom, 8)
        }
    }

    private func selection(size: CGSize) -> some View {
        let frame = rect(for: region, in: size)

        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Palette.accent.opacity(0.16))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: 1.6, dash: [7, 5]))
            }
            .overlay(alignment: .topLeading) {
                cornerMark.offset(x: -1, y: -1)
            }
            .overlay(alignment: .topTrailing) {
                cornerMark.offset(x: 1, y: -1)
            }
            .overlay(alignment: .bottomLeading) {
                cornerMark.offset(x: -1, y: 1)
            }
            .overlay(alignment: .bottomTrailing) {
                resizeHandle(size: size)
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .gesture(moveGesture(size: size))
    }

    private var cornerMark: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Palette.accent)
            .frame(width: 6, height: 6)
    }

    private func resizeHandle(size: CGSize) -> some View {
        Circle()
            .fill(Palette.accent)
            .frame(width: 26, height: 26)
            .overlay {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.black)
            }
            .shadow(color: Palette.accent.opacity(0.5), radius: 8)
            .offset(x: 13, y: 13)
            .gesture(resizeGesture(size: size))
    }

    // MARK: - 手势

    private func moveGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if moveStart == nil { moveStart = region }
                guard let start = moveStart else { return }
                region = ScreenRegion(
                    x: start.x + value.translation.width / size.width,
                    y: start.y + value.translation.height / size.height,
                    w: start.w,
                    h: start.h
                ).clamped()
            }
            .onEnded { _ in moveStart = nil }
    }

    private func resizeGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if resizeStart == nil { resizeStart = region }
                guard let start = resizeStart else { return }
                region = ScreenRegion(
                    x: start.x,
                    y: start.y,
                    w: start.w + value.translation.width / size.width,
                    h: start.h + value.translation.height / size.height
                ).clamped()
            }
            .onEnded { _ in resizeStart = nil }
    }

    // MARK: - 坐标换算

    private func rect(for region: ScreenRegion, in size: CGSize) -> CGRect {
        CGRect(x: region.x * size.width,
               y: region.y * size.height,
               width: region.w * size.width,
               height: region.h * size.height)
    }
}
