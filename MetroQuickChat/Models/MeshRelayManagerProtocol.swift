import Foundation
import Combine

/// Protocol for mesh relay managers (allows mocking for previews)
@MainActor
protocol MeshRelayManagerProtocol: ObservableObject {
    var relays: [RelayNode] { get }
    var stats: MeshStats { get }
    var activePaths: [RelayPath] { get }
    
    func getTopPaths(count: Int) -> [RelayPath]
    func sendFile(data: Data, fileName: String, mimeType: String)
}

