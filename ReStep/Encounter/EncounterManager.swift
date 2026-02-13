import Foundation
import MultipeerConnectivity
import Combine

final class EncounterManager: NSObject, ObservableObject {
    @Published private(set) var nearbyTravelers: [Traveler] = []

    private let serviceType = "restep-enc"
    private let myPeerID = MCPeerID(displayName: UIDevice.current.name)
    private lazy var session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
    private lazy var advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
    private lazy var browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
    private var outboundTraveler: Traveler?

    override init() {
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
    }

    func sendTraveler(_ traveler: Traveler) {
        outboundTraveler = traveler
        guard !session.connectedPeers.isEmpty else { return }
        guard let data = try? JSONEncoder().encode(traveler) else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }
}

extension EncounterManager: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        if state == .connected, let traveler = outboundTraveler {
            sendTraveler(traveler)
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let traveler = try? JSONDecoder().decode(Traveler.self, from: data) {
            DispatchQueue.main.async {
                self.nearbyTravelers.insert(traveler, at: 0)
            }
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
