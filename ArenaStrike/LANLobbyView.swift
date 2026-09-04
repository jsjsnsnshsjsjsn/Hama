import SwiftUI

/// لۆبی ١ڤ١ — خانەخوێ یان میوان لە هەمان وایفای
struct LANLobbyView: View {
    enum LobbyMode { case host, guest }
    let mode: LobbyMode

    @EnvironmentObject var settings: GameSettings
    @Environment(\.dismiss) private var dismiss
    @State private var session: NetSession?
    @State private var startGame = false
    @State private var netCfg: NetMatchConfig?

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                if let session {
                    lobbyContent(session)
                } else {
                    ProgressView("ئامادەکردن...")
                        .foregroundStyle(.white)
                }
            }
            .navigationTitle(mode == .host ? "خانەخوێ (Host)" : "میوان (Join)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                if session == nil {
                    let s = NetSession(side: mode == .host ? .host : .guest,
                                       name: settings.playerName)
                    session = s
                }
            }
            .navigationDestination(isPresented: $startGame) {
                if let session, let netCfg {
                    GameView(settings: settings, netSession: session, netCfg: netCfg)
                }
            }
        }
    }

    @ViewBuilder
    private func lobbyContent(_ session: NetSession) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 46))
                .foregroundStyle(AppTheme.accentGradient)
            Text("١ڤ١ — هەمان وایفای")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text(mode == .host
                 ? "چاوەڕوانی هاوڕێکەت... ئەو لە مۆبایلەکەی خۆی «میوان» هەڵدەبژێرێت"
                 : "هاوڕێکانت لە وایفاکەدا دەردەکەون — کرتە بکە بۆ پەیوەندیکردن")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)

            if mode == .guest {
                VStack(spacing: 10) {
                    ForEach(session.peers, id: \.self) { peer in
                        Button {
                            session.invite(peer)
                        } label: {
                            HStack {
                                Image(systemName: "person.circle")
                                Text(peer.displayName)
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill")
                            }
                            .padding()
                            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                        }
                    }
                    if session.peers.isEmpty {
                        Text("هیچ ئامێرێک نەدۆزرایەوە — دڵنیابە هەردووکتان لە هەمان وایفاین")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                }
                .frame(maxWidth: 420)
            } else {
                VStack(spacing: 10) {
                    if session.guestJoined {
                        Label("هاوڕێکەت بەسترایەوە! ✅", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text("ناو: \(session.session.connectedPeers.first?.displayName ?? "")")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    } else {
                        Text("چاوەڕوانی...")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }

            // ڕێکخستنەکانی یاری
            GlassCard {
                VStack(spacing: 14) {
                    HStack {
                        Text("قەبارەی ئەرێنا")
                        Spacer()
                        Picker("", selection: $settings.arenaSize) {
                            ForEach(ArenaSize.allCases) { s in Text(s.rawValue).tag(s) }
                        }
                        .pickerStyle(.menu)
                    }
                    HStack {
                        Text("کاتی یاری: \(settings.matchMinutes) خولەک")
                        Spacer()
                        Stepper("", value: $settings.matchMinutes, in: 1...10)
                            .labelsHidden()
                    }
                    HStack {
                        Text("چەکی سەرەتایی")
                        Spacer()
                        Picker("", selection: $settings.defaultWeapon) {
                            Text("M416").tag("M416")
                            Text("AKM").tag("AKM")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                }
                .foregroundStyle(.white)
            }
            .frame(maxWidth: 460)

            if mode == .host {
                Button {
                    let cfg = NetMatchConfig(
                        arenaMeters: settings.arenaSize.meters,
                        minutes: settings.matchMinutes,
                        weapon: settings.defaultWeapon,
                        hostName: settings.playerName,
                        guestName: session.session.connectedPeers.first?.displayName ?? "هاوڕێ",
                        seed: UInt32.random(in: 0...UInt32.max)
                    )
                    session.send(.start(cfg: cfg), reliable: true)
                    netCfg = cfg
                    startGame = true
                } label: {
                    Label("دەستپێکردنی یاری 🎮", systemImage: "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(AppTheme.accentGradient, in: Capsule())
                        .foregroundStyle(.white)
                }
                .disabled(!session.guestJoined)
                .opacity(session.guestJoined ? 1 : 0.5)
            }

            if let err = session.errorMessage {
                Text(err).font(.caption).foregroundStyle(.orange)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .onChange(of: session.receivedMatch) { _, cfg in
            if mode == .guest, let cfg {
                netCfg = cfg
                startGame = true
            }
        }
    }
}
