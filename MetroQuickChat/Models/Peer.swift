import Foundation

public struct Peer: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public var nickname: String
    public var isHost: Bool
    public var latitude: Double?
    public var longitude: Double?
    public var lastUpdatedAt: Date?

    public init(id: UUID = UUID(), nickname: String, isHost: Bool = false, latitude: Double? = nil, longitude: Double? = nil, lastUpdatedAt: Date? = nil) {
        self.id = id
        self.nickname = nickname
        self.isHost = isHost
        self.latitude = latitude
        self.longitude = longitude
        self.lastUpdatedAt = lastUpdatedAt
    }
}


