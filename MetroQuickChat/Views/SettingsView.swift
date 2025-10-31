import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var channelManager: ChannelManager
    @State private var storageAnalysis: StorageAnalysis?
    @State private var isAnalyzing = false
    @State private var showClearAlert = false
    @State private var clearAction: ClearAction?
    @State private var selectedFileType: MessageFileItem.FileType?
    
    enum ClearAction {
        case messages
        case all
    }
    
    var body: some View {
        List {
            // 存储概览
            Section {
                if isAnalyzing {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("正在分析存储...")
                            .foregroundStyle(.secondary)
                    }
                } else if let analysis = storageAnalysis {
                    StorageOverviewSection(analysis: analysis)
                } else {
                    Button("分析存储空间") {
                        analyzeStorage()
                    }
                }
            } header: {
                Text("存储空间")
            } footer: {
                Text("已加入的频道和聊天记录会永久保存在本地")
            }
            
            // 设备存储信息
            if let analysis = storageAnalysis, analysis.deviceTotalSpace > 0 {
                Section {
                    DeviceStorageInfoView(analysis: analysis)
                } header: {
                    Text("设备存储")
                }
            }
            
            // 存储详情（应用内数据分类，支持点击查看文件列表）
            if let analysis = storageAnalysis {
                Section {
                    StorageBreakdownView(
                        analysis: analysis,
                        channelManager: channelManager,
                        selectedFileType: $selectedFileType
                    )
                } header: {
                    Text("应用数据详情")
                } footer: {
                    Text("点击项目可查看详细文件列表")
                }
                
                // 统计信息
                Section {
                    HStack {
                        Text("频道数量")
                        Spacer()
                        Text("\(analysis.channelCount)")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("消息总数")
                        Spacer()
                        Text("\(analysis.messageCount)")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("文字消息")
                        Spacer()
                        Text("\(analysis.textMessageCount)")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("图片消息")
                        Spacer()
                        Text("\(analysis.imageMessageCount)")
                            .foregroundStyle(.secondary)
                    }
                    
                    if analysis.videoMessageCount > 0 {
                        HStack {
                            Text("视频消息")
                            Spacer()
                            Text("\(analysis.videoMessageCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if analysis.voiceMessageCount > 0 {
                        HStack {
                            Text("语音消息")
                            Spacer()
                            Text("\(analysis.voiceMessageCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // 系统消息数量（总消息数减去所有类型消息数）
                    let systemMessageCount = analysis.messageCount - analysis.textMessageCount - analysis.imageMessageCount - analysis.videoMessageCount - analysis.voiceMessageCount
                    if systemMessageCount > 0 {
                        HStack {
                            Text("系统消息")
                            Spacer()
                            Text("\(systemMessageCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("统计信息")
                }
            }
            
            // 清理选项
            Section {
                Button(role: .destructive) {
                    clearAction = .messages
                    showClearAlert = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("清理所有消息")
                    }
                }
                
                Button(role: .destructive) {
                    clearAction = .all
                    showClearAlert = true
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("清理所有数据")
                    }
                }
            } header: {
                Text("数据清理")
            } footer: {
                Text("清理操作无法恢复，请谨慎操作")
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            analyzeStorage()
        }
        .onAppear {
            // 每次进入页面都重新分析（实时数据）
            analyzeStorage()
        }
        .navigationDestination(item: $selectedFileType) { fileType in
            MessageFileListView(fileType: fileType, channelManager: channelManager)
        }
        .alert("确认清理", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) { }
            Button("确认", role: .destructive) {
                performClear()
            }
        } message: {
            if clearAction == .messages {
                Text("将删除所有聊天消息，但保留频道记录。此操作无法恢复。")
            } else {
                Text("将删除所有数据，包括消息、频道记录和收藏列表。此操作无法恢复。")
            }
        }
    }
    
    private func analyzeStorage() {
        isAnalyzing = true
        storageAnalysis = nil // 清空旧数据，显示加载状态
        
        Task { @MainActor in
            // 在后台队列执行分析（避免阻塞 UI）
            let analysis = await Task.detached { [store = channelManager.store] in
                return store.analyzeStorage()
            }.value
            
            storageAnalysis = analysis
            isAnalyzing = false
        }
    }
    
    private func performClear() {
        guard let action = clearAction else { return }
        Haptics.warning()
        
        if action == .messages {
            channelManager.store.clearAllMessages()
        } else {
            channelManager.store.clearAllData()
        }
        
        // 重新分析
        analyzeStorage()
        clearAction = nil
    }
}

// MARK: - Storage Overview Section

private struct StorageOverviewSection: View {
    let analysis: StorageAnalysis
    @State private var animatedPercentage: Double = 0.0
    @State private var animatedTotalSize: Int64 = 0
    
    var body: some View {
        VStack(spacing: 20) {
            // 占用手机存储百分比（大号显示，带动画）
            VStack(spacing: 12) {
                Text("\(animatedPercentageText)%")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText(value: animatedPercentage * 100))
                
                Text("占用手机存储")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                // 应用占用大小
                Text("应用占用：\(animatedFormattedSize)")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            
            // 存储百分比环形图
            StoragePercentageChartView(
                percentage: animatedPercentage,
                appSize: animatedTotalSize,
                deviceTotalSpace: analysis.deviceTotalSpace
            )
            .frame(height: 220)
            .padding(.vertical, 8)
        }
        .padding(.vertical, 8)
        .onAppear {
            // 启动动画
            withAnimation(.spring(response: 1.0, dampingFraction: 0.8)) {
                animatedPercentage = analysis.storagePercentage
                animatedTotalSize = analysis.totalSize
            }
        }
    }
    
    private var animatedPercentageText: String {
        String(format: "%.2f", animatedPercentage * 100)
    }
    
    private var animatedFormattedSize: String {
        DeviceStorageInfo.formattedSize(animatedTotalSize)
    }
}

// MARK: - Storage Percentage Chart View

private struct StoragePercentageChartView: View {
    let percentage: Double
    let appSize: Int64
    let deviceTotalSpace: Int64
    
    @State private var animatedProgress: Double = 0.0
    
    var body: some View {
        ZStack {
            // 背景圆环（灰色）
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 24)
            
            // 应用占用部分（蓝色渐变，带动画）
            if percentage > 0 {
                Circle()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.blue,
                                Color.blue.opacity(0.7),
                                Color.cyan.opacity(0.6)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 24, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .blue.opacity(0.3), radius: 8)
            }
        }
        .overlay {
            // 中心文字（带动画）
            VStack(spacing: 8) {
                Text("\(animatedPercentageText)%")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText(value: animatedProgress * 100))
                
                Text("手机存储")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // 设备总存储空间
                if deviceTotalSpace > 0 {
                    Text("总容量：\(DeviceStorageInfo.formattedSize(deviceTotalSpace))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .opacity(animatedProgress > 0 ? 1.0 : 0.0)
            .animation(.easeIn(duration: 0.3), value: animatedProgress)
        }
        .onAppear {
            // 启动动画
            withAnimation(.spring(response: 1.2, dampingFraction: 0.75)) {
                animatedProgress = percentage
            }
        }
    }
    
    private var animatedPercentageText: String {
        String(format: "%.2f", animatedProgress * 100)
    }
}

// MARK: - Device Storage Info View

private struct DeviceStorageInfoView: View {
    let analysis: StorageAnalysis
    @State private var animatedUsedPercentage: Double = 0.0
    
    var body: some View {
        VStack(spacing: 16) {
            // 设备总存储
            HStack {
                Text("设备总容量")
                    .font(.body)
                Spacer()
                Text(DeviceStorageInfo.formattedSize(analysis.deviceTotalSpace))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            
            // 设备已用空间
            HStack {
                Text("设备已用")
                    .font(.body)
                Spacer()
                Text(DeviceStorageInfo.formattedSize(analysis.deviceUsedSpace))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            
            // 设备可用空间
            let availableSpace = analysis.deviceTotalSpace - analysis.deviceUsedSpace
            HStack {
                Text("设备可用")
                    .font(.body)
                Spacer()
                Text(DeviceStorageInfo.formattedSize(availableSpace))
                    .font(.body)
                    .foregroundStyle(.green)
            }
            
            Divider()
            
            // 应用占用空间
            HStack {
                Text("应用占用")
                    .font(.body)
                    .fontWeight(.medium)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(DeviceStorageInfo.formattedSize(analysis.totalSize))
                        .font(.body)
                        .foregroundStyle(.blue)
                    Text("占设备 \(String(format: "%.2f", analysis.storagePercentage * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            let deviceUsedPercentage = analysis.deviceTotalSpace > 0 ? 
                Double(analysis.deviceUsedSpace) / Double(analysis.deviceTotalSpace) : 0.0
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                animatedUsedPercentage = deviceUsedPercentage
            }
        }
    }
}

// MARK: - Storage Breakdown View

private struct StorageBreakdownView: View {
    let analysis: StorageAnalysis
    let channelManager: ChannelManager
    @Binding var selectedFileType: MessageFileItem.FileType?
    
    var body: some View {
        if analysis.totalSize > 0 {
            // 文字消息
            if analysis.textSize > 0 {
                StorageItemRow(
                    title: "文字消息",
                    size: analysis.textSize,
                    percentage: analysis.textPercentage,
                    color: .blue,
                    icon: "text.bubble",
                    count: analysis.textMessageCount
                ) {
                    selectedFileType = .text
                }
            }
            
            // 图片
            if analysis.imageSize > 0 {
                StorageItemRow(
                    title: "图片",
                    size: analysis.imageSize,
                    percentage: analysis.imagePercentage,
                    color: .orange,
                    icon: "photo",
                    count: analysis.imageMessageCount
                ) {
                    selectedFileType = .image
                }
            }
            
            // 视频
            if analysis.videoSize > 0 {
                StorageItemRow(
                    title: "视频",
                    size: analysis.videoSize,
                    percentage: analysis.videoPercentage,
                    color: .purple,
                    icon: "video",
                    count: analysis.videoMessageCount
                ) {
                    selectedFileType = .video
                }
            }
            
            // 语音
            if analysis.voiceSize > 0 {
                StorageItemRow(
                    title: "语音",
                    size: analysis.voiceSize,
                    percentage: analysis.voicePercentage,
                    color: .green,
                    icon: "waveform",
                    count: analysis.voiceMessageCount
                ) {
                    selectedFileType = .voice
                }
            }
            
            // 其他
            if analysis.otherSize > 0 {
                StorageItemRow(
                    title: "其他",
                    size: analysis.otherSize,
                    percentage: analysis.otherPercentage,
                    color: .gray,
                    icon: "doc",
                    count: 0
                ) {
                    selectedFileType = .other
                }
            }
        } else {
            Text("暂无存储数据")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Storage Item Row

private struct StorageItemRow: View {
    let title: String
    let size: Int64
    let percentage: Double
    let color: Color
    let icon: String
    let count: Int
    let onTap: () -> Void
    
    @State private var animatedPercentage: Double = 0.0
    @State private var animatedSize: Int64 = 0
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 图标
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .font(.system(size: 16, weight: .medium))
                        
                        if count > 0 {
                            Text("(\(count))")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Text(formatSize(animatedSize))
                                .font(.system(size: 15, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText(value: Double(animatedSize)))
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    // 进度条（带动画）
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(.systemGray5))
                                .frame(height: 4)
                            
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color)
                                .frame(width: geometry.size.width * CGFloat(animatedPercentage), height: 4)
                        }
                    }
                    .frame(height: 4)
                    
                    Text("\(Int(animatedPercentage * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: Double(Int(animatedPercentage * 100))))
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .onAppear {
            // 启动动画
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                animatedPercentage = percentage
                animatedSize = size
            }
        }
    }
    
    private func formatSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SettingsView(channelManager: ChannelManager(
                central: BluetoothCentralManager(),
                peripheral: BluetoothPeripheralManager(),
                selfPeer: Peer(nickname: "测试用户")
            ))
        }
    }
}
