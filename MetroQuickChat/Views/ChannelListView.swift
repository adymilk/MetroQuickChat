import SwiftUI
import Combine

@MainActor
struct ChannelListView: View {
    @StateObject private var viewModel: ChannelListViewModel
    @State private var pushToChat: Channel? = nil
    @State private var isScanning: Bool = true
    @State private var showCreateChannel: Bool = false
    @State private var isNavigating = false // 防止重复导航

    init(nickname: String, sharedManager: ChannelManager? = nil) {
        let manager = sharedManager ?? ChannelManager(
            central: BluetoothCentralManager(),
            peripheral: BluetoothPeripheralManager(),
            selfPeer: Peer(nickname: nickname)
        )
        _viewModel = StateObject(wrappedValue: ChannelListViewModel(
            channelManager: manager,
            defaultNickname: nickname)
        )
    }

    var body: some View {
        Group {
            if viewModel.channels.isEmpty {
                VStack(spacing: 20) {
                    if isScanning {
                        ProgressView()
                        Text("正在扫描附近频道…")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("请确保蓝牙和定位权限已开启")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 50))
                            .foregroundStyle(.secondary)
                        Text("未发现附近频道")
                            .font(.headline)
                        Text("点击右上角刷新按钮重新扫描")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button(action: {
                            isScanning = true
                            viewModel.channelManager.startDiscovery()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                isScanning = false
                            }
                        }) {
                            Label("重新扫描", systemImage: "arrow.clockwise")
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
                .padding(.horizontal)
            } else {
                List {
                    ForEach(viewModel.channels) { channel in
                        ChannelRowView(
                            channel: channel,
                            channelManager: viewModel.channelManager,
                            isFavorite: viewModel.isFavorite(channelId: channel.id),
                            onTap: {
                                guard !isNavigating else { return }
                                isNavigating = true
                                Haptics.light()
                                viewModel.join(channel: channel)
                                // 延迟重置，防止重复点击
                                Task {
                                    try? await Task.sleep(nanoseconds: 500_000_000)
                                    isNavigating = false
                                }
                            },
                            onFavoriteToggle: {
                                viewModel.toggleFavorite(channel: channel)
                            }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.visible)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            FloatingActionButton(action: { 
                showCreateChannel = true
                Haptics.light()
            }) { 
                Image(systemName: "plus") 
            }
            .padding()
        }
        .navigationDestination(isPresented: $showCreateChannel) {
            ChannelCreateView(nickname: viewModel.nickname, existingManager: viewModel.channelManager)
        }
        .navigationTitle("频道列表")
        .onReceive(viewModel.didJoinChannel) { channel in
            // 防止重复导航：只有在未导航时才设置
            if pushToChat == nil {
                pushToChat = channel
            }
        }
        .navigationDestination(item: $pushToChat) { channel in
            ChatView(channel: channel, channelManager: viewModel.channelManager)
                .onAppear {
                    isNavigating = false
                }
                .onDisappear {
                    // 离开聊天页面时清空导航状态
                    pushToChat = nil
                    isNavigating = false
                }
        }
        .toast(isPresented: $viewModel.showFavoriteToast, text: viewModel.favoriteToastText ?? "")
        .onReceive(viewModel.channelManager.events) { event in
            // 监听新频道发现事件，触发震动和提示
            if case .channelDiscovered(let channel) = event {
                Haptics.success()
                NotificationService.shared.notifyChannelDiscovered(channel)
                print("ChannelListView: 发现新频道 - \(channel.name)")
            }
        }
        .onAppear {
            isScanning = true
            viewModel.channelManager.startDiscovery()
            // 持续扫描，不要3秒后停止
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                // 扫描指示器显示1秒后隐藏，但扫描继续
                if viewModel.channels.isEmpty {
                    isScanning = false
                }
            }
        }
        .onDisappear {
            viewModel.channelManager.stopDiscovery()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    NavigationLink(destination: FavoriteChannelsView(nickname: viewModel.nickname, channelManager: viewModel.channelManager)) {
                        Image(systemName: "star.fill")
                    }
                    NavigationLink(destination: RadarScanView(nickname: viewModel.nickname, channelManager: viewModel.channelManager)) {
                        Image(systemName: "scope")
                    }
                    Button(action: { isScanning = true; viewModel.channelManager.startDiscovery();
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { isScanning = false } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }
}

struct ChannelListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { ChannelListView(nickname: "测试用户") }
            .preferredColorScheme(.dark)
        NavigationStack { ChannelListView(nickname: "测试用户") }
            .preferredColorScheme(.light)
            .previewDevice("iPad (10th generation)")
    }
}


