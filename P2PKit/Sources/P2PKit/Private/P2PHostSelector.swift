//
//  P2PHostSelector.swift

import Foundation

struct HostEvent: Codable {
    enum Kind: Codable {
        case announceHost
    }
    
    let kind: Kind
}

// Decide which connected peer is the leader/host.
class P2PHostSelector {
    var didUpdateHost: ((_ host: Peer?) -> Void)? = nil
    
    var host: Peer? {
        _lock.lock(); defer { _lock.unlock() }
        return _host
    }
    
    private var _host: Peer? = nil
    private let _lock = NSLock()
    private let _hostEventService = P2PEventService<HostEvent.Kind>("P2PKit.P2PHostService")
    
    init() {
        P2PNetwork.addPeerDelegate(self)
        
        _hostEventService.onReceive() {
            [weak self] eventInfo, hostAction, json, sender in
            
            let peers = P2PNetwork.connectedPeers
            guard let self = self else { return }
            switch hostAction {
            case .announceHost:
                let hostPeer = peers.first(where: { $0.peerID == sender })
                if let hostPeer = hostPeer {
                    setHost(hostPeer)
                } else {
                    prettyPrint(level: .error, "Received host announcement, but I'm not fully connected to host.")
                    setHost(nil)
                    // TODO: They're host but I can't send to host --> restart session?
                }
            }
        }
    }
    
    deinit {
        P2PNetwork.removePeerDelegate(self)
    }
    
    func makeMeHost() {
        setHost(P2PNetwork.myPeer)
    }
    
    private func setHost(_ host: Peer?) {
        _lock.lock()
        _host = host
        _lock.unlock()
        
        prettyPrint("Setting new Host [\(host?.displayName ?? nil)]")
        didUpdateHost?(host)
        
        if host?.isMe == true {
            announceHostEvent()
        }
    }
    
    private func announceHostEvent(to peers: [Peer] = []) {
        _hostEventService.send(payload: .announceHost, to: peers.map { $0.peerID }, reliable: true)
    }
}

extension P2PHostSelector: P2PNetworkPeerDelegate {
    func p2pNetwork(didUpdate peer: Peer) {
        _lock.lock()
        if let host = _host {
            _lock.unlock()

            let connectedPeers = P2PNetwork.connectedPeers
            if host.isMe {
                if connectedPeers.contains(peer) {
                    // Announce to newly connected Peers that I am host
                    announceHostEvent(to: [peer])
                }
            } else if !connectedPeers.contains(where: { $0.peerID == host.peerID }) {
                // I've lost connection to existing host
                setHost(nil)
            }
        } else {
            _lock.unlock()
        }
    }
    
    func p2pNetwork(didUpdateHost host: Peer?) {
        // Intentionally empty
    }
}
