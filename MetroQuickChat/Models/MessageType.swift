import Foundation

/// Message type enum for different content types
public enum MessageType: Codable, Equatable {
    case text(String)
    case emoji(String)
    case image(Data)
    case voice(Data, duration: Int) // Data is m4a audio, duration in seconds
    
    private enum CodingKeys: String, CodingKey {
        case type
        case payload
        case duration
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        
        switch typeString {
        case "text":
            let base64 = try container.decode(String.self, forKey: .payload)
            if let data = Data(base64Encoded: base64), let string = String(data: data, encoding: .utf8) {
                self = .text(string)
            } else {
                throw DecodingError.dataCorruptedError(forKey: .payload, in: container, debugDescription: "Invalid text payload")
            }
        case "emoji":
            let base64 = try container.decode(String.self, forKey: .payload)
            if let data = Data(base64Encoded: base64), let string = String(data: data, encoding: .utf8) {
                self = .emoji(string)
            } else {
                throw DecodingError.dataCorruptedError(forKey: .payload, in: container, debugDescription: "Invalid emoji payload")
            }
        case "image":
            let base64 = try container.decode(String.self, forKey: .payload)
            if let data = Data(base64Encoded: base64) {
                self = .image(data)
            } else {
                throw DecodingError.dataCorruptedError(forKey: .payload, in: container, debugDescription: "Invalid image payload")
            }
        case "voice":
            let base64 = try container.decode(String.self, forKey: .payload)
            let duration = try container.decode(Int.self, forKey: .duration)
            if let data = Data(base64Encoded: base64) {
                self = .voice(data, duration: duration)
            } else {
                throw DecodingError.dataCorruptedError(forKey: .payload, in: container, debugDescription: "Invalid voice payload")
            }
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown message type: \(typeString)")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .text(let string):
            try container.encode("text", forKey: .type)
            if let data = string.data(using: .utf8) {
                try container.encode(data.base64EncodedString(), forKey: .payload)
            }
        case .emoji(let string):
            try container.encode("emoji", forKey: .type)
            if let data = string.data(using: .utf8) {
                try container.encode(data.base64EncodedString(), forKey: .payload)
            }
        case .image(let data):
            try container.encode("image", forKey: .type)
            try container.encode(data.base64EncodedString(), forKey: .payload)
        case .voice(let data, let duration):
            try container.encode("voice", forKey: .type)
            try container.encode(data.base64EncodedString(), forKey: .payload)
            try container.encode(duration, forKey: .duration)
        }
    }
}

