import Foundation
import Combine

@MainActor
final class ChannelListViewModel: ObservableObject {
    @Published var channels: [Channel] = []
    @Published var nickname: String
    @Published var errorMessage: String? = nil

    let didJoinChannel = PassthroughSubject<Channel, Never>()

    let channelManager: ChannelManager
    private var cancellables: Set<AnyCancellable> = []

    init(channelManager: ChannelManager, defaultNickname: String) {
        self.channelManager = channelManager
        self.nickname = defaultNickname
        // 如果 manager 中已有频道，使用它们；否则添加示例频道
        if channelManager.channels.isEmpty {
            addDemoChannel()
        } else {
            channels = channelManager.channels
        }
        bind()
    }
    
    private func addDemoChannel() {
        let demoChannel = Channel(
            name: RandomChannelName.generate(),
            hostPeerId: UUID(),
            createdAt: Date()
        )
        channels = [demoChannel]
    }

    private func bind() {
        // 监听频道更新事件
        channelManager.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self = self else { return }
                switch event {
                case .channelsUpdated(let channels):
                    // 优先使用真实扫描到的频道
                    if !channels.isEmpty {
                        self.channels = channels
                    } else if self.channels.isEmpty {
                        // 只有在完全没有频道时才添加示例频道
                        self.addDemoChannel()
                    }
                case .joined(let channel, _):
                    self.didJoinChannel.send(channel)
                case .error(let message):
                    self.errorMessage = message
                    print("ChannelListViewModel Error: \(message)")
                default:
                    break
                }
            }
            .store(in: &cancellables)
        
        // 同时监听 Published 的 channels（实时更新）
        channelManager.$channels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] channels in
                guard let self = self else { return }
                // 直接使用 channelManager 的真实频道列表
                // 如果为空且当前也没有频道，才添加示例频道
                if !channels.isEmpty {
                    self.channels = channels
                } else if self.channels.isEmpty {
                    self.addDemoChannel()
                }
            }
            .store(in: &cancellables)
    }

    func createChannel(name: String) {
        channelManager.createChannel(name: name)
    }

    func join(channel: Channel) {
        channelManager.joinChannel(channel)
    }

    func updateNickname(_ newValue: String) {
        nickname = newValue
        UserDefaults.standard.set(newValue, forKey: "nickname")
    }
    
    // MARK: - Favorite Channels
    
    @Published var favoriteToastText: String? = nil
    @Published var showFavoriteToast: Bool = false
    
    func toggleFavorite(channel: Channel) {
        if channelManager.isFavoriteChannel(channelId: channel.id) {
            channelManager.unfavoriteChannel(channelId: channel.id)
            favoriteToastText = "已取消收藏"
            showFavoriteToast = true
            Haptics.light()
            // 自动隐藏 toast
            Task {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                await MainActor.run {
                    showFavoriteToast = false
                }
            }
        } else {
            channelManager.favoriteChannel(channel)
            favoriteToastText = "已收藏"
            showFavoriteToast = true
            Haptics.success()
            // 自动隐藏 toast
            Task {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                await MainActor.run {
                    showFavoriteToast = false
                }
            }
        }
    }
    
    func isFavorite(channelId: UUID) -> Bool {
        return channelManager.isFavoriteChannel(channelId: channelId)
    }
}


