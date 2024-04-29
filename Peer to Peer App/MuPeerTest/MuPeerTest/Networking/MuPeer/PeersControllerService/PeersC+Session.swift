//  created by musesum on 12/8/22.

import MultipeerConnectivity

extension PeersController: MCSessionDelegate {

    public func session(_ session: MCSession,
                        peer peerID: MCPeerID,
                        didChange state: MCSessionState) {

        let peerName = peerID.displayName
        logPeer("session \"\(peerName)\" \(state.description())")
        peerState[peerName] = state
        
        if state == .notConnected {
            session.disconnect()
            peerState[peerName] = nil
        }
        for delegate in self.peersDelegates {
            delegate.sessionDidUpdate()
        }
    }

    /// receive message via session
    public func session(_ session: MCSession,
                        didReceive data: Data,
                        fromPeer peerID: MCPeerID) {

        let peerName = peerID.displayName
        logPeer("⚡️didReceive: \"\(peerName)\"")

        DispatchQueue.main.async {
            for delegate in self.peersDelegates {
                if delegate.received(data: data, viaStream: false) {
                    return
                }
            }
            
            do {
                let json = try JSONSerialization.data(withJSONObject: data).base64EncodedString()
                self.logPeer("WARN: Data has no listener to receive it: \(json)")
            } catch {
                self.logPeer("WARN: Data is not a JSON: \(error)")
            }
        }
    }

    /// setup stream for messages
    public func session(_ session: MCSession,
                        didReceive inputStream: InputStream,
                        withName streamName: String,
                        fromPeer: MCPeerID) {

        inputStream.delegate = self
        inputStream.schedule(in: .main, forMode: .common)
        inputStream.open()
        let peerName = fromPeer.displayName
        logPeer("💧didReceive inputStream from: \"\(peerName)\"")
    }

    // files not implemented
    public func session(_ session: MCSession, didStartReceivingResourceWithName _: String, fromPeer: MCPeerID, with _: Progress) {}
    public func session(_ session: MCSession, didFinishReceivingResourceWithName _: String, fromPeer: MCPeerID, at _: URL?, withError _: Error?) {}
}