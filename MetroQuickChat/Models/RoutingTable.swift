import Foundation

/// Routing table entry for BLE mesh networking
struct RoutingEntry: Codable, Equatable {
    let peerId: UUID
    var hop: Int // Number of hops to reach this peer
    var lastSeen: Date
    
    init(peerId: UUID, hop: Int = 0, lastSeen: Date = Date()) {
        self.peerId = peerId
        self.hop = hop
        self.lastSeen = lastSeen
    }
}

/// Manages routing table for mesh networking
@MainActor
final class RoutingTable: ObservableObject {
    @Published private(set) var entries: [UUID: RoutingEntry] = [:]
    private let selfPeerId: UUID
    private var cleanupTimer: Timer?
    
    // Maximum age for routing entries before they expire
    private let entryTTL: TimeInterval = 30.0
    
    init(selfPeerId: UUID) {
        self.selfPeerId = selfPeerId
        // Add self as direct neighbor (hop 0)
        updateEntry(peerId: selfPeerId, hop: 0)
        startCleanupTimer()
    }
    
    /// Update routing entry for a peer
    func updateEntry(peerId: UUID, hop: Int) {
        let existing = entries[peerId]
        // Only update if hop count is better (smaller) or same peer
        if peerId == selfPeerId {
            entries[peerId] = RoutingEntry(peerId: peerId, hop: 0, lastSeen: Date())
        } else if existing == nil || hop < existing!.hop {
            entries[peerId] = RoutingEntry(peerId: peerId, hop: hop, lastSeen: Date())
        } else if existing?.hop == hop {
            // Update last seen time
            entries[peerId] = RoutingEntry(peerId: peerId, hop: hop, lastSeen: Date())
        }
    }
    
    /// Get best hop count to reach a peer
    func hopCount(to peerId: UUID) -> Int? {
        return entries[peerId]?.hop
    }
    
    /// Get direct neighbors (hop == 1)
    var directNeighbors: [UUID] {
        return entries.values
            .filter { $0.hop == 1 }
            .map { $0.peerId }
            .filter { $0 != selfPeerId }
    }
    
    /// Merge routing table from another peer
    func merge(from other: [RoutingEntry], via peerId: UUID) {
        let viaHop = entries[peerId]?.hop ?? 1
        for entry in other {
            let newHop = viaHop + entry.hop
            if entry.peerId != selfPeerId {
                updateEntry(peerId: entry.peerId, hop: newHop)
            }
        }
    }
    
    /// Export routing table for sharing
    func export() -> [RoutingEntry] {
        return Array(entries.values)
    }
    
    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.cleanupExpiredEntries()
        }
    }
    
    private func cleanupExpiredEntries() {
        let now = Date()
        let expired = entries.filter { peerId, entry in
            peerId != selfPeerId && now.timeIntervalSince(entry.lastSeen) > entryTTL
        }
        for (peerId, _) in expired {
            entries.removeValue(forKey: peerId)
        }
    }
    
    deinit {
        cleanupTimer?.invalidate()
    }
}

