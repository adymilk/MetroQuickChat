import SwiftUI

/// 图片画册预览视图（支持多图滑动浏览）
struct ImageGalleryView: View {
    let images: [ImageItem]
    let initialIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showInfo = false
    
    init(images: [ImageItem], initialIndex: Int = 0) {
        self.images = images
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // 图片浏览器（TabView 实现左右滑动）
            TabView(selection: $currentIndex) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, item in
                    ImageViewItem(
                        image: item.image,
                        scale: index == currentIndex ? $scale : .constant(1.0),
                        lastScale: index == currentIndex ? $lastScale : .constant(1.0),
                        offset: index == currentIndex ? $offset : .constant(.zero),
                        lastOffset: index == currentIndex ? $lastOffset : .constant(.zero)
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .onChange(of: currentIndex) { oldValue, newValue in
                // 切换图片时重置缩放和偏移
                withAnimation {
                    scale = 1.0
                    offset = .zero
                    lastOffset = .zero
                }
            }
            
            // 顶部信息栏
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.5), in: Circle())
                    }
                    
                    Spacer()
                    
                    // 图片计数
                    Text("\(currentIndex + 1) / \(images.count)")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.5), in: Capsule())
                    
                    Spacer()
                    
                    Button(action: { showInfo.toggle() }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.5), in: Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                Spacer()
                
                // 底部信息卡片
                if showInfo, currentIndex < images.count {
                    let item = images[currentIndex]
                    VStack(alignment: .leading, spacing: 8) {
                        if let channelName = item.channelName {
                            HStack {
                                Image(systemName: "bubble.left.and.bubble.right")
                                Text(channelName)
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundStyle(.white)
                        }
                        
                        HStack {
                            Image(systemName: "person.circle")
                            Text(item.senderNickname)
                                .font(.system(size: 14))
                        }
                        .foregroundStyle(.white.opacity(0.8))
                        
                        HStack {
                            Image(systemName: "clock")
                            Text(item.createdAt, style: .relative)
                                .font(.system(size: 13))
                        }
                        .foregroundStyle(.white.opacity(0.7))
                        
                        if item.size > 0 {
                            HStack {
                                Image(systemName: "doc")
                                Text(formatSize(item.size))
                                    .font(.system(size: 13))
                            }
                            .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .gesture(
            // 单指点击切换信息显示
            TapGesture()
                .onEnded {
                    withAnimation {
                        showInfo.toggle()
                    }
                }
        )
    }
    
    private func formatSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

/// 单张图片视图项
private struct ImageViewItem: View {
    let image: UIImage
    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize
    
    var body: some View {
        GeometryReader { geometry in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    // 双指缩放
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScale
                            lastScale = value
                            scale = scale * delta
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                            // 限制缩放范围
                            if scale < 1.0 {
                                withAnimation(.spring()) {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            } else if scale > 5.0 {
                                withAnimation(.spring()) {
                                    scale = 5.0
                                }
                            }
                        }
                )
                .gesture(
                    // 单指拖动
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                            // 如果缩放回到1.0，重置偏移
                            if scale <= 1.0 {
                                withAnimation(.spring()) {
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }
                        }
                )
                .gesture(
                    // 双击缩放
                    TapGesture(count: 2)
                        .onEnded {
                            withAnimation(.spring()) {
                                if scale > 1.0 {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2.5
                                }
                            }
                        }
                )
        }
    }
}

/// 图片项数据模型
struct ImageItem: Identifiable {
    let id: UUID
    let image: UIImage
    let channelName: String?
    let senderNickname: String
    let createdAt: Date
    let size: Int64
    
    init(id: UUID = UUID(), image: UIImage, channelName: String? = nil, senderNickname: String, createdAt: Date, size: Int64 = 0) {
        self.id = id
        self.image = image
        self.channelName = channelName
        self.senderNickname = senderNickname
        self.createdAt = createdAt
        self.size = size
    }
}

struct ImageGalleryView_Previews: PreviewProvider {
    static var previews: some View {
        // 创建测试图片
        let testImage = UIImage(systemName: "photo")!
        let images = [
            ImageItem(image: testImage, senderNickname: "测试用户1", createdAt: Date(), size: 1024 * 500),
            ImageItem(image: testImage, senderNickname: "测试用户2", createdAt: Date().addingTimeInterval(-3600), size: 1024 * 800)
        ]
        
        ImageGalleryView(images: images, initialIndex: 0)
    }
}

