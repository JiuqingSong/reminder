import SwiftUI

/// 全屏图片浏览：左右滑动切换，双指缩放，双击放大/还原
struct ImageViewer: View {
    let fileNames: [String]
    @State var startIndex: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $startIndex) {
                ForEach(Array(fileNames.enumerated()), id: \.offset) { index, name in
                    ZoomableImage(fileName: name).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: fileNames.count > 1 ? .always : .never))

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .white.opacity(0.3))
            }
            .padding()
        }
    }
}

private struct ZoomableImage: View {
    let fileName: String
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        if let image = AttachmentStore.image(fileName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            scale = max(1, lastScale * value.magnification)
                        }
                        .onEnded { _ in
                            lastScale = scale
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation {
                        scale = scale > 1 ? 1 : 2.5
                        lastScale = scale
                    }
                }
        } else {
            Image(systemName: "photo").foregroundStyle(.secondary)
        }
    }
}
