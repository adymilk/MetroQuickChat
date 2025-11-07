import Foundation

/// 消息文件项（用于文件列表显示）
struct MessageFileItem: Identifiable {
    let id: UUID
    let channelId: UUID
    let channelName: String?
    let messageId: UUID
    let messageType: MessageType?
    let attachment: Attachment?
    let text: String?
    let size: Int64
    let createdAt: Date
    let senderNickname: String
    
    init(message: Message, channelName: String?) {
        self.id = message.id
        self.channelId = message.channelId
        self.channelName = channelName
        self.messageId = message.id
        self.messageType = message.messageType
        self.attachment = message.attachment
        self.text = message.text
        self.createdAt = message.createdAt
        self.senderNickname = message.nickname
        
        // 计算消息大小
        var calculatedSize: Int64 = 0
        if let encoded = try? JSONEncoder().encode(message) {
            calculatedSize += Int64(encoded.count)
        }
        
        // 加上实际数据大小
        if let messageType = message.messageType {
            switch messageType {
            case .image(let data):
                calculatedSize += Int64(data.count)
            case .voice(let data, _):
                calculatedSize += Int64(data.count)
            case .video(let data, _, _):
                calculatedSize += Int64(data.count)
            case .text, .emoji:
                break
            }
        } else if let attachment = message.attachment {
            if let data = Data(base64Encoded: attachment.dataBase64) {
                calculatedSize += Int64(data.count)
            }
        }
        
        self.size = calculatedSize
    }
    
    var displayName: String {
        if let messageType = messageType {
            switch messageType {
            case .image:
                return "图片"
            case .voice(_, let duration):
                return "语音 (\(duration)秒)"
            case .video(_, _, let duration):
                if let duration = duration {
                    return "视频 (\(duration)秒)"
                }
                return "视频"
            case .text(let text), .emoji(let text):
                return text
            }
        } else if let attachment = attachment {
            switch attachment.kind {
            case .image:
                return "图片"
            case .video:
                return "视频"
            }
        }
        return text ?? "未知类型"
    }
    
    var fileType: FileType {
        if let messageType = messageType {
            switch messageType {
            case .text, .emoji:
                return .text
            case .image:
                return .image
            case .voice:
                return .voice
            case .video:
                return .video
            }
        } else if let attachment = attachment {
            switch attachment.kind {
            case .image:
                return .image
            case .video:
                return .video
            }
        }
        return .other
    }
    
    enum FileType: Identifiable {
        case text
        case image
        case video
        case voice
        case other
        
        var id: String {
            switch self {
            case .text: return "text"
            case .image: return "image"
            case .video: return "video"
            case .voice: return "voice"
            case .other: return "other"
            }
        }
    }
}

