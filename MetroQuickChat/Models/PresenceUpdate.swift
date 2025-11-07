import Foundation

public struct PresenceUpdate: Codable {
    public let channelId: UUID
    public let peerId: UUID
    public let nickname: String
    public let latitude: Double
    public let longitude: Double
    public let isHost: Bool
    public let sentAt: Date
}




