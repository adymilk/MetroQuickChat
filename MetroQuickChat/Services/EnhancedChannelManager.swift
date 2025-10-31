import Foundation
import Combine
import CoreLocation
import UIKit
import MultipeerConnectivity

/// Production-ready ChannelManager with sub-channel sharding, BLE mesh routing, and Wi-Fi Direct fallback
@MainActor
final class EnhancedChannelManager: ObservableObject {
    enum Event {
        case channelsUpdated([Channel])
        case joined(Channel, Peer)
        case left(Channel, Peer)
        case kicked(Channel, Peer)
        case dissolved(Channel)
        case message(Message)
        case error(String)
        case peersUpdated([Peer])
        case subChannelCreated(SubChannel)
        case routingTableUpdated
    }
    
    @Published private(set) var channels: [Channel] = []
    @Published private(set) var currentChannel: Channel? = nil
    @Published private(set) var currentSubChannel: SubChannel? = nil
    @Published private(set) var logicalChannels: [LogicalChannel] = []
    @Published private(set) var peers: [Peer] = []
    
    let events = PassthroughSubject<Event, Never>()
    
    private let central: BluetoothCentralManager
    private let peripheral: BluetoothPeripheralManager
    private let wifiService: WiFiDirectService
    private let meshRouter: MeshRoutingManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let store = LocalStore()
    let locationProvider = LocationProvider()
    private var reassemblyBuffer: [UUID: [Int: Data]] = [:]
    let selfPeer: Peer
    
    // Sub-channel management
    private var subChannelMap: [UUID: SubChannel] = [:] // channelId -> SubChannel
    private let maxUsersPerSubChannel = 6
    
    init(central: BluetoothCentralManager, peripheral: BluetoothPeripheralManager, selfPeer: Peer) {
        self.central = central
        self.peripheral = peripheral
        self.selfPeer = selfPeer
        self.wifiService = WiFiDirectService(displayName: selfPeer.nickname)
        self.meshRouter = MeshRoutingManager(selfPeerId: selfPeer.id)
        
        bind()
        setupMeshRouting()
        setupWiFiService()
    }
    
    private func bind() {
        // BLE incoming data
        central.incomingDataSubject
            .merge(with: peripheral.receivedWriteSubject)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.handleIncomingBLE(data)
            }
            .store(in: &cancellables)
        
        // Wi-Fi incoming data
        wifiService.onDataReceived = { [weak self] data, peerId in
            self?.handleIncomingWiFi(data, from: peerId)
        }
        
