//
//  GameRoom.swift
//  P2PKitExample
//
//  Created by Paige Sun on 5/12/24.
//

import Foundation
import UIKit
import P2PKit
import MultipeerConnectivity

class SyncedGameRoom {
    // All players including self
    var players: [Player] {
        return syncedRoom.value.players
    }
    
    var onRoomSync: ((GameRoom) -> Void)? = nil {
        didSet {
            p2pNetwork(didUpdate: P2PNetwork.myPeer)
        }
    }
    
    private(set) var isHost: Bool = false
    private let syncedRoom: P2PSynced<GameRoom>!
    
    init() {
        syncedRoom = P2PSynced<GameRoom>(
            name: "SyncedRoom",
            initial: GameRoom.initialLocalState,
            reliable: true)
        syncedRoom.onReceiveSync = { [weak self] gameRoom in
            guard let self = self else { return }
            onRoomSync?(gameRoom)
        }
                
        P2PNetwork.addPeerDelegate(self)
        P2PNetwork.start()
        p2pNetwork(didUpdateHost: P2PNetwork.host)
    }
    
    deinit {
        P2PNetwork.removePeerDelegate(self)
    }
}

// MARK: - Host Only

extension SyncedGameRoom {
    func incrementScore(_ playerID: Peer.Identifier) {
        guard isHost else { return }

        let prevRoom = syncedRoom.value
        if let prevPlayer = prevRoom.getPlayerByID(playerID) {
            let newRoom = prevRoom.withPlayer(prevPlayer.incrementScore())
            syncedRoom.value = newRoom
            onRoomSync?(newRoom)
        }
    }
}

extension SyncedGameRoom: P2PNetworkPeerDelegate {
    func p2pNetwork(didUpdateHost host: Peer?) {
        isHost = host?.isMe == true
        if isHost, let host = host {
            p2pNetwork(didUpdate: host)
        }
    }
    
    func p2pNetwork(didUpdate peer: Peer) {
        guard isHost, P2PNetwork.connectedPeers.count > 0 else {
            return
        }
                
        var room = syncedRoom.value
        let connectedIds = (
            [P2PNetwork.myPeer.id] + P2PNetwork.connectedPeers.map { $0.id }
        ).sorted()
        for playerID in connectedIds {
            if room.getPlayerByID(playerID) == nil {
                room = room.withNewPlayer(playerID: playerID) // TODO: custom method
            }
        }
        let newRoom = room.withConnectedIDs(connectedIds)
        syncedRoom.value = newRoom
        
        onRoomSync?(newRoom)
    }
}
