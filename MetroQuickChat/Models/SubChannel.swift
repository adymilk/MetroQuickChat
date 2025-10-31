import Foundation

/// Represents a sub-channel within a logical channel
public struct SubChannel: Codable, Equatable, Identifiable {
    public let id: UUID // Unique sub-channel ID
    public let logicalChannelId: UUID // Parent logical channel ID
    public let name: String // Display name (e.g., "早八吐槽大会-2")
    public let subChannelIndex: Int // 1, 2, 3, ...
    public let hostPeerId: UUID
    public var memberCount: Int
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        logicalChannelId: UUID,
        name: String,
        subChannelIndex: Int,
        hostPeerId: UUID,
        memberCount: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.logicalChannelId = logicalChannelId
        self.name = name
        self.subChannelIndex = subChannelIndex
        self.hostPeerId = hostPeerId
        self.memberCount = memberCount
        self.createdAt = createdAt
    }
    
    /// Check if sub-channel is full (max 6 users)
    public var isFull: Bool {
        return memberCount >= 6
    }
}

/// Logical channel that may have multiple sub-channels
public struct LogicalChannel: Codable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public var subChannels: [SubChannel]
    public let createdAt: Date
    
    public init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.subChannels = []
        self.createdAt = createdAt
    }
    
    /// Get the least populated sub-channel
    var leastPopulatedSubChannel: SubChannel? {
        return subChannels
            .filter { !$0.isFull }
            .min { $0.memberCount < $1.memberCount }
    }
    
    /// Get total member count across all sub-channels
    var totalMembers: Int {
        return subChannels.reduce(0) { $0 + $1.memberCount }
    }
    
    /// Create a new sub-channel for this logical channel
    mutating func createSubChannel(hostPeerId: UUID) -> SubChannel {
        let index = subChannels.count + 1
        let subName = index == 1 ? name : "\(name)-\(index)"
        let subChannel = SubChannel(
            logicalChannelId: id,
            name: subName,
            subChannelIndex: index,
            hostPeerId: hostPeerId
        )
        subChannels.append(subChannel)
        return subChannel
    }
}