        // Channel discovery
        central.discoveredSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (identifier, name) in
                self?.handleDiscoveredChannel(identifier: identifier, name: name)
            }
            .store(in: &cancellables)
    }
    
    private func setupMeshRouting() {
        meshRouter.onMessageReceived = { [weak self] unifiedMessage in
            self?.handleUnifiedMessage(unifiedMessage)
        }
        
        meshRouter.sendToDirectNeighbors = { [weak self] unifiedMessage in
            self?.forwardUnifiedMessage(unifiedMessage)
        }
    }
    
    private func setupWiFiService() {
        wifiService.onPeerConnected = { [weak self] peerId in
            print("EnhancedChannelManager: Wi-Fi peer connected: \(peerId.displayName)")
        }
        
        wifiService.onPeerDisconnected = { [weak self] peerId in
            print("EnhancedChannelManager: Wi-Fi peer disconnected: \(peerId.displayName)")
        }
    }
    
    // MARK: - Channel Management with Sub-channel Sharding
    
    func createChannel(name: String) {
        let logicalChannel = LogicalChannel(name: name)
        logicalChannels.append(logicalChannel)
        
        // Create first sub-channel
        var updatedChannel = logicalChannel
        let subChannel = updatedChannel.createSubChannel(hostPeerId: selfPeer.id)
        logicalChannels[logicalChannels.count - 1] = updatedChannel
        
        // Map to legacy Channel for compatibility
        let channel = Channel(
            id: subChannel.id,
            name: subChannel.name,
            hostPeerId: subChannel.hostPeerId,
            createdAt: subChannel.createdAt
        )
        
        channels.append(channel)
        subChannelMap[channel.id] = subChannel
        currentChannel = channel
        currentSubChannel = subChannel
        peers = [Peer(id: selfPeer.id, nickname: selfPeer.nickname, isHost: true)]
        
        events.send(.joined(channel, selfPeer))
        events.send(.subChannelCreated(subChannel))
        
        advertiseChannel()
        sendSystem("频道创建成功：\(name)")
        startPresenceLoop()
        
        // Start Wi-Fi advertising
        let serviceInfo = [
            "channel": name,
            "subChannels": encodeSubChannels([subChannel])
        ]
        wifiService.startAdvertising(serviceInfo: serviceInfo)
    }
    
    func joinChannel(_ channel: Channel) {
        // Find or create logical channel
        let logicalChannel: LogicalChannel
        if let existing = logicalChannels.first(where: { $0.name == channel.name }) {
            logicalChannel = existing
        } else {
            // New logical channel
            var newLogical = LogicalChannel(name: channel.name)
            logicalChannels.append(newLogical)
            logicalChannel = newLogical
        }
        
        // Find least populated sub-channel
        var updatedLogical = logicalChannel
        let targetSubChannel: SubChannel
        
        if let leastPopulated = updatedLogical.leastPopulatedSubChannel {
            // Join existing sub-channel
            targetSubChannel = leastPopulated
        } else {
            // All sub-channels full or none exist, create new one
            targetSubChannel = updatedLogical.createSubChannel(hostPeerId: channel.hostPeerId)
            logicalChannels[logicalChannels.firstIndex(where: { $0.id == logicalChannel.id })!] = updatedLogical
        }
        
        // Update current channel
        let updatedChannel = Channel(
            id: targetSubChannel.id,
            name: targetSubChannel.name,
            hostPeerId: targetSubChannel.hostPeerId,
            createdAt: targetSubChannel.createdAt,
            discoveryId: channel.discoveryId
        )
        
        currentChannel = updatedChannel
        currentSubChannel = targetSubChannel
        subChannelMap[updatedChannel.id] = targetSubChannel
        
        if peers.contains(where: { $0.id == selfPeer.id }) == false {
            peers.append(selfPeer)
        }
        
        // Update sub-channel member count
        updateSubChannelMemberCount(targetSubChannel.id, delta: 1)
        
        events.send(.joined(updatedChannel, selfPeer))
        sendSystem("已加入频道：\(targetSubChannel.name)")
        
        if let discoveryId = channel.discoveryId {
            central.connect(to: discoveryId)
        }
        
        startPresenceLoop()
        
        // Start Wi-Fi browsing for large file transfers
        wifiService.startBrowsing()
    }
    
    func leaveChannel() {
        guard let channel = currentChannel, let subChannel = currentSubChannel else { return }
        
        peers.removeAll { $0.id == selfPeer.id }
        updateSubChannelMemberCount(subChannel.id, delta: -1)
        
        currentChannel = nil
        currentSubChannel = nil
        
        events.send(.left(channel, selfPeer))
        sendSystem("已离开频道：\(channel.name)")
        
        peripheral.stopAdvertising()
        wifiService.stop()
        stopPresenceLoop()
    }
    
    private func updateSubChannelMemberCount(_ subChannelId: UUID, delta: Int) {
        if var subChannel = subChannelMap[subChannelId] {
            subChannel.memberCount = max(0, subChannel.memberCount + delta)
            subChannelMap[subChannelId] = subChannel
            
            // Update logical channel
            if let logicalIdx = logicalChannels.firstIndex(where: { $0.id == subChannel.logicalChannelId }) {
                if let subIdx = logicalChannels[logicalIdx].subChannels.firstIndex(where: { $0.id == subChannelId }) {
                    logicalChannels[logicalIdx].subChannels[subIdx].memberCount = subChannel.memberCount
                }
            }
        }
    }
    
    // MARK: - Message Sending
    
    func sendChat(_ text: String) {
        sendMessage(type: .text, payload: text.data(using: .utf8)?.base64EncodedString() ?? "")
    }
    
    func sendImage(_ data: Data, mime: String = "image/jpeg", thumbnail: Data? = nil) {
        // Compress if too large
        let maxSize = 1_000_000
        var imageData = data
        if data.count > maxSize, let uiImage = UIImage(data: data) {
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
        
        sendMessage(type: .image, payload: imageData.base64EncodedString(), fileSize: imageData.count)
    }
    
    func sendVoice(_ data: Data, duration: Int) {
        sendMessage(type: .voice, payload: data.base64EncodedString(), duration: duration, fileSize: data.count)
    }
    
    private func sendMessage(
        type: UnifiedMessage.MessageTypeEnum,
        payload: String,
        duration: Int? = nil,
        fileSize: Int? = nil
    ) {
        guard let channel = currentChannel,
              let subChannel = currentSubChannel else { return }
        
        let unifiedMessage = UnifiedMessage(
            channel: subChannel.name,
            subChannel: subChannel.subChannelIndex,
            ttl: 3,
            hops: [],
            type: type,
            sender: selfPeer.id,
            senderNickname: selfPeer.nickname,
            payload: payload,
            duration: duration,
            fileSize: fileSize
        )
        
        // Send via mesh router
        meshRouter.sendMessage(unifiedMessage)
        
        // Also send via Wi-Fi if file is large and Wi-Fi is available
        if let fileSize = fileSize, fileSize > WiFiDirectService.wifiThresholdBytes {
            if wifiService.isConnected {
                if let data = Data(base64Encoded: payload) {
                    _ = wifiService.send(data)
                }
            }
        }
    }
    
    private func forwardUnifiedMessage(_ unifiedMessage: UnifiedMessage) {
        // Forward via BLE
        if let data = try? encoder.encode(unifiedMessage) {
            let frames = BLEChunker.chunk(data: data)
            for frame in frames {
                central.send(frame)
                peripheral.notify(frame)
            }
        }
        
        // Forward via Wi-Fi if connected and message is large
        if let fileSize = unifiedMessage.fileSize,
           fileSize > WiFiDirectService.wifiThresholdBytes,
           wifiService.isConnected,
           let payload = Data(base64Encoded: unifiedMessage.payload) {
            _ = wifiService.send(payload)
        }
    }
    
    // MARK: - Message Reception
    
    private func handleIncomingBLE(_ data: Data) {
        if let reassembled = BLEChunker.reassemble(buffer: &reassemblyBuffer, incoming: data) {
            handleUnifiedMessageData(reassembled)
        } else {
            // Try single frame
            handleUnifiedMessageData(data)
        }
    }
    
    private func handleIncomingWiFi(_ data: Data, from peerId: MCPeerID) {
        // Wi-Fi messages are typically large files
        handleUnifiedMessageData(data)
    }
    
    private func handleUnifiedMessageData(_ data: Data) {
        // Try UnifiedMessage format first
        if let unifiedMessage = try? decoder.decode(UnifiedMessage.self, from: data) {
            handleUnifiedMessage(unifiedMessage)
            return
        }
        
        // Fallback to legacy BluetoothMessage
        if let btMessage = try? decoder.decode(BluetoothMessage.self, from: data),
           let message = btMessage.toMessage(selfPeerId: selfPeer.id) {
            events.send(.message(message))
            store.appendMessage(message)
        }
    }
    
    private func handleUnifiedMessage(_ unifiedMessage: UnifiedMessage) {
        // Extract sender peer ID from hops or sender field
        let senderId = unifiedMessage.hops.first ?? unifiedMessage.sender
        
        // Handle routing table sync
        if unifiedMessage.type == .routingTableSync {
            if let payloadData = Data(base64Encoded: unifiedMessage.payload),
               let entries = try? decoder.decode([RoutingEntry].self, from: payloadData) {
                meshRouter.updateRoutingTable(entries, from: senderId)
                events.send(.routingTableUpdated)
            }
            return
        }
        
        // Handle sub-channel info
        if unifiedMessage.type == .subChannelInfo {
            // Parse sub-channel information from payload
            // This would contain list of available sub-channels
            return
        }
        
        // Process regular message via mesh router
        meshRouter.processIncoming(unifiedMessage, from: senderId)
        
        // Convert to Message for UI and deliver
        deliverUnifiedMessageToUI(unifiedMessage)
    }
    
    private func deliverUnifiedMessageToUI(_ unifiedMessage: UnifiedMessage) {
        guard let channel = currentChannel,
              let subChannel = currentSubChannel else { return }
        
        if let message = unifiedMessage.toMessage(
            logicalChannelId: subChannel.logicalChannelId,
            subChannelId: subChannel.id,
            selfPeerId: selfPeer.id
        ) {
            events.send(.message(message))
            store.appendMessage(message)
        }
    }
    
    // MARK: - Channel Discovery
    
    private func handleDiscoveredChannel(identifier: UUID, name: String) {
        // Parse channel name and sub-channel info from advertising data
        // Format: "ChannelName-2" or "ChannelName"
        let components = name.split(separator: "-")
        let logicalChannelName = String(components[0])
        let subChannelIndex = components.count > 1 ? Int(components[1]) ?? 1 : 1
        
        // Find or create channel
        if let idx = channels.firstIndex(where: { $0.discoveryId == identifier }) {
            channels[idx].name = name
        } else {
            let channel = Channel(name: name, hostPeerId: identifier, discoveryId: identifier)
            channels.append(channel)
        }
        
        events.send(.channelsUpdated(channels))
    }
    
    // MARK: - Advertising
    
    func advertiseChannel() {
        guard let channel = currentChannel,
              let subChannel = currentSubChannel else { return }
        
        // Advertise sub-channel name
        peripheral.startAdvertising(localName: subChannel.name)
        
        // Also advertise all sub-channels in service info (for future enhancement)
        if let logicalChannel = logicalChannels.first(where: { $0.id == subChannel.logicalChannelId }) {
            let serviceInfo = [
                "channel": logicalChannel.name,
                "subChannels": encodeSubChannels(logicalChannel.subChannels)
            ]
            wifiService.startAdvertising(serviceInfo: serviceInfo)
        }
    }
    
    private func encodeSubChannels(_ subChannels: [SubChannel]) -> String {
        // Simple JSON encoding of sub-channel info
        guard let data = try? encoder.encode(subChannels),
              let str = String(data: data, encoding: .utf8) else {
            return ""
        }
        return str
    }
    
    func startDiscovery() {
        central.startScanning()
        wifiService.startBrowsing()
    }
    
    func stopDiscovery() {
        central.stopScanning()
        wifiService.stop()
    }
    
    // MARK: - Utilities
    
    private func sendSystem(_ text: String) {
        guard let channel = currentChannel else { return }
        let message = Message(channelId: channel.id, author: .system, nickname: "系统", text: text)
        events.send(.message(message))
        store.appendMessage(message)
    }
    
    func loadHistory(channelId: UUID) -> [Message] {
        return store.loadMessages(channelId: channelId)
    }
    
    var selfPeerId: UUID { selfPeer.id }
    
    // MARK: - Presence Loop
    
    private var presenceTask: Task<Void, Never>? = nil
    private func startPresenceLoop() {
        presenceTask?.cancel()
        presenceTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if let ch = self.currentChannel, let loc = self.locationProvider.location {
                    // Send presence via unified message
                    let presence = UnifiedMessage(
                        channel: ch.name,
                        subChannel: self.currentSubChannel?.subChannelIndex ?? 1,
                        ttl: 1, // Only direct neighbors
                        type: .system,
                        sender: self.selfPeer.id,
                        senderNickname: self.selfPeer.nickname,
                        payload: "presence:\(loc.coordinate.latitude),\(loc.coordinate.longitude)"
                    )
                    self.meshRouter.sendMessage(presence)
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }
    
    private func stopPresenceLoop() {
        presenceTask?.cancel()
        presenceTask = nil
    }
    
    private var cancellables: Set<AnyCancellable> = []
    
    func kick(peerId: UUID) {
        guard let channel = currentChannel else { return }
        guard selfPeer.isHost else { return }
        if let idx = peers.firstIndex(where: { $0.id == peerId }) {
            let kicked = peers.remove(at: idx)
            events.send(.kicked(channel, kicked))
            sendSystem("已将 \(kicked.nickname) 踢出频道")
        }
    }
    
    func dissolveChannel() {
        guard let channel = currentChannel else { return }
        guard selfPeer.isHost else { return }
        sendSystem("频道 \(channel.name) 已解散")
        events.send(.dissolved(channel))
        channels.removeAll { $0.id == channel.id }
        currentChannel = nil
        currentSubChannel = nil
        peers.removeAll()
        peripheral.stopAdvertising()
        wifiService.stop()
        stopPresenceLoop()
    }
}

