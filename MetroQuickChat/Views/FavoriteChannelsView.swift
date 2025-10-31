import SwiftUI

@MainActor
struct FavoriteChannelsView: View {
    let nickname: String
    @ObservedObject var channelManager: ChannelManager
    @State private var favoriteChannels: [Channel] = []
    @State private var pushToChat: Channel? = nil
    @State private var showEmptyState = false
    @State private var isNavigating = false // 防止重复导航
    
    var body: some View {
        Group {
            if favoriteChannels.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "star")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                    Text("暂无收藏频道")
                        .font(.headline)
                    Text("长按频道卡片可以收藏频道")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                List {
                    ForEach(favoriteChannels) { channel in
                        ChannelRowView(
                            channel: channel,
                            channelManager: channelManager,
                            isFavorite: true,
                            onTap: {
                                guard !isNavigating else { return }
                                isNavigating = true
                                Haptics.light()
                                // 延迟导航，确保 joinChannel 完成
                                Task { @MainActor in
                                    channelManager.joinChannel(channel)
                                    // 等待一小段时间确保状态更新
                                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
                                    pushToChat = channel
                                    // 重置标志，允许下次导航
                                    isNavigating = false
                                }
                            },
                            onFavoriteToggle: {
                                channelManager.unfavoriteChannel(channelId: channel.id)
                                loadFavorites()
                            }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.visible)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteFavorite(channel)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                channelManager.unfavoriteChannel(channelId: channel.id)
                                loadFavorites()
                                Haptics.success()
                            } label: {
                                Label("取消收藏", systemImage: "star.slash")
                            }
                            .tint(.orange)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("收藏频道")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $pushToChat) { channel in
            ChatView(channel: channel, channelManager: channelManager)
                .onAppear {
                    // 进入 ChatView 后重置导航标志
                    isNavigating = false
                }
                .onDisappear {
                    // 离开 ChatView 时清空 pushToChat，防止重复导航
                    pushToChat = nil
                }
        }
        .onAppear {
            loadFavorites()
            // 开始扫描，以便更新收藏频道的在线状态
            channelManager.startDiscovery()
        }
        .onDisappear {
            channelManager.stopDiscovery()
        }
        .onChange(of: channelManager.channels) { oldChannels, newChannels in
            // 当扫描到新频道时，更新收藏频道的在线状态
            updateFavoriteChannelsStatus(with: newChannels)
            // 只在未手动导航时自动尝试加入收藏频道
            if !isNavigating && pushToChat == nil {
                channelManager.autoJoinFavoriteChannels()
            }
        }
        .refreshable {
            loadFavorites()
            channelManager.startDiscovery()
        }
    }
    
    private func loadFavorites() {
        favoriteChannels = channelManager.loadFavoriteChannels()
        showEmptyState = favoriteChannels.isEmpty
    }
    
    private func updateFavoriteChannelsStatus(with discoveredChannels: [Channel]) {
        // 更新收藏频道的在线状态和最后发现时间
        for i in 0..<favoriteChannels.count {
            if let discovered = discoveredChannels.first(where: { $0.id == favoriteChannels[i].id }) {
                favoriteChannels[i].lastDiscoveredAt = discovered.lastDiscoveredAt
                favoriteChannels[i].name = discovered.name // 更新名称（如果变化）
            }
        }
    }
    
    private func deleteFavorite(_ channel: Channel) {
        Haptics.warning()
        // 取消收藏并删除数据
        channelManager.unfavoriteChannel(channelId: channel.id)
        // 删除频道的所有消息数据（如果不在当前频道中）
        if channelManager.currentChannel?.id != channel.id {
            channelManager.store.clearChannelMessages(channelId: channel.id)
        }
        // 重新加载收藏列表
        loadFavorites()
        Haptics.success()
    }
}


struct FavoriteChannelsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            FavoriteChannelsView(
                nickname: "测试用户",
                channelManager: ChannelManager(
                    central: BluetoothCentralManager(),
                    peripheral: BluetoothPeripheralManager(),
                    selfPeer: Peer(nickname: "测试用户")
                )
            )
        }
    }
}

