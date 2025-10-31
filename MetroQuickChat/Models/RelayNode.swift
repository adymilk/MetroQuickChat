import Foundation
import CoreBluetooth

/// Relay node in the mesh network - every user acts as a relay
public struct RelayNode: Identifiable, Codable, Equatable {
    public let id: UUID // User ID / Peer ID
    public let channelId: UUID // Channel this node belongs to
    public var nickname: String
    public var hop: Int // Number of hops to reach this node
    public var battery: Int // Battery percentage (0-100)
    public var rssi: Int // Signal strength in dBm
    public var lastHeartbeat: Date
    public var estimatedBandwidth: Double // KB/s estimated based on recent transfers
    public var connectionState: ConnectionState
    public var isDirectNeighbor: Bool // True if BLE directly connected
    
    public enum ConnectionState: String, Codable {
        case disconnected
        case scanning
        case connected
        case relaying
    }
    
    public init(
        id: UUID,
        channelId: UUID,
        nickname: String,
        hop: Int = 0,
        battery: Int = 100,
        rssi: Int = 0,
        lastHeartbeat: Date = Date(),
        estimatedBandwidth: Double = 0.0,
        connectionState: ConnectionState = .scanning,
        isDirectNeighbor: Bool = false
    ) {
        self.id = id
        self.channelId = channelId
        self.nickname = nickname
        self.hop = hop
        self.battery = battery
        self.rssi = rssi
        self.lastHeartbeat = lastHeartbeat
        self.estimatedBandwidth = estimatedBandwidth
        self.connectionState = connectionState
        self.isDirectNeighbor = isDirectNeighbor
    }
    
    /// Calculate relay score for path selection
    /// Score = (rssi * 0.5) + (battery * 0.3) + (bandwidth * 0.2)
    public func relayScore() -> Double {
        // Normalize values:
        // RSSI: -100 to 0 dBm -> 0 to 1 (better signal = higher score)
        let rssiScore = max(0.0, min(1.0, Double(rssi + 100) / 100.0))
        
        // Battery: 0-100% -> 0 to 1
        let batteryScore = Double(battery) / 100.0
        
        // Bandwidth: 0-1000 KB/s -> 0 to 1 (cap at 1000 KB/s)
        let bandwidthScore = min(1.0, estimatedBandwidth / 1000.0)
        
        // Hop penalty: prefer nodes with hop < 3
        let hopPenalty: Double = hop < 3 ? 1.0 : max(0.5, 1.0 - Double(hop - 3) * 0.1)
        
        let baseScore = (rssiScore * 0.5) + (batteryScore * 0.3) + (bandwidthScore * 0.2)
        return baseScore * hopPenalty
    }
    
    /// Check if node is stale (no heartbeat for > 5 seconds)
    public func isStale(timeout: TimeInterval = 5.0) -> Bool {
        Date().timeIntervalSince(lastHeartbeat) > timeout
    }
    
    /// Update from heartbeat advertisement
    public mutating func update(from heartbeat: HeartbeatAdvertisement) {
        self.hop = heartbeat.hop
        self.battery = heartbeat.battery
        self.rssi = heartbeat.rssi
        self.lastHeartbeat = Date()
        self.nickname = heartbeat.nickname
    }
    
    /// Update estimated bandwidth based on transfer metrics
    public mutating func updateBandwidth(bytesTransferred: Int, duration: TimeInterval) {
        let newBandwidth = Double(bytesTransferred) / duration / 1024.0 // KB/s
        // Exponential moving average
        estimatedBandwidth = estimatedBandwidth * 0.7 + newBandwidth * 0.3
    }
}

/// Heartbeat advertisement payload (broadcasted every 2s)
public struct HeartbeatAdvertisement: Codable {
    let userId: UUID
    let channelId: UUID
    let nickname: String
    let hop: Int
    let battery: Int
    let timestamp: TimeInterval
    
    // RSSI is not encoded (comes from BLE)
    var rssi: Int = 0
    
    init(userId: UUID, channelId: UUID, nickname: String, hop: Int, battery: Int) {
        self.userId = userId
        self.channelId = channelId
        self.nickname = nickname
        self.hop = hop
        self.battery = battery
        self.timestamp = Date().timeIntervalSince1970
    }
}

/// Relay path for multi-path transfers
public struct RelayPath: Identifiable, Comparable {
    public let id: UUID
    public var nodes: [RelayNode] // Ordered list of relay nodes
    public var totalScore: Double // Sum of relay scores
    public var estimatedLatency: TimeInterval // Estimated latency in seconds
    public var isActive: Bool
    
    public init(nodes: [RelayNode]) {
        self.id = UUID()
        self.nodes = nodes
        self.totalScore = nodes.reduce(0) { $0 + $1.relayScore() }
        // Estimate latency: each hop adds ~100ms base + bandwidth delay
        self.estimatedLatency = Double(nodes.count) * 0.1
        self.isActive = true
    }
    
    /// Calculate path bandwidth (bottleneck)
    public func pathBandwidth() -> Double {
        guard !nodes.isEmpty else { return 0 }
        return nodes.map { $0.estimatedBandwidth }.min() ?? 0
    }
    
    public static func < (lhs: RelayPath, rhs: RelayPath) -> Bool {
        // Sort by total score (higher is better)
        return lhs.totalScore < rhs.totalScore
    }
    
    public static func == (lhs: RelayPath, rhs: RelayPath) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Mesh network statistics
public struct MeshStats: Codable {
    var totalNodes: Int
    var directNeighbors: Int
    var coverageRadius: Double // meters (estimated from RSSI)
    var averageSpeedup: Double // 10× speed factor
    var activeRelays: Int
    
    init(totalNodes: Int = 0, directNeighbors: Int = 0, coverageRadius: Double = 0, averageSpeedup: Double = 1.0, activeRelays: Int = 0) {
        self.totalNodes = totalNodes
        self.directNeighbors = directNeighbors
        self.coverageRadius = coverageRadius
        self.averageSpeedup = averageSpeedup
        self.activeRelays = activeRelays
    }
}

