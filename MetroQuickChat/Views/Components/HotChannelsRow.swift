import SwiftUI

struct HotChannelsRow: View {
    @ObservedObject var channelManager: ChannelManager
    let nickname: String
    @State private var pushToChat: Channel? = nil
    @State private var isNavigating = false // 防止重复导航
    @State private var favoriteToastText: String? = nil
    @State private var showFavoriteToast: Bool = false
    
    init(nickname: String, sharedManager: ChannelManager) {
        self.channelManager = sharedManager
        self.nickname = nickname
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("热门频道")
                    .font(.headline)
                    .padding(.horizontal, 16)
                Spacer()
            }
            
            if hotChannels.isEmpty {
                // 空状态提示
                VStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("暂无附近频道")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("请开启蓝牙和定位权限，等待附近频道出现")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                List {
                    ForEach(hotChannels) { channel in
                        ChannelRowView(
                            channel: channel,
                            channelManager: channelManager,
                            isFavorite: channelManager.isFavoriteChannel(channelId: channel.id),
                            onTap: {
                                guard !isNavigating else { return }
                                isNavigating = true
                                Haptics.light()
                                channelManager.joinChannel(channel)
                                // 延迟重置，防止重复点击
                                Task {
                                    try? await Task.sleep(nanoseconds: 500_000_000)
                                    isNavigating = false
                                }
                            },
                            onFavoriteToggle: {
                                toggleFavorite(channel: channel)
                            }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.visible)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(height: CGFloat(min(hotChannels.count, 5)) * 66) // 每行约66点高度，最多显示5行
            }
        }
        .onAppear { 
            channelManager.startDiscovery() 
        }
        .onReceive(channelManager.events) { event in
            if case .joined(let channel, _) = event {
                // 防止重复导航
                if pushToChat == nil {
                    pushToChat = channel
                }
            }
        }
        .navigationDestination(item: $pushToChat) { channel in
            ChatView(channel: channel, channelManager: channelManager)
                .onAppear {
                    isNavigating = false
                }
                .onDisappear {
                    pushToChat = nil
                    isNavigating = false
                }
        }
        .toast(isPresented: $showFavoriteToast, text: favoriteToastText ?? "")
    }

    /// 真实的热门频道排序逻辑
    private var hotChannels: [Channel] {
        let channels = channelManager.channels
        
        // 如果没有频道，返回空数组
        guard !channels.isEmpty else {
            return []
        }
        
        // 计算每个频道的热度分数并排序
        let scoredChannels = channels.map { channel -> (channel: Channel, score: Double) in
            var score: Double = 0.0
            
            // 1. 在线状态（权重：50%）
            if channel.isOnline {
                score += 50.0
            } else {
                // 根据最后发现时间计算衰减分数
                if let lastDiscovered = channel.lastDiscoveredAt {
                    let minutesSince = Date().timeIntervalSince(lastDiscovered) / 60.0
                    // 5分钟内：40分，10分钟内：20分，30分钟内：10分，超过30分钟：0分
                    if minutesSince < 5 {
                        score += 40.0
                    } else if minutesSince < 10 {
                        score += 20.0
                    } else if minutesSince < 30 {
                        score += 10.0
                    }
                }
            }
            
            // 2. 消息数量（活跃度，权重：30%）
            let messages = channelManager.store.loadMessages(channelId: channel.id)
            let messageCount = messages.count
            // 消息数转化为0-30分（最多100条消息得满分）
            score += min(Double(messageCount) / 100.0 * 30.0, 30.0)
            
            // 3. 最近发现时间（权重：20%）
            if let lastDiscovered = channel.lastDiscoveredAt {
                let secondsSince = Date().timeIntervalSince(lastDiscovered)
                // 30秒内：20分，1分钟内：15分，5分钟内：10分，超过5分钟：5分
                if secondsSince < 30 {
                    score += 20.0
                } else if secondsSince < 60 {
                    score += 15.0
                } else if secondsSince < 300 {
                    score += 10.0
                } else {
                    score += 5.0
                }
            }
            
            return (channel: channel, score: score)
        }
        
        // 按分数降序排序，取前8个
        return scoredChannels
            .sorted { $0.score > $1.score }
            .prefix(8)
            .map { $0.channel }
    }
    
    private func toggleFavorite(channel: Channel) {
        if channelManager.isFavoriteChannel(channelId: channel.id) {
            channelManager.unfavoriteChannel(channelId: channel.id)
            favoriteToastText = "已取消收藏"
            showFavoriteToast = true
            Haptics.light()
        } else {
            channelManager.favoriteChannel(channel)
            favoriteToastText = "已收藏"
            showFavoriteToast = true
            Haptics.success()
        }
        // 自动隐藏 toast
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            await MainActor.run {
                showFavoriteToast = false
            }
        }
    }
}

struct HotChannelsRow_Previews: PreviewProvider {
    static var previews: some View {
        let manager = ChannelManager(
            central: BluetoothCentralManager(),
            peripheral: BluetoothPeripheralManager(),
            selfPeer: Peer(nickname: "预览")
        )
        HotChannelsRow(nickname: "预览", sharedManager: manager)
            .padding()
            .preferredColorScheme(.dark)
    }
}


