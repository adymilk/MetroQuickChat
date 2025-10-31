import Foundation
import Combine

/// Manages BLE mesh routing, message forwarding, and deduplication
@MainActor
final class MeshRoutingManager: ObservableObject {
    private let routingTable: RoutingTable
    private let selfPeerId: UUID
    private var seenMessages: Set<UUID> = []
    private var seenMessageTTL: [UUID: Date] = [:]
    private var routingSyncTimer: Timer?
    
    // Maximum age for seen messages cache
    private let seenMessageTTLInterval: TimeInterval = 60.0
    
    // Closure to send messages to direct neighbors
    var sendToDirectNeighbors: ((UnifiedMessage) -> Void)?
    
    // Closure to handle incoming messages
    var onMessageReceived: ((UnifiedMessage) -> Void)?
    
    init(selfPeerId: UUID) {
        self.selfPeerId = selfPeerId
        self.routingTable = RoutingTable(selfPeerId: selfPeerId)
        startRoutingSyncTimer()
        startCleanupTimer()
    }
    
    // MARK: - Message Routing
    
    /// Process incoming message and determine if it should be forwarded
    func processIncoming(_ unifiedMessage: UnifiedMessage, from peerId: UUID) {
        // Update routing table (direct neighbor, hop 1)
        routingTable.updateEntry(peerId: peerId, hop: 1)
        
        // Check if we've already seen this message
        guard unifiedMessage.shouldForward(seenMessages: seenMessages, selfPeerId: selfPeerId) else {
            return // Already seen or invalid
        }
        
        // Mark as seen
        markAsSeen(unifiedMessage.msgId)
        
        // Deliver to local handler (this will handle UI delivery)
        onMessageReceived?(unifiedMessage)
        
        // Forward to neighbors if TTL allows
        if unifiedMessage.ttl > 0 && !unifiedMessage.hops.contains(selfPeerId) {
            let forwarded = unifiedMessage.forwarded(by: selfPeerId)
            forwardMessage(forwarded)
        }
    }
    
    /// Send message to direct neighbors for flooding
    private func forwardMessage(_ unifiedMessage: UnifiedMessage) {
        let neighbors = routingTable.directNeighbors
        guard !neighbors.isEmpty else { return }
        
        // Send to all direct neighbors (flooding)
        for neighborId in neighbors {
            // Filter out the sender from hops to avoid loops
            if !unifiedMessage.hops.contains(neighborId) {
                sendToDirectNeighbors?(unifiedMessage)
            }
        }
    }
    
    /// Send a new message (originated by this peer)
    func sendMessage(_ unifiedMessage: UnifiedMessage) {
        // Mark as seen to avoid echoing back
        markAsSeen(unifiedMessage.msgId)
        
        // Deliver locally
        onMessageReceived?(unifiedMessage)
        
        // Forward to all direct neighbors
        forwardMessage(unifiedMessage)
    }
    
    // MARK: - Routing Table Management
    
    /// Update routing table from a neighbor
    func updateRoutingTable(_ entries: [RoutingEntry], from peerId: UUID) {
        // Mark sender as direct neighbor
        routingTable.updateEntry(peerId: peerId, hop: 1)
        
        // Merge routing table
        routingTable.merge(from: entries, via: peerId)
    }
    
    /// Get routing table for sync
    func getRoutingTable() -> [RoutingEntry] {
        return routingTable.export()
    }
    
    /// Sync routing table with neighbors (called periodically)
    private func syncRoutingTable() {
        let entries = routingTable.export()
        let syncMessage = UnifiedMessage(
            channel: "",
            subChannel: 0,
            ttl: 1, // Only sync with direct neighbors
            hops: [],
            type: .routingTableSync,
            sender: selfPeerId,
            senderNickname: "",
            payload: (try? JSONEncoder().encode(entries).base64EncodedString()) ?? ""
        )
        
        // Send routing sync to direct neighbors
        forwardMessage(syncMessage)
    }
    
    // MARK: - Cleanup
    
    private func startRoutingSyncTimer() {
        routingSyncTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.syncRoutingTable()
        }
    }
    
    private func startCleanupTimer() {
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.cleanupSeenMessages()
        }
    }
    
    private func cleanupSeenMessages() {
        let now = Date()
        let expired = seenMessageTTL.filter { now.timeIntervalSince($0.value) > seenMessageTTLInterval }
        for (msgId, _) in expired {
            seenMessages.remove(msgId)
            seenMessageTTL.removeValue(forKey: msgId)
        }
    }
    
    private func markAsSeen(_ msgId: UUID) {
        seenMessages.insert(msgId)
        seenMessageTTL[msgId] = Date()
    }
    
    deinit {
        routingSyncTimer?.invalidate()
    }
}

