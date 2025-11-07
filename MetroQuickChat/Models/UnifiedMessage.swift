import Foundation

/// Unified message protocol for BLE/Wi-Fi transmission
/// Supports sub-channel sharding and mesh routing
public struct UnifiedMessage: Codable {
    // Message identification
    let msgId: UUID
    let channel: String // Logical channel name
    let subChannel: Int // Sub-channel index (1, 2, 3, ...)
    
    // Routing fields
    var ttl: Int // Time to live (max hops)
    var hops: [UUID] // List of peer IDs that have forwarded this message
    
    // Content
    let type: MessageTypeEnum // text, image, video, voice, join, system
    let sender: UUID
    let senderNickname: String
    let payload: String // base64 encoded or plain text
    let timestamp: TimeInterval // Unix timestamp
    
    // Optional fields
    let duration: Int? // For voice messages
    let fileSize: Int? // For image/video messages
    
    enum MessageTypeEnum: String, Codable {
        case text
        case image
        case video
        case voice
        case join
        case system
        case emoji
        case routingTableSync = "routing_sync"
        case subChannelInfo = "subchannel_info"
    }
    
    init(
        msgId: UUID = UUID(),
        channel: String,
        subChannel: Int,
        ttl: Int = 3,
        hops: [UUID] = [],
        type: MessageTypeEnum,
        sender: UUID,
        senderNickname: String,
        payload: String,
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        duration: Int? = nil,
        fileSize: Int? = nil
    ) {
        self.msgId = msgId
        self.channel = channel
        self.subChannel = subChannel
        self.ttl = ttl
        self.hops = hops
        self.type = type
        self.sender = sender
        self.senderNickname = senderNickname
        self.payload = payload
        self.timestamp = timestamp
        self.duration = duration
        self.fileSize = fileSize
    }
    
    /// Create a UnifiedMessage from a Message
    static func from(message: Message, logicalChannelName: String, subChannelIndex: Int, selfPeerId: UUID) -> UnifiedMessage? {
        guard let messageType = message.messageType else {
            // Handle system messages or legacy text
            if message.author == .system || !message.text.isEmpty {
                let payload = message.text.data(using: .utf8)?.base64EncodedString() ?? ""
                return UnifiedMessage(
                    channel: logicalChannelName,
                    subChannel: subChannelIndex,
                    type: message.author == .system ? .system : .text,
                    sender: message.author.userId ?? selfPeerId,
                    senderNickname: message.nickname,
                    payload: payload
                )
            }
            return nil
        }
        
        let type: MessageTypeEnum
        var payload: String
        var duration: Int? = nil
        var fileSize: Int? = nil
        
        switch messageType {
        case .text(let text):
            type = .text
            payload = text.data(using: .utf8)?.base64EncodedString() ?? ""
            
        case .emoji(let emoji):
            type = .emoji
            payload = emoji.data(using: .utf8)?.base64EncodedString() ?? ""
            
        case .image(let data):
            type = .image
            payload = data.base64EncodedString()
            fileSize = data.count
            
        case .voice(let data, let dur):
            type = .voice
            payload = data.base64EncodedString()
            duration = dur
            fileSize = data.count
            
        case .video(let data, _, let dur):
            type = .video
            payload = data.base64EncodedString()
            duration = dur
            fileSize = data.count
        }
        
        return UnifiedMessage(
            channel: logicalChannelName,
            subChannel: subChannelIndex,
            type: type,
            sender: message.author.userId ?? selfPeerId,
            senderNickname: message.nickname,
            payload: payload,
            timestamp: message.createdAt.timeIntervalSince1970,
            duration: duration,
            fileSize: fileSize
        )
    }
    
    /// Convert to Message for UI display
    func toMessage(logicalChannelId: UUID, subChannelId: UUID, selfPeerId: UUID) -> Message? {
        let channelId = subChannelId // Use sub-channel ID as channelId
        let author: MessageAuthor = sender == selfPeerId ? .user(sender) : .user(sender)
        let isOutgoing = sender == selfPeerId
        let createdAt = Date(timeIntervalSince1970: timestamp)
        
        // Try to decode payload as base64, fallback to plain text
        let payloadData: Data?
        if let decoded = Data(base64Encoded: payload) {
            payloadData = decoded
        } else {
            payloadData = payload.data(using: .utf8)
        }
        
        guard let data = payloadData else {
            // Fallback for plain text if decode fails
            if type == .text || type == .system {
                return Message(
                    id: msgId,
                    channelId: channelId,
                    author: type == .system ? .system : author,
                    nickname: senderNickname,
                    text: payload,
                    isOutgoing: isOutgoing,
                    createdAt: createdAt
                )
            }
            return nil
        }
        
        var messageType: MessageType?
        
        switch type {
        case .text:
            if let text = String(data: data, encoding: .utf8) {
                messageType = .text(text)
            }
        case .emoji:
            if let emoji = String(data: data, encoding: .utf8) {
                messageType = .emoji(emoji)
            }
        case .image:
            messageType = .image(data)
        case .voice:
            if let dur = duration {
                messageType = .voice(data, duration: dur)
            }
        case .video:
            messageType = .video(data, thumbnail: nil, duration: duration)
        case .system:
            if let text = String(data: data, encoding: .utf8) {
                return Message(
                    id: msgId,
                    channelId: channelId,
                    author: .system,
                    nickname: senderNickname,
                    text: text,
                    isOutgoing: isOutgoing,
                    createdAt: createdAt
                )
            }
        case .routingTableSync, .subChannelInfo, .join:
            return nil
        }
        
        guard let msgType = messageType else { return nil }
        
        return Message(
            id: msgId,
            channelId: channelId,
            author: author,
            nickname: senderNickname,
            text: "",
            messageType: msgType,
            isOutgoing: isOutgoing,
            createdAt: createdAt
        )
    }
    
    /// Check if message should be forwarded (not seen, TTL > 0)
    func shouldForward(seenMessages: Set<UUID>, selfPeerId: UUID) -> Bool {
        if seenMessages.contains(msgId) {
            return false // Already seen
        }
        if hops.contains(selfPeerId) {
            return false // Already forwarded by this peer
        }
        if ttl <= 0 {
            return false // TTL expired
        }
        return true
    }
    
    /// Create a forwarded copy with updated TTL and hops
    func forwarded(by peerId: UUID) -> UnifiedMessage {
        var forwarded = self
        forwarded.ttl = max(0, forwarded.ttl - 1)
        forwarded.hops.append(peerId)
        return forwarded
    }
}

