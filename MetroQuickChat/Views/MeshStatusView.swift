import SwiftUI
import Combine

/// Real-time mesh network status view showing coverage, nodes, and speed
@MainActor
struct MeshStatusView<Manager: ObservableObject & MeshRelayManagerProtocol>: View {
    @ObservedObject var meshManager: Manager
    @State private var animationScale: CGFloat = 1.0
    
    var body: some View {
        VStack(spacing: 16) {
            // Coverage and stats
            HStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse, options: .repeating)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Int(meshManager.stats.coverageRadius)) 米覆盖")
                        .font(.headline)
                    HStack(spacing: 8) {
                        Label("\(meshManager.stats.totalNodes) 人在线", systemImage: "person.3.fill")
                            .font(.caption)
                        Label("\(Int(meshManager.stats.averageSpeedup))× 速度", systemImage: "bolt.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                
                Spacer()
                
                // Speed indicator
                VStack(spacing: 2) {
                    Text("\(Int(meshManager.stats.averageSpeedup))×")
                        .font(.title.bold())
                        .foregroundStyle(.green)
                    Text("速度")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            
            // Active relays
            if !meshManager.activePaths.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("活跃中继路径")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    
                    ForEach(meshManager.activePaths.prefix(5)) { path in
                        RelayPathView(path: path)
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            
            // Relay nodes list
            if !meshManager.relays.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("中继节点 (\(meshManager.relays.count))")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(meshManager.relays.filter { !$0.isStale() }) { relay in
                                RelayNodeCard(relay: relay)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
        }
        .padding()
    }
}

/// Relay path view
private struct RelayPathView: View {
    let path: RelayPath
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.3.trianglepath")
                .font(.caption)
                .foregroundStyle(.blue)
            
            if let firstNode = path.nodes.first {
                Text(firstNode.nickname)
                    .font(.caption)
                
                if path.nodes.count > 1 {
                    Text("→ \(path.nodes.count - 1) hop")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Score indicator
            HStack(spacing: 4) {
                ForEach(0..<Int(path.totalScore), id: \.self) { _ in
                    Circle()
                        .fill(.green)
                        .frame(width: 4, height: 4)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Relay node card
private struct RelayNodeCard: View {
    let relay: RelayNode
    
    var body: some View {
        VStack(spacing: 6) {
            // Node status indicator
            Circle()
                .fill(relay.isDirectNeighbor ? .green : .orange)
                .frame(width: 8, height: 8)
            
            Text(relay.nickname)
                .font(.caption.bold())
                .lineLimit(1)
            
            HStack(spacing: 4) {
                // Hop count
                Label("\(relay.hop)", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                // RSSI
                Image(systemName: "wifi")
                    .font(.caption2)
                    .foregroundStyle(rssiColor(relay.rssi))
            }
            
            // Battery indicator
            HStack(spacing: 2) {
                ForEach(0..<5) { i in
                    Rectangle()
                        .fill(i < batteryLevel(relay.battery) ? .green : .gray.opacity(0.3))
                        .frame(width: 3, height: 6)
                }
            }
        }
        .padding(8)
        .frame(width: 80)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
    
    private func rssiColor(_ rssi: Int) -> Color {
        if rssi > -50 { return .green }
        if rssi > -70 { return .orange }
        return .red
    }
    
    private func batteryLevel(_ battery: Int) -> Int {
        return min(5, max(0, Int(Double(battery) / 20.0)))
    }
}

// MARK: - Channel Card with Mesh Stats

extension View {
    /// Add mesh stats overlay to channel card
    func meshStatsOverlay(stats: MeshStats) -> some View {
        self.overlay(alignment: .bottom) {
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                Text("\(Int(stats.coverageRadius)) 米覆盖 · \(stats.totalNodes) 人在线")
                Spacer()
                Text("\(Int(stats.averageSpeedup))× 速度")
                    .foregroundStyle(.green)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(8)
        }
    }
}

// MARK: - Preview

struct MeshStatusView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        let mockManager = MockMeshRelayManager()
        return MeshStatusView<MockMeshRelayManager>(meshManager: mockManager)
            .preferredColorScheme(.dark)
    }
}

/// Mock mesh manager for previews
@MainActor
private class MockMeshRelayManager: ObservableObject, MeshRelayManagerProtocol {
    @Published var relays: [RelayNode] = []
    @Published var stats: MeshStats = MeshStats()
    @Published var activePaths: [RelayPath] = []
    
    var onFileReceived: ((Data, String, String) -> Void)?
    var onTransferProgress: ((UUID, Double) -> Void)?
    
    init(
        selfPeerId: UUID = UUID(),
        channelId: UUID = UUID(),
        nickname: String = "我",
        central: BluetoothCentralManager? = nil,
        peripheral: BluetoothPeripheralManager? = nil
    ) {
        // Initialize with dummy managers (not used in mock)
        _ = central
        _ = peripheral
        // Simulate 50-node network
        for i in 1...50 {
            let relay = RelayNode(
                id: UUID(),
                channelId: channelId,
                nickname: "用户\(i)",
                hop: i <= 5 ? 1 : Int.random(in: 2...5),
                battery: Int.random(in: 20...100),
                rssi: Int.random(in: -90...(-50)),
                estimatedBandwidth: Double.random(in: 100...1000)
            )
            relays.append(relay)
        }
        
        // Create mock paths
        activePaths = Array(relays.prefix(10).map { RelayPath(nodes: [$0]) })
        
        // Update mock stats
        stats = MeshStats(
            totalNodes: relays.count + 1,
            directNeighbors: relays.filter { $0.isDirectNeighbor }.count,
            coverageRadius: 500.0,
            averageSpeedup: 10.0,
            activeRelays: activePaths.count
        )
    }
    
    func getTopPaths(count: Int) -> [RelayPath] {
        return Array(activePaths.prefix(count))
    }
    
    func sendFile(data: Data, fileName: String, mimeType: String) {
        // Mock implementation
    }
    
    private func updateStats() {
        // Mock stats already set in init
    }
}

