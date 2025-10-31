import Foundation

public enum MessageAuthor: Codable, Equatable {
    case user(UUID)
    case system

    private enum CodingKeys: String, CodingKey { case type, id }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "user":
            let id = try container.decode(UUID.self, forKey: .id)
            self = .user(id)
        default:
            self = .system
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .user(let id):
            try container.encode("user", forKey: .type)
            try container.encode(id, forKey: .id)
        case .system:
            try container.encode("system", forKey: .type)
        }
    }
}

public struct Message: Identifiable, Codable, Equatable {
    public let id: UUID
    public var channelId: UUID
    public var author: MessageAuthor
    public var nickname: String
    public var text: String // Legacy support, also used for system messages
    public var messageType: MessageType? // New type-based content
    public var attachment: Attachment? // Legacy support
    public var isOutgoing: Bool // True if sent by current user
    public var createdAt: Date
    public var relayHops: Int? // Number of relay hops (for mesh routing)
    public var relayLatency: TimeInterval? // Latency in seconds (for mesh routing)

    public init(id: UUID = UUID(), channelId: UUID, author: MessageAuthor, nickname: String, text: String, attachment: Attachment? = nil, messageType: MessageType? = nil, isOutgoing: Bool = false, createdAt: Date = Date(), relayHops: Int? = nil, relayLatency: TimeInterval? = nil) {
        self.id = id
        self.channelId = channelId
        self.author = author
        self.nickname = nickname
        self.text = text
        self.attachment = attachment
        self.messageType = messageType
        self.isOutgoing = isOutgoing
        self.createdAt = createdAt
        self.relayHops = relayHops
        self.relayLatency = relayLatency
    }
    
    // Computed property for backward compatibility
    public var displayText: String {
        if let messageType = messageType {
            switch messageType {
            case .text(let str), .emoji(let str):
                return str
            case .image:
                return "📷 图片"
            case .voice(_, let duration):
                return "🎤 语音 (\(duration)秒)"
            }
        }
        return text
    }
}

public struct Attachment: Codable, Equatable {
    public enum Kind: String, Codable { case image, video }
    public var kind: Kind
    public var mime: String
    public var dataBase64: String
    public var thumbnailBase64: String?
}


