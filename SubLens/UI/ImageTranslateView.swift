import SwiftUI
import PhotosUI
import UIKit

struct ImageTranslateView: View {
    @EnvironmentObject private var env: AppEnvironment

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var blocks: [RecognizedBlock] = []
    @State private var isWorking = false
    @State private var showOriginal = false
    @State private var showCamera = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let image {
                    imageCanvas(image)
                    toolbar
                } else {
                    placeholder
                }

                if isWorking {
                    HStack(spacing: 8) {
                        ProgressView().tint(Palette.accent)
                        Text("正在识别并翻译…")
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryText)
                    }
                }

                if let errorText {
                    StatusBanner(text: errorText)
                }

                if !blocks.isEmpty {
                    textList
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .background { LiquidBackground() }
            .navigationTitle("识图翻译")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCamera) {
                CameraPicker(image: $image, isPresented: $showCamera)
                    .ignoresSafeArea()
            }
        }
        .onChange(of: image.map(ObjectIdentifier.init)) { _, _ in
            if let image {
                Task { await analyze(image) }
            }
        }
        .onChange(of: pickerItem) { _, newItem in
            Task { await load(newItem) }
        }
    }

    // MARK: - 空状态

    private var placeholder: some View {
        VStack(spacing: 16) {
            EmptyHint(icon: "text.viewfinder",
                      title: "拍一张或选一张有文字的图片",
                      detail: "菜单、说明书、路牌、截图都能识别，译好的文字会直接盖在原文位置上。")

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("从相册选择", systemImage: "photo.on.rectangle")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.accent, Palette.accentDeep],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: Palette.accent.opacity(0.35), radius: 14, y: 6)
            }
            .foregroundStyle(.black)

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showCamera = true
                } label: {
                    Label("直接拍照", systemImage: "camera.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
                .background(Palette.cardStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.white)
            }
        }
        .padding(.top, 20)
    }

    // MARK: - 图片 + 覆盖译文

    private func imageCanvas(_ image: UIImage) -> some View {
        GeometryReader { geo in
            let fitted = fitRect(for: image.size, in: geo.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)

                if !showOriginal {
                    ForEach(blocks) { block in
                        if !block.translation.isEmpty {
                            let rect = absoluteRect(block.rect, in: fitted)
                            Text(block.translation)
                                .font(.system(size: max(8, min(22, rect.height * 0.62)), weight: .medium))
                                .lineLimit(4)
                                .minimumScaleFactor(0.5)
                                .multilineTextAlignment(.center)
                                .frame(width: rect.width, height: rect.height)
                                .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .foregroundStyle(.white)
                                .position(x: rect.midX, y: rect.midY)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 320)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func fitRect(for imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (container.width - size.width) / 2,
                      y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    private func absoluteRect(_ normalized: CGRect, in fitted: CGRect) -> CGRect {
        CGRect(x: fitted.minX + normalized.minX * fitted.width,
               y: fitted.minY + normalized.minY * fitted.height,
               width: max(12, normalized.width * fitted.width),
               height: max(12, normalized.height * fitted.height))
    }

    // MARK: - 工具条

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                showOriginal.toggle()
            } label: {
                Label(showOriginal ? "看译文" : "看原文", systemImage: showOriginal ? "character.book.closed" : "eye")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .background(Palette.cardStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(.white)

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("换一张", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .background(Palette.cardStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(.white)

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showCamera = true
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                }
                .buttonStyle(.plain)
                .background(Palette.cardStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(.white)
            }
        }
    }

    // MARK: - 文本对照

    private var textList: some View {
        SectionCard(title: "原文 / 译文对照（\(blocks.count) 处）") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(blocks) { block in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(block.translation.isEmpty ? "…" : block.translation)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(block.text)
                            .font(.caption2)
                            .foregroundStyle(Palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 3)
                }
            }
        }
    }

    // MARK: - 处理

    @MainActor
    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let loaded = UIImage(data: data) else {
                errorText = "这张图片读不出来"
                return
            }
            blocks = []
            image = loaded
        } catch {
            errorText = "读取相册图片失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func analyze(_ image: UIImage) async {
        isWorking = true
        errorText = nil
        blocks = []
        let result = await env.translateImage(image: image)
        blocks = result
        if result.isEmpty {
            errorText = env.statusMessage
        }
        isWorking = false
        pickerItem = nil
    }
}

// MARK: - 拍照

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let picked = info[.originalImage] as? UIImage {
                parent.image = picked
            }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}
