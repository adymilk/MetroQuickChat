import SwiftUI

struct HotChannelsRow: View {
    @StateObject private var vm: ChannelListViewModel
    @State private var pushToChat: Channel? = nil
    @State private var isNavigating = false // 防止重复导航

    init(nickname: String, sharedManager: ChannelManager? = nil) {
        let manager = sharedManager ?? ChannelManager(central: BluetoothCentralManager(), peripheral: BluetoothPeripheralManager(), selfPeer: Peer(nickname: nickname))
        _vm = StateObject(wrappedValue: ChannelListViewModel(channelManager: manager, defaultNickname: nickname))
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
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                List {
                    ForEach(hotChannels) { channel in
                        ChannelRowView(
                            channel: channel,
                            channelManager: vm.channelManager,
                            isFavorite: vm.isFavorite(channelId: channel.id),
                            onTap: {
                                guard !isNavigating else { return }
                                isNavigating = true
                                Haptics.light()
                                vm.join(channel: channel)
                                // 延迟重置，防止重复点击
                                Task {
                                    try? await Task.sleep(nanoseconds: 500_000_000)
                                    isNavigating = false
                                }
                            },
                            onFavoriteToggle: {
                                vm.toggleFavorite(channel: channel)
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
            vm.channelManager.startDiscovery() 
        }
        .onReceive(vm.didJoinChannel) { channel in
            // 防止重复导航
            if pushToChat == nil {
                pushToChat = channel
            }
        }
        .navigationDestination(item: $pushToChat) { channel in
            ChatView(channel: channel, channelManager: vm.channelManager)
                .onAppear {
                    isNavigating = false
                }
                .onDisappear {
                    pushToChat = nil
                    isNavigating = false
                }
        }
        .toast(isPresented: $vm.showFavoriteToast, text: vm.favoriteToastText ?? "")
    }

    private var hotChannels: [Channel] {
        Array(vm.channels.prefix(8))
    }
}

struct HotChannelsRow_Previews: PreviewProvider {
    static var previews: some View {
        HotChannelsRow(nickname: "预览")
            .padding()
            .preferredColorScheme(.dark)
    }
}


