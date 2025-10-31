import SwiftUI

/// 消息文件列表视图（按类型显示）
struct MessageFileListView: View {
    let fileType: MessageFileItem.FileType
    let channelManager: ChannelManager
    @State private var files: [MessageFileItem] = []
    @State private var isLoading = true
    @State private var selectedImageIndex: Int?
    @State private var galleryImages: [ImageItem] = []
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if files.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "folder")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                    Text("暂无\(typeName)")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(Array(files.enumerated()), id: \.element.id) { index, item in
                        MessageFileRow(
                            item: item,
                            onTap: {
                                if item.fileType == .image {
                                    openImageGallery(at: index)
                                }
                            }
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(typeName)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: Binding(
            get: { selectedImageIndex != nil },
            set: { if !$0 { selectedImageIndex = nil } }
        )) {
            if let index = selectedImageIndex, !galleryImages.isEmpty, index < galleryImages.count {
                ImageGalleryView(images: galleryImages, initialIndex: index)
            }
        }
        .onAppear {
            loadFiles()
        }
    }
    
    private var typeName: String {
        switch fileType {
        case .text: return "文字消息"
        case .image: return "图片"
        case .video: return "视频"
        case .voice: return "语音"
        case .other: return "其他"
        }
    }
    
    private func loadFiles() {
        isLoading = true
        Task { @MainActor in
            // 获取频道名称映射
            let channelNameMap = Dictionary(uniqueKeysWithValues: channelManager.channels.map { ($0.id, $0.name) })
            
            // 在后台线程执行文件加载
            let loadedFiles = await Task.detached {
                channelManager.store.getAllMessageFiles(byType: fileType) { channelId in
                    return channelNameMap[channelId]
                }
            }.value
            
            self.files = loadedFiles
            self.isLoading = false
            
            // 如果是图片类型，预先准备图片数据
            if fileType == .image {
                prepareGalleryImages(from: loadedFiles)
            }
        }
    }
    
    /// 准备画册图片数据
    private func prepareGalleryImages(from files: [MessageFileItem]) {
        Task.detached {
            var images: [ImageItem] = []
            
            for file in files {
                if let image = await extractImage(from: file) {
                    await MainActor.run {
                        images.append(ImageItem(
                            id: file.id,
                            image: image,
                            channelName: file.channelName,
                            senderNickname: file.senderNickname,
                            createdAt: file.createdAt,
                            size: file.size
                        ))
                    }
                }
            }
            
            await MainActor.run {
                self.galleryImages = images
            }
        }
    }
    
    /// 从 MessageFileItem 提取图片
    private func extractImage(from item: MessageFileItem) async -> UIImage? {
        // 从 LocalStore 加载完整消息数据（包含图片数据）
        let message = channelManager.store.loadMessage(for: item)
        
        // 尝试从 messageType 获取
        if let message = message, let messageType = message.messageType {
            switch messageType {
            case .image(let data):
                return UIImage(data: data)
            default:
                break
            }
        }
        
        // 如果 MessageFileItem 本身有 messageType，也尝试（回退方案）
        if let messageType = item.messageType {
            switch messageType {
            case .image(let data):
                return UIImage(data: data)
            default:
                break
            }
        }
        
        // 尝试从 attachment 获取
        if let message = message, let attachment = message.attachment, attachment.kind == .image {
            if let data = Data(base64Encoded: attachment.dataBase64) {
                return UIImage(data: data)
            }
        }
        
        // 如果 MessageFileItem 本身有 attachment，也尝试（回退方案）
        if let attachment = item.attachment, attachment.kind == .image {
            if let data = Data(base64Encoded: attachment.dataBase64) {
                return UIImage(data: data)
            }
        }
        
        return nil
    }
    
    /// 打开图片画册
    private func openImageGallery(at index: Int) {
        guard fileType == .image else { return }
        
        // 如果图片数据还没准备好，尝试实时加载
        if galleryImages.isEmpty || galleryImages.count != files.count {
            prepareGalleryImages(from: files)
            // 延迟打开，等待图片加载
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                if !galleryImages.isEmpty {
                    let actualIndex = min(index, galleryImages.count - 1)
                    selectedImageIndex = actualIndex >= 0 ? actualIndex : 0
                }
            }
        } else {
            selectedImageIndex = min(index, galleryImages.count - 1)
        }
    }
}

/// 文件项行视图
private struct MessageFileRow: View {
    let item: MessageFileItem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 文件图标
                Image(systemName: iconName)
                    .font(.system(size: 24))
                    .foregroundStyle(iconColor)
                    .frame(width: 40, height: 40)
                    .background(iconColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayName.prefix(50))
                        .font(.system(size: 16, weight: .medium))
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        if let channelName = item.channelName {
                            Text(channelName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Text(formatTime(item.createdAt))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        
                        Spacer()
                        
                        Text(formatSize(item.size))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
    
    private var iconName: String {
        switch item.fileType {
        case .text: return "text.bubble"
        case .image: return "photo"
        case .video: return "video"
        case .voice: return "waveform"
        case .other: return "doc"
        }
    }
    
    private var iconColor: Color {
        switch item.fileType {
        case .text: return .blue
        case .image: return .orange
        case .video: return .purple
        case .voice: return .green
        case .other: return .gray
        }
    }
    
    private func formatSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    private func formatTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            formatter.locale = Locale(identifier: "zh_CN")
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "昨天"
        } else if calendar.dateInterval(of: .weekOfYear, for: now)?.contains(date) ?? false {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE HH:mm"
            formatter.locale = Locale(identifier: "zh_CN")
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M月d日 HH:mm"
            formatter.locale = Locale(identifier: "zh_CN")
            return formatter.string(from: date)
        }
    }
}

struct MessageFileListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            MessageFileListView(
                fileType: .image,
                channelManager: ChannelManager(
                    central: BluetoothCentralManager(),
                    peripheral: BluetoothPeripheralManager(),
                    selfPeer: Peer(nickname: "测试")
                )
            )
        }
    }
}

