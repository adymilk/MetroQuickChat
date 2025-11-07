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
            .sink { [weak self] (identifier, name, hostNickname, hostDeviceId) in
                guard let self else { return }
                var isNewChannel = false
                
                // Create/update channel for discovered peripheral
                if let idx = self.channels.firstIndex(where: { $0.discoveryId == identifier }) {
                    // 更新现有频道的信息和发现时间
                    self.channels[idx].name = name
                    self.channels[idx].lastDiscoveredAt = Date()
                    // 如果之前没有房主信息，现在有了，更新它
                    if !self.channels[idx].hasValidHostInfo {
                        if let nickname = hostNickname, let deviceId = hostDeviceId {
                            self.channels[idx].hostNickname = nickname
                            self.channels[idx].hostDeviceId = deviceId
                            print("ChannelManager: 更新频道房主信息 - \(name): \(nickname)")
                        }
                    }
                } else {
                    // 创建新频道，使用广播中的房主信息
                    let channel = Channel(
                        name: name,
                        hostPeerId: identifier, // 使用identifier作为hostPeerId（蓝牙设备ID）
                        hostNickname: hostNickname,
                        hostDeviceId: hostDeviceId,
                        discoveryId: identifier,
                        lastDiscoveredAt: Date()
                    )
                    self.channels.append(channel)
                    
                    // 如果房主信息无效，标记并稍后清理（不会触发通知）
                    if !channel.hasValidHostInfo {
                        print("ChannelManager: ⚠️ 发现频道但缺少房主信息: \(name)，将在清理周期中移除")
                    } else {
                        // 只有有效房主信息才触发新频道发现事件
                        self.events.send(.channelDiscovered(channel))
                        
                        // 发送通知和触发震动
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            Haptics.success()
                            NotificationService.shared.notifyChannelDiscovered(channel)
                        }
                    }
                }
                self.events.send(.channelsUpdated(self.channels))
                
                // 关键修复：如果发现的是当前频道的设备，自动连接以确保双向通信
                if let currentChannel = self.currentChannel, name == currentChannel.name {
                    // 发现的是同一频道的设备，尝试连接
                    print("ChannelManager: 🔗 发现同频道设备，自动连接: \(identifier.uuidString.prefix(8)), 频道: \(name)")
                    
                    // 避免重复连接（检查是否已连接）
                    if !self.central.isConnected(to: identifier) {
                        self.central.connect(to: identifier)
                    } else {
                        print("ChannelManager: 设备已连接，跳过: \(identifier.uuidString.prefix(8))")
                    }
                }
                
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
                // 同时移除所有没有有效房主信息的频道（未知房主）
                let beforeCount = self.channels.count
                var channelsToRemove: [Channel] = []
                
                self.channels.removeAll { channel in
                    // 如果是当前频道，不移除
                    if channel.id == self.currentChannel?.id {
                        return false
                    }
                    
                    // 如果没有有效房主信息，标记为待移除（未知房主）
                    if !channel.hasValidHostInfo {
                        print("ChannelManager: 移除未知房主的频道 - \(channel.name)")
                        channelsToRemove.append(channel)
                        return true
                    }
                    
                    // 如果超过5分钟未发现，标记为待移除
                    if let lastDiscovered = channel.lastDiscoveredAt,
                       now.timeIntervalSince(lastDiscovered) > expiredThreshold {
                        channelsToRemove.append(channel)
                        return true
                    }
                    return false
                }
                
                // 对于要移除的频道，如果未收藏则删除全部数据
                for channel in channelsToRemove {
                    let isFavorite = self.store.isFavoriteChannel(channelId: channel.id)
                    if !isFavorite {
                        // 未收藏的频道，删除全部数据
                        print("ChannelManager: 删除未收藏频道的数据 - \(channel.name) (ID: \(channel.id.uuidString.prefix(8)))")
                        self.store.clearChannelMessages(channelId: channel.id)
                    } else {
                        // 已收藏的频道，保留数据，只打印日志
                        print("ChannelManager: 移除过期频道但保留数据（已收藏）- \(channel.name)")
                    }
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
        // 获取设备唯一标识符
        let deviceId = DeviceIdentifier.deviceId()
        let fullNickname = DeviceIdentifier.fullUserIdentifier(nickname: selfPeer.nickname)
        
        let channel = Channel(
            name: name,
            hostPeerId: selfPeer.id,
            hostNickname: fullNickname,
            hostDeviceId: deviceId,
            lastDiscoveredAt: Date()
        )
        channels.append(channel)
        peers = [Peer(id: selfPeer.id, nickname: selfPeer.nickname, isHost: true)]
        currentChannel = channel
        
        // 发送频道更新事件，让列表页知道新频道已创建
        events.send(.channelsUpdated(channels))
        events.send(.joined(channel, selfPeer))
        
        // 使用 Task 延迟执行，避免在视图更新期间修改状态
        Task { @MainActor in
            // 广播时传入房主信息
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
        
        // 关键修复：加入频道后也要开始广播，确保双向通信
        // 这样其他设备也可以连接到本设备，实现双向消息传输
        advertiseChannel()
        
        // 持续扫描，以便发现和连接同一频道的其他设备
        central.startScanning()
        
        // 连接到房主设备（如果存在且不是自己）
        if let discoveryId = channel.discoveryId, discoveryId != selfPeer.id {
            print("ChannelManager: 🔗 尝试连接到房主设备 - \(discoveryId.uuidString.prefix(8))")
            
            // 延迟一下，确保扫描到设备
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // 等待500ms，确保设备已在idToPeripheral中
                try? await Task.sleep(nanoseconds: 500_000_000)
                
                if !self.central.isConnected(to: discoveryId) {
                    self.central.connect(to: discoveryId)
                    print("ChannelManager: 连接请求已发送")
                } else {
                    print("ChannelManager: 已连接到房主设备")
                }
            }
        } else {
            print("ChannelManager: 自己是房主，无需连接")
        }
        
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
        
        // 首先尝试从 peers 列表中查找
        if let peer = peers.first(where: { $0.id == channel.hostPeerId }) {
            return peer
        }
        
        // 如果 peers 中没有，但频道有房主信息，创建一个虚拟的 Peer 用于显示
        if let hostNickname = channel.hostNickname, channel.hasValidHostInfo {
            // 解析完整昵称（格式：昵称#设备ID）
            let displayName: String
            if let hashIndex = hostNickname.firstIndex(of: "#") {
                displayName = String(hostNickname[..<hashIndex])
            } else {
                displayName = hostNickname
            }
            
            return Peer(
                id: channel.hostPeerId,
                nickname: displayName,
                isHost: true
            )
        }
        
        return nil
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

    func sendVideo(_ data: Data, thumbnail: Data? = nil, duration: Int? = nil) {
        guard let channel = currentChannel else { return }
        
        // 视频文件可能很大，需要压缩或限制大小
        // 对于蓝牙传输，建议视频文件不超过5MB
        let maxSize = 5_000_000
        var videoData = data
        
        // 如果视频太大，尝试压缩（这里简单处理，实际可以调用视频压缩库）
        if data.count > maxSize {
            print("ChannelManager: 警告：视频文件过大(\(data.count)字节)，建议压缩后发送")
            // 实际应用中可以使用 AVAssetExportSession 压缩视频
        }
        
        let message = Message(
            channelId: channel.id,
            author: .user(selfPeer.id),
            nickname: selfPeer.nickname,
            text: "",
            messageType: .video(videoData, thumbnail: thumbnail, duration: duration),
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
                    NSLog("📤 ChannelManager: 准备发送消息 - 类型: \(btMessage.type), 内容: \(message.displayText.prefix(50)), 分块数: \(frames.count)")
                    
                    // 关键修复：检查连接状态
                    let connectedCount = central.connectedDeviceCount
                    if connectedCount == 0 {
                        NSLog("⚠️ ChannelManager: 警告：没有已连接的设备，消息可能无法发送（仅依赖notify）")
                    } else {
                        NSLog("📡 ChannelManager: 准备发送消息，当前已连接 \(connectedCount) 个设备")
                    }
                    
                    for (index, frame) in frames.enumerated() {
                        // 关键修复：同时使用 Central 和 Peripheral 模式发送，确保双向通信
                        // Central 模式：向已连接的设备发送（writeValue）
                        central.send(frame)
                        // Peripheral 模式：向订阅的 Central 发送（notify）
                        peripheral.notify(frame)
                        
                        // 对于多块数据，使用RunLoop延迟避免发送过快
                        if frames.count > 1 && index < frames.count - 1 {
                            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01)) // 10ms 延迟
                        }
                    }
                    
                    NSLog("✅ ChannelManager: 消息发送完成 - 已发送 \(frames.count) 个数据块")
                } else {
                    NSLog("❌ ChannelManager: 无法创建 BluetoothMessage")
                }
            } else {
                let data = try encoder.encode(payload)
                // chunk large payloads
                let frames = BLEChunker.chunk(data: data)
                print("ChannelManager: 发送数据 - 分块数: \(frames.count)")
                
                for (index, frame) in frames.enumerated() {
                    central.send(frame)
                    peripheral.notify(frame)
                    
                    // 对于多块数据，使用RunLoop延迟
                    if frames.count > 1 && index < frames.count - 1 {
                        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01)) // 10ms 延迟
                    }
                }
            }
        } catch {
            let errorMsg = "编码失败: \(error.localizedDescription)"
            print("ChannelManager: ❌ \(errorMsg)")
            events.send(.error(errorMsg))
        }
    }

    private func handleIncoming(_ data: Data) {
        NSLog("📥 ChannelManager: 收到数据 - 大小: \(data.count) 字节")
        
        // 尝试重新组装分块数据
        if let joined = BLEChunker.reassemble(buffer: &reassemblyBuffer, incoming: data) {
            NSLog("📥 ChannelManager: 数据重组成功，总大小: \(joined.count) 字节")
            
            // Try BluetoothMessage protocol first (new format)
            if let btMessage = try? decoder.decode(BluetoothMessage.self, from: joined),
               let message = btMessage.toMessage(selfPeerId: selfPeer.id) {
                NSLog("✅ ChannelManager: 成功解析 BluetoothMessage - 类型: \(btMessage.type), 发送者: \(message.nickname)")
                events.send(.message(message))
                store.appendMessage(message)
                return
            }
            
            // Try legacy Message format
            if let message = try? decoder.decode(Message.self, from: joined) {
                NSLog("✅ ChannelManager: 成功解析 Message (legacy) - 发送者: \(message.nickname)")
                events.send(.message(message))
                store.appendMessage(message)
                return
            }
            
            // Try PresenceUpdate
            if let presence = try? decoder.decode(PresenceUpdate.self, from: joined) {
                NSLog("✅ ChannelManager: 收到 PresenceUpdate - 发送者: \(presence.nickname)")
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
            
            NSLog("⚠️ ChannelManager: 数据重组后无法解析 - 大小: \(joined.count)")
        } else {
            NSLog("📥 ChannelManager: 数据分块中，等待更多数据...")
        }
        
        // Try single-frame BluetoothMessage
        if let btMessage = try? decoder.decode(BluetoothMessage.self, from: data),
           let message = btMessage.toMessage(selfPeerId: selfPeer.id) {
            NSLog("✅ ChannelManager: 成功解析单帧 BluetoothMessage - 类型: \(btMessage.type), 发送者: \(message.nickname)")
            events.send(.message(message))
            store.appendMessage(message)
            return
        }
        
        // Try single-frame legacy Message
        if let message = try? decoder.decode(Message.self, from: data) {
            NSLog("✅ ChannelManager: 成功解析单帧 Message (legacy) - 发送者: \(message.nickname)")
            events.send(.message(message))
            store.appendMessage(message)
            return
        }
        // Could be Channel/Peer updates in future
    }

    func advertiseChannel() {
        guard let channel = currentChannel else {
            peripheral.startAdvertising(localName: selfPeer.nickname)
            return
        }
        
        // 广播时包含房主信息（昵称和设备ID）
        let hostNickname = channel.hostNickname ?? DeviceIdentifier.fullUserIdentifier(nickname: selfPeer.nickname)
        let hostDeviceId = channel.hostDeviceId ?? DeviceIdentifier.deviceId()
        peripheral.startAdvertising(localName: channel.name, hostNickname: hostNickname, hostDeviceId: hostDeviceId)
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


