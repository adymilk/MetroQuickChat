import Foundation
import MultipeerConnectivity
import Network

/// Wi-Fi Direct service using MultipeerConnectivity for high-bandwidth file transfers
@MainActor
final class WiFiDirectService: NSObject, ObservableObject {
    enum TransferMode {
        case ble
        case wifi
    }
    
    @Published var isConnected: Bool = false
    @Published var connectedPeers: [MCPeerID] = []
    @Published var transferMode: TransferMode = .ble
    
    // Threshold: files > 2MB use Wi-Fi
    static let wifiThresholdBytes: Int = 2 * 1024 * 1024
    
    private let serviceType = "metroquickchat"
    private let peerId: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var tcpListener: NWListener?
    private var activeConnections: [MCPeerID: NWConnection] = [:]
    
    var onDataReceived: ((Data, MCPeerID) -> Void)?
    var onPeerConnected: ((MCPeerID) -> Void)?
    var onPeerDisconnected: ((MCPeerID) -> Void)?
    
    init(displayName: String) {
        self.peerId = MCPeerID(displayName: displayName)
        super.init()
    }
    
    // MARK: - Setup
    
    func startAdvertising(serviceInfo: [String: String]? = nil) {
        guard advertiser == nil else { return }
        
        session = MCSession(peer: peerId, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
        
        advertiser = MCNearbyServiceAdvertiser(
            peer: peerId,
            discoveryInfo: serviceInfo,
            serviceType: serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        
        // Also start TCP listener for large file transfers
        startTCPListener()
    }
    
    func startBrowsing() {
        guard browser == nil else { return }
        
        if session == nil {
            session = MCSession(peer: peerId, securityIdentity: nil, encryptionPreference: .required)
            session?.delegate = self
        }
        
        browser = MCNearbyServiceBrowser(peer: peerId, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }
    
    func stop() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        session?.disconnect()
        session = nil
        tcpListener?.cancel()
        tcpListener = nil
        activeConnections.values.forEach { $0.cancel() }
        activeConnections.removeAll()
        isConnected = false
        connectedPeers.removeAll()
    }
    
    // MARK: - TCP Socket Listener for Large Files
    
    private func startTCPListener() {
        let port: UInt16 = 8080
        let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        parameters.allowLocalEndpointReuse = true
        
        guard let listener = try? NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port)) else {
            print("WiFiDirectService: Failed to create TCP listener")
            return
        }
        
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleNewTCPConnection(connection)
            }
        }
        
        listener.stateUpdateHandler = { (state: NWListener.State) in
            switch state {
            case .ready:
                print("WiFiDirectService: TCP listener ready on port \(port)")
            case .failed(let error):
                print("WiFiDirectService: TCP listener failed: \(error)")
            default:
                break
            }
        }
        
        listener.start(queue: DispatchQueue.main)
        self.tcpListener = listener
    }
    
    private func handleNewTCPConnection(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue.main)
        receiveTCPData(on: connection)
    }
    
    private func receiveTCPData(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                print("WiFiDirectService: TCP receive error: \(error)")
                connection.cancel()
                return
            }
            
            if let data = data, !data.isEmpty {
                // Parse received data (assume format: length(4 bytes) + payload)
                if data.count >= 4 {
                    let length = UInt32(data[0]) << 24 | UInt32(data[1]) << 16 | UInt32(data[2]) << 8 | UInt32(data[3])
                    let payload = data.dropFirst(4)
                    
                    if payload.count == Int(length) {
                        // For now, we don't have peer ID in TCP stream, so we use a placeholder
                        // In production, you'd include peer ID in the protocol
                        DispatchQueue.main.async {
                            self.onDataReceived?(Data(payload), self.peerId)
                        }
                    }
                }
                
                if !isComplete {
                    self.receiveTCPData(on: connection)
                }
            }
        }
    }
    
    // MARK: - Send Data
    
    func send(_ data: Data, to peerId: UUID? = nil) -> Bool {
        guard let session = session, session.connectedPeers.count > 0 else {
            return false
        }
        
        // Determine transfer mode based on data size
        if data.count > Self.wifiThresholdBytes {
            transferMode = .wifi
            // Use TCP for large files
            if let peer = session.connectedPeers.first {
                return sendViaTCP(data, to: peer)
            }
        } else {
            transferMode = .ble
            // Use MCSession for small messages
            do {
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
                return true
            } catch {
                print("WiFiDirectService: Send error: \(error)")
                return false
            }
        }
        
        return false
    }
    
    private func sendViaTCP(_ data: Data, to peer: MCPeerID) -> Bool {
        // For TCP, we need the peer's IP address
        // MultipeerConnectivity doesn't expose IP directly, so we use resource transfer
        // This is a limitation - in production, you'd negotiate IP via MCSession first
        
        // Fallback: Use MCSession resource transfer for large files
        guard let session = session else { return false }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try data.write(to: tempURL)
            session.sendResource(at: tempURL, withName: "file-\(UUID().uuidString)", toPeer: peer) { error in
                if let error = error {
                    print("WiFiDirectService: Resource send error: \(error)")
                } else {
                    print("WiFiDirectService: Resource sent successfully")
                }
                try? FileManager.default.removeItem(at: tempURL)
            }
            return true
        } catch {
            print("WiFiDirectService: Failed to write temp file: \(error)")
            return false
        }
    }
}

// MARK: - MCSessionDelegate

extension WiFiDirectService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                }
                self.isConnected = self.connectedPeers.count > 0
                self.onPeerConnected?(peerID)
                print("WiFiDirectService: Peer connected: \(peerID.displayName)")
                
            case .connecting:
                print("WiFiDirectService: Connecting to: \(peerID.displayName)")
                
            case .notConnected:
                self.connectedPeers.removeAll { $0 == peerID }
                self.isConnected = self.connectedPeers.count > 0
                self.onPeerDisconnected?(peerID)
                print("WiFiDirectService: Peer disconnected: \(peerID.displayName)")
                
            @unknown default:
                break
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            self?.onDataReceived?(data, peerID)
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Handle streams if needed
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Handle resource reception
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        if let error = error {
            print("WiFiDirectService: Resource receive error: \(error)")
        } else if let url = localURL, let data = try? Data(contentsOf: url) {
            DispatchQueue.main.async { [weak self] in
                self?.onDataReceived?(data, peerID)
            }
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension WiFiDirectService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("WiFiDirectService: Failed to start advertising: \(error)")
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept invitations
        invitationHandler(true, session)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension WiFiDirectService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("WiFiDirectService: Failed to start browsing: \(error)")
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        // Auto-invite found peers
        browser.invitePeer(peerID, to: session!, withContext: nil, timeout: 30)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        // Handle peer lost
    }
}

