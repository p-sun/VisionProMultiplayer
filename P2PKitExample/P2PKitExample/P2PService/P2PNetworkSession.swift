//
//  P2PNetworking.swift
//  P2PKitExample


import MultipeerConnectivity
import os.signpost

struct P2PConstants {
    static let networkChannelName = "my-p2p-service"
    static let loggerEnabled = true
}

protocol P2PNetworkSessionDelegate {
    func p2pNetworkSession(_ session: P2PNetworkSession, didUpdate player: Player) -> Void
    func p2pNetworkSession(_ session: P2PNetworkSession, didReceive: Data, from player: Player) -> Bool
}

class P2PNetworkSession: NSObject {
    static var shared = P2PNetworkSession(myPlayer: UserDefaults.standard.myPlayer)
    
    var delegates = [P2PNetworkSessionDelegate]() // TODO: Weak Ref?
    
    let myPlayer: Player
    let session: MCSession
    let advertiser: MCNearbyServiceAdvertiser
    let browser: MCNearbyServiceBrowser
    
    private let myDiscoveryInfo = DiscoveryInfo()
    
    private var peersLock = NSLock()
    private var foundPeers = Set<MCPeerID>()  // protected with playersLock
    private var discoveryInfos = [MCPeerID: DiscoveryInfo]() // protected with playersLock
    private var sessionStates = [MCPeerID: MCSessionState]() // protected with playersLock
    
    var connectedPeers: [Player] {
        peersLock.lock(); defer { peersLock.unlock() }
        prettyPrint(level: .debug, "\(session.connectedPeers)")
        return session.connectedPeers.filter { foundPeers.contains($0) }.map { Player($0) }
    }
    
    init(myPlayer: Player) {
        self.myPlayer = myPlayer
        let myPeerID = myPlayer.peerID
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID,
                                               discoveryInfo: ["discoveryId": "\(myDiscoveryInfo.discoveryId)"],
                                               serviceType: P2PConstants.networkChannelName)
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: P2PConstants.networkChannelName)
        
        super.init()
        
        session.delegate = self
        
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        
        browser.delegate = self
        browser.startBrowsingForPeers()
    }
    
    deinit {
        prettyPrint("Deinit")
        stopServices()
        session.disconnect()
        session.delegate = nil
    }
    
    private func stopServices() {
        advertiser.stopAdvertisingPeer()
        advertiser.delegate = nil
        
        browser.stopBrowsingForPeers()
        browser.delegate = nil
    }
    
    func connectionState(for peer: MCPeerID) -> MCSessionState? {
        peersLock.lock(); defer { peersLock.unlock() }
        return sessionStates[peer]
    }
    
    // MARK: - Sending
    
    func send(_ encodable: Encodable, to peers: [MCPeerID] = []) {
        do {
            let data = try JSONEncoder().encode(encodable)
            send(data: data, to: peers)
        } catch {
            prettyPrint(level: .error, "Could not encode: \(error.localizedDescription)")
        }
    }
    
    func send(data: Data, to peers: [MCPeerID] = []) {
        let sendToPeers = peers == [] ? session.connectedPeers : peers
        guard !sendToPeers.isEmpty else {
            return
        }
        
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            prettyPrint(level: .error, "error sending data to peers: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Delegates
    
    func addDelegate(_ delegate: P2PNetworkSessionDelegate) {
        delegates.append(delegate)
    }
    
    private func updateSessionDelegates(forPeer peerID: MCPeerID) {
        for delegate in delegates {
            delegate.p2pNetworkSession(self, didUpdate: Player(peerID))
        }
    }
    
    // MARK: - Loopback Test
    // Test whether a connection is still alive.
    
    private func startLoopbackTest(_ peerID: MCPeerID) {
        prettyPrint("Sending Ping to \(peerID.displayName)")
        send(["ping": ""], to: [peerID])
    }
    
    private func handleLoopbackTest(_ session: MCSession, didReceive json: [String: Any], fromPeer peerID: MCPeerID) -> Bool {
        if json["ping"] as? String == "" {
            prettyPrint("Sending Pong to \(peerID.displayName)")
            send(["pong": ""])
            return true
        } else if json["pong"] as? String == "" {
            prettyPrint("Received Pong from \(peerID.displayName)")
            peersLock.lock()
            if sessionStates[peerID] == nil {
                sessionStates[peerID] = .connected
            }
            peersLock.unlock()
            
            updateSessionDelegates(forPeer: peerID)
            return true
        }
        return false
    }
}

extension P2PNetworkSession: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        prettyPrint("Session state of [\(peerID.displayName)] changed to [\(state)]")
        
        peersLock.lock()
        sessionStates[peerID] = state
        
        switch state {
        case .connected:
            foundPeers.insert(peerID)
        case .connecting:
            break
        case .notConnected:
            invitePeerIfNeeded(peerID)
        default:
            fatalError(#function + " - Unexpected multipeer connectivity state.")
        }
        peersLock.unlock()

        updateSessionDelegates(forPeer: peerID)
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let json = try? JSONSerialization.jsonObject(with: data) {
            prettyPrint("Received: \(json)")
            
            if let json = json as? [String: Any] {
                if handleLoopbackTest(session, didReceive: json, fromPeer: peerID) {
                    return
                }
            }
        }
        
        for delegate in delegates {
            if delegate.p2pNetworkSession(self, didReceive: data, from: Player(peerID)) {
                return
            }
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        fatalError("This service does not send/receive streams.")
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        fatalError("This service does not send/receive resources.")
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        fatalError("This service does not send/receive resources.")
    }
    
    func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        certificateHandler(true)
    }
}

