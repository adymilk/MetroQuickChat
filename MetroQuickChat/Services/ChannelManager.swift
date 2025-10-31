import Foundation
import Combine
import CoreLocation
import UIKit

@MainActor
final class ChannelManager: ObservableObject {
    enum Event {
        case channelsUpdated([Channel])
        case channelDiscovered(Channel) // 新发现的频道
        case joined(Channel, Peer)
        case left(Channel, Peer)
        case kicked(Channel, Peer)
        case dissolved(Channel)
        case message(Message)
        case error(String)
        case peersUpdated([Peer])
    }

    @Published private(set) var channels: [Channel] = []
    @Published private(set) var currentChannel: Channel? = nil
    @Published private(set) var peers: [Peer] = []

    let events = PassthroughSubject<Event, Never>()

    private let central: BluetoothCentralManager
    private let peripheral: BluetoothPeripheralManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    let store = LocalStore() // 改为公开，供设置页面访问
    let locationProvider = LocationProvider()
    private var reassemblyBuffer: [UUID: [Int: Data]] = [:]
    var selfPeer: Peer // 改为 var，以便更新昵称

    init(central: BluetoothCentralManager, peripheral: BluetoothPeripheralManager, selfPeer: Peer) {
        self.central = central
        self.peripheral = peripheral
        self.selfPeer = selfPeer
        bind()
    }

    private func bind() {
        central.incomingDataSubject
            .merge(with: peripheral.receivedWriteSubject)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.handleIncoming(data)
            }
            .store(in: &cancellables)

        central.discoveredSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (identifier, name) in
                guard let self else { return }
                var isNewChannel = false
                
