import Foundation
import MultipeerConnectivity

/// پەیامەکانی تۆڕ — ١ڤ١ لە هەمان وایفای (بەبێ سێرڤەر)
enum NetMsg: Codable {
    case hello(name: String)
    case start(cfg: NetMatchConfig)
    case state(NetPlayerState)
    case shot(damage: Double, headshot: Bool, from: String)
    case died(killer: String)
    case end(NetResult)
}

struct NetMatchConfig: Codable, Equatable {
    var arenaMeters: Float
    var minutes: Int
    var weapon: String
    var hostName: String
    var guestName: String
    var seed: UInt32
}

struct NetPlayerState: Codable {
    var x: Float, y: Float, z: Float
    var yaw: Float, pitch: Float
    var hp: Double
    var alive: Bool
    var scoped: Bool
    var weapon: String
    var kills: Int
    var deaths: Int
    var clock: Double
    var firing: Bool
}

struct NetResult: Codable {
    var winner: String
    var kills: [String: Int]
}

/// بەڕێوەبەری پەیوەندی ١ڤ١
final class NetSession: NSObject, ObservableObject {
    enum Side { case host, guest }

    let side: Side
    let myName: String
    @Published var peers: [MCPeerID] = []
    @Published var connected = false
    @Published var guestJoined = false
    @Published var receivedMatch: NetMatchConfig?
    @Published var errorMessage: String?

    var onMsg: ((NetMsg) -> Void)?

    private let serviceType = "arena1v1"
    private let myPeerID: MCPeerID
    let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    init(side: Side, name: String) {
        self.side = side
        self.myName = name.isEmpty ? UIDevice.current.name : name
        self.myPeerID = MCPeerID(displayName: self.myName)
        self.session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .none)
        super.init()
        session.delegate = self
        if side == .host {
            advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: ["name": self.myName], serviceType: serviceType)
            advertiser?.delegate = self
            advertiser?.startAdvertisingPeer()
        } else {
            browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
            browser?.delegate = self
            browser?.startBrowsingForPeers()
        }
    }

    deinit {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.disconnect()
    }

    var isHost: Bool { side == .host }

    func invite(_ peer: MCPeerID) {
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 15)
    }

    func send(_ msg: NetMsg, reliable: Bool = false) {
        guard session.connectedPeers.count > 0 else { return }
        do {
            let data = try JSONEncoder().encode(msg)
            try session.send(data, toPeers: session.connectedPeers,
                             with: reliable ? .reliable : .unreliable)
        } catch {
            errorMessage = "نەتوانرا پەیام بنێردرێت"
        }
    }
}

// MARK: - MCSessionDelegate
extension NetSession: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.connected = true
                if self.isHost { self.guestJoined = true }
            case .notConnected:
                self.connected = false
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            if let msg = try? JSONDecoder().decode(NetMsg.self, from: data) {
                if case .start(let cfg) = msg {
                    self.receivedMatch = cfg
                }
                self.onMsg?(msg)
            }
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - Browser (میوان)
extension NetSession: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            if !self.peers.contains(peerID) {
                self.peers.append(peerID)
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.peers.removeAll { $0 == peerID }
        }
    }
}

// MARK: - Advertiser (خانەخوێ)
extension NetSession: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // قبوڵکردنی خۆکار بۆ هاوڕێکان
        invitationHandler(true, session)
    }
}
