import Foundation
import Combine
import CoreLocation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var errorMessage: String? = nil
    @Published var peers: [Peer] = []
    var isHost: Bool { peers.first(where: { $0.isHost })?.id == selfPeerId }
    @Published var didExitChannel: Bool = false

    let channelManager: ChannelManager
    let channel: Channel
    private var cancellables: Set<AnyCancellable> = []
    let selfPeerId: UUID
    let locationProvider = LocationProvider()
    let voiceService = VoiceRecordingService()
    
    // Currently playing voice message ID
    @Published var playingVoiceId: UUID? = nil

    init(channelManager: ChannelManager, channel: Channel) {
        self.channelManager = channelManager
        self.channel = channel
        self.selfPeerId = channelManager.selfPeerId
        bind()
        setupVoiceService()
        // Load local history
        let history = channelManager.loadHistory(channelId: channel.id)
        if history.isEmpty == false { self.messages = history }
        // 注意：实际的加入消息会在 ChannelManager.joinChannel() 中发送
        // 这里只在首次加载历史消息时显示本地欢迎消息
        if history.isEmpty {
            sendSystem("欢迎 \(channelManager.selfPeer.nickname) 加入 \(channel.name)")
        }
    }
    
    // MARK: - Preview Mode Initializer
    init(channel: Channel, previewMessages: [Message], previewPeers: [Peer] = []) {
        // Create a dummy channel manager for preview
        let dummyPeer = Peer(nickname: "我")
        let dummyManager = ChannelManager(
            central: BluetoothCentralManager(),
            peripheral: BluetoothPeripheralManager(),
            selfPeer: dummyPeer
        )
        self.channelManager = dummyManager
        self.channel = channel
        self.selfPeerId = dummyPeer.id
        self.messages = previewMessages
        self.peers = previewPeers.isEmpty ? [
            Peer(nickname: "Alice", isHost: false),
            Peer(nickname: "Bob", isHost: false),
            Peer(nickname: "Charlie", isHost: false)
        ] : previewPeers
        bind()
        setupVoiceService()
    }
    
    private func setupVoiceService() {
        voiceService.onRecordingComplete = { [weak self] data, duration in
            guard let self = self else { return }
            self.channelManager.sendVoice(data, duration: duration)
            Haptics.light()
        }
        voiceService.onRecordingCancelled = {
            Haptics.warning()
        }
    }

    private func bind() {
        channelManager.events
            .sink { [weak self] event in
                guard let self else { return }
                switch event {
                case .message(let message) where message.channelId == self.channel.id:
                    self.messages.append(message)
                case .peersUpdated(let peers):
                    self.peers = peers
                case .joined(let channel, let peer) where channel.id == self.channel.id:
                    if self.peers.contains(where: { $0.id == peer.id }) == false { self.peers.append(peer) }
                case .left(let channel, let peer) where channel.id == self.channel.id:
                    self.peers.removeAll { $0.id == peer.id }
                    // 只有真正是当前用户主动离开或被踢出时才触发退出
                    // 注意：切换到另一个频道时不会发送 .left 事件，所以这里只处理真正的离开
                    if peer.id == self.selfPeerId {
                        // 延迟检查，确保 ChannelManager 状态已更新
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms，给足够时间让状态稳定
                            // 再次确认：只有当 currentChannel 确实不是当前频道，且没有加入新频道时才退出
                            let currentChannelId = self.channelManager.currentChannel?.id
                            if currentChannelId != channel.id {
                                // 再等待一小段时间，确保不是临时的状态波动
                                try? await Task.sleep(nanoseconds: 300_000_000)
                                // 最终确认：如果 currentChannel 仍然是 nil 或不是当前频道，才真正退出
                                // 如果 currentChannel 是另一个频道，说明用户切换了频道，不需要退出当前视图（会由导航栈处理）
                                let finalChannelId = self.channelManager.currentChannel?.id
                                if finalChannelId != channel.id && finalChannelId == nil {
                                    // 只有当前没有在任何一个频道时，才退出
                                    self.didExitChannel = true
                                }
                            }
                        }
                    }
                case .kicked(let channel, let peer) where channel.id == self.channel.id:
                    self.peers.removeAll { $0.id == peer.id }
                case .error(let message):
                    self.errorMessage = message
                case .dissolved(let channel) where channel.id == self.channel.id:
                    self.didExitChannel = true
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    func send() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        sendText(trimmed)
        inputText = ""
    }
    
    // MARK: - New Message Type Methods
    
    func sendText(_ text: String) {
        channelManager.sendChat(text)
        Haptics.light()
    }
    
    func sendEmoji(_ emoji: String) {
        let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        channelManager.sendChat(trimmed) // Reuse sendChat for emoji
        Haptics.light()
    }
    
    func sendImage(_ data: Data) {
        channelManager.sendImage(data)
        Haptics.light()
    }
    
    func sendVoice(_ data: Data, duration: Int) {
        channelManager.sendVoice(data, duration: duration)
        Haptics.light()
    }
    
    func startVoiceRecord() {
        voiceService.startRecording()
        Haptics.light()
    }
    
    func stopVoiceRecord() {
        voiceService.stopRecording()
    }
    
    func cancelVoiceRecord() {
        voiceService.cancelRecording()
    }
    
    func playVoice(message: Message) {
        guard case .voice(let data, _) = message.messageType else { return }
        
        // Stop current playback if different message
        if playingVoiceId != message.id {
            voiceService.stopPlayback()
            playingVoiceId = message.id
            voiceService.playVoice(data: data)
        } else {
            // Toggle playback
            if voiceService.isPlaying {
                voiceService.stopPlayback()
                playingVoiceId = nil
            } else {
                playingVoiceId = message.id
                voiceService.playVoice(data: data)
            }
        }
    }
    
    func stopVoicePlayback() {
        voiceService.stopPlayback()
        playingVoiceId = nil
    }
    
    func deleteMessage(_ message: Message) {
        guard message.isOutgoing else { return }
        channelManager.deleteMessage(messageId: message.id)
        messages.removeAll { $0.id == message.id }
        Haptics.light()
    }

    func leave() {
        channelManager.leaveChannel()
    }

    func kick(_ peerId: UUID) {
        channelManager.kick(peerId: peerId)
    }

    func dissolve() {
        channelManager.dissolveChannel()
    }
    
    func updateChannelName(_ newName: String) {
        channelManager.updateChannelName(newName)
    }
    
    func getHostPeer() -> Peer? {
        channelManager.getHostPeer()
    }
    
    var hostNickname: String {
        getHostPeer()?.nickname ?? "未知"
    }

    private func sendSystem(_ text: String) {
        let message = Message(channelId: channel.id, author: .system, nickname: "系统", text: text)
        messages.append(message)
    }

    // MARK: - Media send proxies (legacy)
    func sendVideoThumbnail(_ thumb: Data) {
        channelManager.sendVideoThumbnail(thumb)
    }

    // MARK: - Distance & Bearing
    func distanceText(for peer: Peer) -> String? {
        guard let plat = peer.latitude, let plon = peer.longitude, let loc = locationProvider.location else { return nil }
        let peerLocation = CLLocation(latitude: plat, longitude: plon)
        let meters = peerLocation.distance(from: loc)
        if meters < 1000 { return String(format: "%.0f 米", meters) }
        return String(format: "%.2f 公里", meters/1000)
    }

    func bearingText(for peer: Peer) -> String? {
        guard let plat = peer.latitude, let plon = peer.longitude, let loc = locationProvider.location else { return nil }
        let bearing = Self.bearing(from: loc.coordinate, to: CLLocationCoordinate2D(latitude: plat, longitude: plon))
        let dir = Self.cardinalDirection(from: bearing)
        return "方位：\(dir) \(Int(bearing))°"
    }
    
    func onlineDurationText(for peer: Peer) -> String? {
        guard let lastUpdated = peer.lastUpdatedAt else { return nil }
        let duration = Date().timeIntervalSince(lastUpdated)
        
        if duration < 60 {
            return "刚刚在线"
        } else if duration < 3600 {
            let minutes = Int(duration / 60)
            return "在线 \(minutes) 分钟"
        } else if duration < 86400 {
            let hours = Int(duration / 3600)
            return "在线 \(hours) 小时"
        } else {
            let days = Int(duration / 86400)
            return "在线 \(days) 天"
        }
    }

    private static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        var brng = atan2(y, x) * 180 / .pi
        if brng < 0 { brng += 360 }
        return brng
    }

    private static func cardinalDirection(from degrees: Double) -> String {
        let dirs = ["北", "东北", "东", "东南", "南", "西南", "西", "西北", "北"]
        let idx = Int((degrees + 22.5) / 45.0)
        return dirs[min(max(idx, 0), 8)]
    }
}