                // Create/update channel for discovered peripheral
                if let idx = self.channels.firstIndex(where: { $0.discoveryId == identifier }) {
                    // 更新现有频道的信息和发现时间
                    self.channels[idx].name = name
                    self.channels[idx].lastDiscoveredAt = Date()
                } else {
                    // 创建新频道，记录发现时间
                    let channel = Channel(name: name, hostPeerId: identifier, discoveryId: identifier, lastDiscoveredAt: Date())
                    self.channels.append(channel)
                    isNewChannel = true
                    
                    // 触发新频道发现事件（用于通知和震动）
                    self.events.send(.channelDiscovered(channel))
                    
                    // 发送通知和触发震动
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        Haptics.success()
                        NotificationService.shared.notifyChannelDiscovered(channel)
                    }
                }
                self.events.send(.channelsUpdated(self.channels))
                
                // 检查是否是收藏的频道，如果是则自动尝试加入
                // 延迟执行，避免与用户手动操作冲突
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // 延迟 500ms，给用户手动操作时间
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    // 再次检查，确保用户没有手动加入频道
                    if self.currentChannel == nil {
                        self.autoJoinFavoriteChannels()
                    }
                }
            }
            .store(in: &cancellables)
        
        // 定期清理过期频道（超过5分钟未发现的频道）
        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                let now = Date()
                let expiredThreshold: TimeInterval = 300 // 5分钟
                
                // 移除超过5分钟未发现且不在当前频道的频道
                let beforeCount = self.channels.count
                self.channels.removeAll { channel in
                    // 如果是当前频道，不移除
                    if channel.id == self.currentChannel?.id {
                        return false
                    }
                    // 如果超过5分钟未发现，移除
                    if let lastDiscovered = channel.lastDiscoveredAt,
                       now.timeIntervalSince(lastDiscovered) > expiredThreshold {
                        print("ChannelManager: 移除过期频道 \(channel.name) (最后发现: \(now.timeIntervalSince(lastDiscovered))秒前)")
                        return true
                    }
                    return false
                }
                
                if self.channels.count != beforeCount {
                    self.events.send(.channelsUpdated(self.channels))
                }
                
                // 每30秒检查一次
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    func createChannel(name: String) {
        let channel = Channel(name: name, hostPeerId: selfPeer.id, lastDiscoveredAt: Date())
        channels.append(channel)
        peers = [Peer(id: selfPeer.id, nickname: selfPeer.nickname, isHost: true)]
        currentChannel = channel
        
        // 发送频道更新事件，让列表页知道新频道已创建
        events.send(.channelsUpdated(channels))
        events.send(.joined(channel, selfPeer))
        
        // 使用 Task 延迟执行，避免在视图更新期间修改状态
        Task { @MainActor in
            advertiseChannel()
            sendSystem("频道创建成功：\(name)")
            startPresenceLoop()
        }
    }

    func joinChannel(_ channel: Channel) {
        // 如果已经在另一个频道中，先离开（但不发送 .left 事件，因为这是切换操作）
        if let current = currentChannel, current.id != channel.id {
            // 先清理旧频道状态，但不发送 .left 事件（避免触发退出）
            peers.removeAll { $0.id == selfPeer.id }
            peripheral.stopAdvertising()
            stopPresenceLoop()
            // 注意：不发送 .left 事件，因为这是切换到另一个频道
        }
        
        currentChannel = channel
        
        // 设置 selfPeer 的 isHost 状态（根据 channel.hostPeerId 判断）
        let isCurrentUserHost = channel.hostPeerId == selfPeer.id
        selfPeer.isHost = isCurrentUserHost
        
        if peers.contains(where: { $0.id == selfPeer.id }) == false {
            peers.append(selfPeer)
        } else {
            // 更新已有的 peer 的 isHost 状态
            if let idx = peers.firstIndex(where: { $0.id == selfPeer.id }) {
                peers[idx].isHost = isCurrentUserHost
            }
        }
        
        events.send(.joined(channel, selfPeer))
        sendSystemWithNickname("\(selfPeer.nickname) 加入频道", nickname: selfPeer.nickname)
        if let discoveryId = channel.discoveryId { central.connect(to: discoveryId) }
        startPresenceLoop()
    }

    func leaveChannel() {
        guard let channel = currentChannel else { return }
        peers.removeAll { $0.id == selfPeer.id }
        currentChannel = nil
        events.send(.left(channel, selfPeer))
        sendSystem("已离开频道：\(channel.name)")
        peripheral.stopAdvertising()
        stopPresenceLoop()
    }

    func kick(peerId: UUID) {
        guard let channel = currentChannel else { return }
        guard selfPeer.isHost else { return }
        if let idx = peers.firstIndex(where: { $0.id == peerId }) {
            let kicked = peers.remove(at: idx)
            events.send(.kicked(channel, kicked))
            broadcastSystem("已将 \(kicked.nickname) 踢出频道")
        }
    }

    func dissolveChannel() {
        guard let channel = currentChannel else { return }
        guard selfPeer.isHost else { return }
        broadcastSystem("频道 \(channel.name) 已解散")
        events.send(.dissolved(channel))
        channels.removeAll { $0.id == channel.id }
        currentChannel = nil
        peers.removeAll()
        peripheral.stopAdvertising()
        stopPresenceLoop()
    }
    
    // MARK: - Channel Information Management (Host Only)
    
    /// 修改频道名称（只有房主可以）
    func updateChannelName(_ newName: String) {
        guard let channel = currentChannel else { return }
        guard selfPeer.isHost else {
            events.send(.error("只有房主可以修改频道名称"))
            return
        }
        
        // 更新频道列表中的名称
        if let idx = channels.firstIndex(where: { $0.id == channel.id }) {
            channels[idx].name = newName
            events.send(.channelsUpdated(channels))
        }
        
        // 更新当前频道
        currentChannel?.name = newName
        
        // 发送系统消息
        sendSystem("频道名称已更改为：\(newName)")
        
        // 更新广播名称
        advertiseChannel()
    }
    
    /// 获取房主信息
    func getHostPeer() -> Peer? {
        guard let channel = currentChannel else { return nil }
        return peers.first(where: { $0.id == channel.hostPeerId })
    }
    
    /// 检查当前用户是否是房主
    func isCurrentUserHost() -> Bool {
        guard let channel = currentChannel else { return false }
        return channel.hostPeerId == selfPeer.id && selfPeer.isHost
    }

    func sendChat(_ text: String) {
        guard let channel = currentChannel else { return }
        let message = Message(
            channelId: channel.id,
            author: .user(selfPeer.id),
            nickname: selfPeer.nickname,
            text: text,
            messageType: .text(text),
            isOutgoing: true
        )
        events.send(.message(message))
        send(message)
        store.appendMessage(message)
    }

    func sendImage(_ data: Data, mime: String = "image/jpeg", thumbnail: Data? = nil) {
        guard let channel = currentChannel else { return }
        // Compress if too large (max 1MB)
        let maxSize = 1_000_000
        var imageData = data
        if data.count > maxSize {
            // Compress JPEG further
            if let uiImage = UIImage(data: data) {
                var quality: CGFloat = 0.7
                while quality > 0.1 {
                    if let compressed = uiImage.jpegData(compressionQuality: quality),
                       compressed.count <= maxSize {
                        imageData = compressed
                        break
                    }
                    quality -= 0.1
                }
            }
        }
        
        let message = Message(
            channelId: channel.id,
            author: .user(selfPeer.id),
            nickname: selfPeer.nickname,
            text: "",
            messageType: .image(imageData),
            isOutgoing: true
        )
        events.send(.message(message))
        send(message)
        store.appendMessage(message)
    }

    func sendVideoThumbnail(_ thumbnail: Data, mime: String = "image/jpeg") {
        guard let channel = currentChannel else { return }
        let attachment = Attachment(kind: .video, mime: mime, dataBase64: thumbnail.base64EncodedString(), thumbnailBase64: nil)
        let message = Message(channelId: channel.id, author: .user(selfPeer.id), nickname: selfPeer.nickname, text: "[视频]", attachment: attachment)
        events.send(.message(message))
        send(message)
        store.appendMessage(message)
    }

    private func sendSystem(_ text: String) {
        guard let channel = currentChannel else { return }
        let message = Message(channelId: channel.id, author: .system, nickname: "系统", text: text)
        events.send(.message(message))
        send(message)
        store.appendMessage(message)
    }
    
    /// 发送包含用户昵称的系统消息
    private func sendSystemWithNickname(_ text: String, nickname: String) {
        guard let channel = currentChannel else { return }
        let message = Message(channelId: channel.id, author: .system, nickname: nickname, text: text)
        events.send(.message(message))
        send(message)
        store.appendMessage(message)
    }

    private func broadcastSystem(_ text: String) {
        guard let channel = currentChannel else { return }
        let message = Message(channelId: channel.id, author: .system, nickname: "系统", text: text)
        send(message)
    }

    func sendVoice(_ data: Data, duration: Int) {
        guard let channel = currentChannel else { return }
        let message = Message(
            channelId: channel.id,
            author: .user(selfPeer.id),
            nickname: selfPeer.nickname,
            text: "",
            messageType: .voice(data, duration: duration),
            isOutgoing: true
        )
        events.send(.message(message))
        send(message)
        store.appendMessage(message)
    }
    
    private func send<T: Encodable>(_ payload: T) {
        do {
            // For Message objects, convert to BluetoothMessage protocol
            if let message = payload as? Message {
                if let btMessage = BluetoothMessage.from(message: message, selfPeerId: selfPeer.id) {
                    let data = try encoder.encode(btMessage)
                    let frames = BLEChunker.chunk(data: data)
                    for frame in frames {
                        central.send(frame)
                        peripheral.notify(frame)
                    }
                }
            } else {
                let data = try encoder.encode(payload)
                // chunk large payloads
                let frames = BLEChunker.chunk(data: data)
                for frame in frames {
                    central.send(frame)
                    peripheral.notify(frame)
                }
            }
        } catch {
            events.send(.error("编码失败: \(error.localizedDescription)"))
        }
    }

    private func handleIncoming(_ data: Data) {
        if let joined = BLEChunker.reassemble(buffer: &reassemblyBuffer, incoming: data) {
            // Try BluetoothMessage protocol first (new format)
            if let btMessage = try? decoder.decode(BluetoothMessage.self, from: joined),
               let message = btMessage.toMessage(selfPeerId: selfPeer.id) {
                events.send(.message(message))
                store.appendMessage(message)
                return
            }
            // Try legacy Message format
            if let message = try? decoder.decode(Message.self, from: joined) {
                events.send(.message(message))
                store.appendMessage(message)
                return
            }
            // Try PresenceUpdate
            if let presence = try? decoder.decode(PresenceUpdate.self, from: joined) {
                // Update peer location
                if let idx = peers.firstIndex(where: { $0.id == presence.peerId }) {
                    peers[idx].latitude = presence.latitude
                    peers[idx].longitude = presence.longitude
                    peers[idx].lastUpdatedAt = presence.sentAt
                } else {
                    let p = Peer(id: presence.peerId, nickname: presence.nickname, isHost: presence.isHost, latitude: presence.latitude, longitude: presence.longitude, lastUpdatedAt: presence.sentAt)
                    peers.append(p)
                }
                events.send(.peersUpdated(peers))
                return
            }
        }
        // Try single-frame BluetoothMessage
        if let btMessage = try? decoder.decode(BluetoothMessage.self, from: data),
           let message = btMessage.toMessage(selfPeerId: selfPeer.id) {
            events.send(.message(message))
            store.appendMessage(message)
            return
        }
        // Try single-frame legacy Message
        if let message = try? decoder.decode(Message.self, from: data) {
            events.send(.message(message))
            store.appendMessage(message)
            return
        }
        // Could be Channel/Peer updates in future
    }

    func advertiseChannel() {
        let name = currentChannel?.name ?? selfPeer.nickname
        peripheral.startAdvertising(localName: name)
    }

    func startDiscovery() {
        print("ChannelManager: 开始扫描频道...")
        central.startScanning()
    }

    func stopDiscovery() {
        print("ChannelManager: 停止扫描频道...")
        central.stopScanning()
    }

    private var cancellables: Set<AnyCancellable> = []

    var selfPeerId: UUID { selfPeer.id }
    
    /// 更新用户昵称
    func updateNickname(_ newNickname: String) {
        // 更新 selfPeer 的昵称
        selfPeer.nickname = newNickname
        
        // 如果当前在频道中，更新 peers 列表中的昵称
        if let index = peers.firstIndex(where: { $0.id == selfPeer.id }) {
            peers[index].nickname = newNickname
            events.send(.peersUpdated(peers))
        }
    }

    func loadHistory(channelId: UUID) -> [Message] { store.loadMessages(channelId: channelId) }
    
    func deleteMessage(messageId: UUID) {
        guard let channel = currentChannel else { return }
        store.deleteMessage(messageId: messageId, channelId: channel.id)
    }
    
    // MARK: - Favorite Channels
    
    /// 收藏频道
    func favoriteChannel(_ channel: Channel) {
        store.saveFavoriteChannel(channel)
        print("ChannelManager: 已收藏频道: \(channel.name)")
    }
    
    /// 取消收藏频道
    func unfavoriteChannel(channelId: UUID) {
        store.removeFavoriteChannel(channelId: channelId)
        print("ChannelManager: 已取消收藏频道: \(channelId.uuidString.prefix(8))")
    }
    
    /// 检查频道是否已收藏
    func isFavoriteChannel(channelId: UUID) -> Bool {
        return store.isFavoriteChannel(channelId: channelId)
    }
    
    /// 加载所有收藏的频道
    func loadFavoriteChannels() -> [Channel] {
        return store.loadFavoriteChannels()
    }
    
    /// 自动尝试加入收藏的频道（当频道在线时）
    func autoJoinFavoriteChannels() {
        // 如果已经在频道中，不自动加入（避免打断用户操作）
        guard currentChannel == nil else {
            return
        }
        
        let favorites = loadFavoriteChannels()
        let availableChannels = channels.filter { ch in
            favorites.contains(where: { $0.id == ch.id }) && ch.isOnline
        }
        
        // 如果发现收藏的频道在线，自动加入第一个
        if let firstFavorite = availableChannels.first {
            print("ChannelManager: 自动加入收藏频道: \(firstFavorite.name)")
            joinChannel(firstFavorite)
        }
    }

    // Periodically broadcast presence while in a channel
    private var presenceTask: Task<Void, Never>? = nil
    private func startPresenceLoop() {
        presenceTask?.cancel()
        presenceTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if let ch = self.currentChannel, let loc = self.locationProvider.location {
                    let presence = PresenceUpdate(channelId: ch.id, peerId: self.selfPeer.id, nickname: self.selfPeer.nickname, latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, isHost: self.selfPeer.isHost, sentAt: Date())
                    self.send(presence)
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func stopPresenceLoop() { presenceTask?.cancel(); presenceTask = nil }
}


