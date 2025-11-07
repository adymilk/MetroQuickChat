import Foundation

/// Protocol message wrapper for Bluetooth transmission
/// Format: {type: "text|image|voice|emoji", payload: base64(Data), sender: UUID, timestamp: Date}
struct BluetoothMessage: Codable {
    let type: String
    let payload: String // base64 encoded
    let duration: Int? // For voice messages
    let sender: UUID
    let timestamp: Date
    let channelId: UUID
    let nickname: String
    
    init(type: String, payload: String, sender: UUID, timestamp: Date = Date(), channelId: UUID, nickname: String, duration: Int? = nil) {
        self.type = type
        self.payload = payload
        self.sender = sender
        self.timestamp = timestamp
        self.channelId = channelId
        self.nickname = nickname
        self.duration = duration
    }
    
    static func from(message: Message, selfPeerId: UUID) -> BluetoothMessage? {
        guard let channelId = UUID(uuidString: message.channelId.uuidString) else { return nil }
        
        if let messageType = message.messageType {
            switch messageType {
            case .text(let text):
                if let data = text.data(using: .utf8) {
                    return BluetoothMessage(
                        type: "text",
                        payload: data.base64EncodedString(),
                        sender: message.author.userId ?? selfPeerId,
                        timestamp: message.createdAt,
                        channelId: channelId,
                        nickname: message.nickname
                    )
                }
            case .emoji(let emoji):
                if let data = emoji.data(using: .utf8) {
                    return BluetoothMessage(
                        type: "emoji",
                        payload: data.base64EncodedString(),
                        sender: message.author.userId ?? selfPeerId,
                        timestamp: message.createdAt,
                        channelId: channelId,
                        nickname: message.nickname
                    )
                }
            case .image(let data):
                return BluetoothMessage(
                    type: "image",
                    payload: data.base64EncodedString(),
                    sender: message.author.userId ?? selfPeerId,
                    timestamp: message.createdAt,
                    channelId: channelId,
                    nickname: message.nickname
                )
            case .voice(let data, let duration):
                return BluetoothMessage(
                    type: "voice",
                    payload: data.base64EncodedString(),
                    sender: message.author.userId ?? selfPeerId,
                    timestamp: message.createdAt,
                    channelId: channelId,
                    nickname: message.nickname,
                    duration: duration
                )
            case .video(let data, let thumbnail, let duration):
                // 对于视频，我们需要将数据、缩略图和时长信息编码
                // 创建一个包含所有信息的JSON结构
                var videoDict: [String: String] = [:]
                videoDict["video"] = data.base64EncodedString()
                if let thumbnail = thumbnail {
                    videoDict["thumbnail"] = thumbnail.base64EncodedString()
                }
                if let duration = duration {
                    videoDict["duration"] = String(duration)
                }
                
                // 使用 JSONEncoder 构建JSON（更安全可靠）
                if let jsonData = try? JSONEncoder().encode(videoDict),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    return BluetoothMessage(
                        type: "video",
                        payload: jsonString.data(using: .utf8)?.base64EncodedString() ?? "",
                        sender: message.author.userId ?? selfPeerId,
                        timestamp: message.createdAt,
                        channelId: channelId,
                        nickname: message.nickname,
                        duration: duration
                    )
                }
                
                // Fallback: 只发送视频数据
                return BluetoothMessage(
                    type: "video",
                    payload: data.base64EncodedString(),
                    sender: message.author.userId ?? selfPeerId,
                    timestamp: message.createdAt,
                    channelId: channelId,
                    nickname: message.nickname,
                    duration: duration
                )
            }
        } else if !message.text.isEmpty {
            // Legacy text message
            if let data = message.text.data(using: .utf8) {
                return BluetoothMessage(
                    type: "text",
                    payload: data.base64EncodedString(),
                    sender: message.author.userId ?? selfPeerId,
                    timestamp: message.createdAt,
                    channelId: channelId,
                    nickname: message.nickname
                )
            }
        }
        
        return nil
    }
    
    func toMessage(selfPeerId: UUID) -> Message? {
        guard let payloadData = Data(base64Encoded: payload) else { return nil }
        
        var messageType: MessageType?
        
        switch type {
        case "text":
            if let text = String(data: payloadData, encoding: .utf8) {
                messageType = .text(text)
            }
        case "emoji":
            if let emoji = String(data: payloadData, encoding: .utf8) {
                messageType = .emoji(emoji)
            }
        case "image":
            messageType = .image(payloadData)
        case "voice":
            if let duration = duration {
                messageType = .voice(payloadData, duration: duration)
            }
        case "video":
            // 尝试解析JSON格式的视频数据（包含缩略图和时长）
            if let jsonString = String(data: payloadData, encoding: .utf8),
               let jsonData = jsonString.data(using: .utf8),
               let videoDict = try? JSONDecoder().decode([String: String].self, from: jsonData),
               let videoBase64 = videoDict["video"],
               let videoData = Data(base64Encoded: videoBase64) {
                let thumbnail = videoDict["thumbnail"].flatMap { Data(base64Encoded: $0) }
                let duration = videoDict["duration"].flatMap { Int($0) }
                messageType = .video(videoData, thumbnail: thumbnail, duration: duration)
            } else {
                // Fallback: 直接使用payload作为视频数据
                messageType = .video(payloadData, thumbnail: nil, duration: duration)
            }
        default:
            return nil
        }
        
        guard let msgType = messageType else { return nil }
        
        let author: MessageAuthor = sender == selfPeerId ? .user(selfPeerId) : .user(sender)
        let isOutgoing = sender == selfPeerId
        
        return Message(
            channelId: channelId,
            author: author,
            nickname: nickname,
            text: "", // Empty for typed messages
            messageType: msgType,
            isOutgoing: isOutgoing,
            createdAt: timestamp
        )
    }
}

extension MessageAuthor {
    var userId: UUID? {
        switch self {
        case .user(let id):
            return id
        case .system:
            return nil
        }
    }
}

