//
//  P2PNetwork.swift
//  P2PKitExample
//
//  Created by Paige Sun on 5/2/24.
//

import Foundation
import MultipeerConnectivity

public struct P2PConstants {
    public static var networkChannelName = "my-p2p-service"
    public static var loggerEnabled = true
    
    struct UserDefaultsKeys {
        static let myMCPeerID = "com.P2PKit.MyMCPeerIDKey"
        static let myPeerID = "com.P2PKit.MyPeerIDKey"
    }
}

public protocol P2PNetworkPeerDelegate: AnyObject {
    func p2pNetwork(didUpdate peer: Peer) -> Void
}

public struct EventInfo: Codable {
    public let senderEntityID: String?
    public let sendTime: Double
}

public struct P2PNetwork {
    private static var session = P2PSession(myPeer: Peer.getMyPeer())
    private static let sessionListener = P2PNetworkSessionListener()
    
    // MARK: - Public P2PSession Getters
    
    // TODO: Set a device as session host
    public static var isHost: Bool = false
    
    public static var myPeer: Peer {
        return session.myPeer
    }
    
    // Connected Peers, not including self
    public static var connectedPeers: [Peer] {
        return session.connectedPeers
    }
    
    // Debug only, use connectedPeers instead.
    public static var allPeers: [Peer] {
        return session.allPeers
    }
    
    public static func start() {
        if session.delegate == nil {
            session.delegate = sessionListener
            session.start()
        }
    }
    
    // MARK: - Public P2PSession Functions
    
    public static func connectionState(for peer: MCPeerID) -> MCSessionState? {
        session.connectionState(for: peer)
    }
    
    public static func resetSession(displayName: String? = nil) {
        prettyPrint(level: .error, "♻️ Resetting Session!")
        let oldSession = session
        oldSession.disconnect()
        
        let newPeerId = MCPeerID(displayName: displayName ?? oldSession.myPeer.displayName)
        let myPeer = Peer.resetMyPeer(with: newPeerId)
        session = P2PSession(myPeer: myPeer)
        session.delegate = sessionListener
        session.start()
    }
    
    public static func makeBrowserViewController() -> MCBrowserViewController {
        return session.makeBrowserViewController()
    }
    
    // MARK: - Peer Delegates

    public static func addPeerDelegate(_ delegate: P2PNetworkPeerDelegate) {
        sessionListener.addPeerDelegate(delegate)
    }
    
    public static func removePeerDelegate(_ delegate: P2PNetworkPeerDelegate) {
        sessionListener.removePeerDelegate(delegate)
    }

    // MARK: - Internal - Send and Receive Events
    
    static func send(_ encodable: Encodable, to peers: [MCPeerID] = [], reliable: Bool) {
        session.send(encodable, to: peers, reliable: reliable)
    }
    
    static func sendData(_ data: Data, to peers: [MCPeerID] = [], reliable: Bool) {
        session.send(data: data, to: peers, reliable: reliable)
    }
    
    static func onReceiveData(eventName: String, _ callback: @escaping DataHandler.Callback) -> DataHandler {
        sessionListener.onReceiveData(eventName: eventName, callback)
    }
}

class DataHandler {
    typealias Callback = (_ data: Data, _ dataAsJson: [String : Any]?, _ fromPeerID: MCPeerID) -> Void
    
    var callback: Callback
    
    init(_ callback: @escaping Callback) {
        self.callback = callback
    }
}

// MARK: - Private

private class P2PNetworkSessionListener {
    private var peerDelegates = [WeakPeerDelegate]()
        
    private var dataHandlers = [String: [Weak<DataHandler>]]()
    
    fileprivate func onReceiveData(eventName: String, _ handleData: @escaping DataHandler.Callback) -> DataHandler {
        let handler = DataHandler(handleData)
        if let handlers = dataHandlers[eventName] {
            dataHandlers[eventName] = handlers.filter { $0.weakRef != nil } + [Weak(handler)]
        } else {
            dataHandlers[eventName] = [Weak(handler)]
        }
        return handler
    }
    
    fileprivate func addPeerDelegate(_ delegate: P2PNetworkPeerDelegate) {
        if !peerDelegates.contains(where: { $0.delegate === delegate }) {
            peerDelegates.append(WeakPeerDelegate(delegate))
        }
        peerDelegates.removeAll(where: { $0.delegate == nil })
        delegate.p2pNetwork(didUpdate: P2PNetwork.myPeer)
    }
    
    fileprivate func removePeerDelegate(_ delegate: P2PNetworkPeerDelegate) {
        peerDelegates.removeAll(where: { $0.delegate === delegate || $0.delegate == nil })
    }
}

extension P2PNetworkSessionListener: P2PSessionDelegate {
    func p2pSession(_ session: P2PSession, didUpdate peer: Peer) {
        for peerDelegateWrapper in peerDelegates {
            peerDelegateWrapper.delegate?.p2pNetwork(didUpdate: peer)
        }
    }
    
    func p2pSession(_ session: P2PSession, didReceive data: Data, dataAsJson json: [String : Any]?, from peerID: MCPeerID) {
        if let eventName = json?["eventName"] as? String {
            if let handlers = dataHandlers[eventName] {
                for handler in handlers {
                    handler.weakRef?.callback(data, json, peerID)
                }
            }
        }
        
        if let handlers = dataHandlers[""] {
            for handler in handlers {
                handler.weakRef?.callback(data, json, peerID)
            }
        }
    }
}

private class WeakPeerDelegate {
    weak var delegate: P2PNetworkPeerDelegate?
    
    init(_ delegate: P2PNetworkPeerDelegate) {
        self.delegate = delegate
    }
}

private class Weak<T: AnyObject> {
    weak var weakRef: T?
    
    init(_ weakRef: T) {
        self.weakRef = weakRef
    }
}
