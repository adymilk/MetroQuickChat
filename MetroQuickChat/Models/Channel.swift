import Foundation

public struct Channel: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public var name: String
    public var hostPeerId: UUID
    /// 房主昵称（带设备ID，防止重名）
    public var hostNickname: String?
    /// 房主设备唯一标识符
    public var hostDeviceId: UUID?
    public var createdAt: Date
    public var discoveryId: UUID?
    /// 最后发现时间（用于缓存机制）
    public var lastDiscoveredAt: Date?
    /// 是否在线（基于最近是否扫描到）
    public var isOnline: Bool {
        guard let lastDiscovered = lastDiscoveredAt else { return false }
        // 如果 30 秒内有扫描到，认为在线
        return Date().timeIntervalSince(lastDiscovered) < 30
    }
    
    /// 是否包含有效的房主信息
    public var hasValidHostInfo: Bool {
        return hostNickname != nil && hostDeviceId != nil && !hostNickname!.isEmpty
    }

    public init(
        id: UUID = UUID(),
        name: String,
        hostPeerId: UUID,
        hostNickname: String? = nil,
        hostDeviceId: UUID? = nil,
        createdAt: Date = Date(),
        discoveryId: UUID? = nil,
        lastDiscoveredAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.hostPeerId = hostPeerId
        self.hostNickname = hostNickname
        self.hostDeviceId = hostDeviceId
        self.createdAt = createdAt
        self.discoveryId = discoveryId
        self.lastDiscoveredAt = lastDiscoveredAt ?? Date()
    }
}