extension P2PNetworkSession: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        prettyPrint("Found peer: [\(peerID)]")
        
        if let discoveryId = info?["discoveryId"] {
            peersLock.lock()
            foundPeers.insert(peerID)

            discoveryInfos[peerID] = DiscoveryInfo(discoveryId: discoveryId)
            if sessionStates[peerID] == nil, session.connectedPeers.contains(peerID) {
                startLoopbackTest(peerID)
            }
            
            invitePeerIfNeeded(peerID)
            peersLock.unlock()
        }

        updateSessionDelegates(forPeer: peerID)
    }
    
    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        prettyPrint("Lost peer: [\(peerID.displayName)]")
        
        peersLock.lock()
        foundPeers.remove(peerID)
        
        // When a peer enters background, session.connectedPeers still contains that peer.
        // Setting this to nil ensures we make a loopback test to test the connection.
        sessionStates[peerID] = nil
        
        peersLock.unlock()
        
        updateSessionDelegates(forPeer: peerID)
    }
    
    private func invitePeerIfNeeded(_ peerID: MCPeerID) {
        let peerInfo = discoveryInfos[peerID]
        let sessionState = sessionStates[peerID]
        if let peerInfo = peerInfo, myDiscoveryInfo.shouldInvite(peerInfo),
           !session.connectedPeers.contains(peerID), sessionState != .connecting {
            prettyPrint("Inviting peer: [\(peerID.displayName)]")
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 3)
        }
    }
}

extension P2PNetworkSession: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        if !session.connectedPeers.contains(peerID), sessionStates[peerID] != .connecting {
            prettyPrint("Accepting Peer invite from [\(peerID.displayName)]")
            invitationHandler(true, self.session)
        }
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        prettyPrint(level:.error, "Error: \(error.localizedDescription)")
    }
}

private struct DiscoveryInfo {
    let discoveryId: String
    
    init(discoveryId: String? = nil) {
        self.discoveryId = discoveryId ?? "\(Date().timeIntervalSince1970) \(UUID().uuidString)"
    }
    
    func shouldInvite(_ otherInfo: DiscoveryInfo) -> Bool {
        return discoveryId < otherInfo.discoveryId
    }
}
