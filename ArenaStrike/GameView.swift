import SwiftUI
import SceneKit

/// شاشەی یاری — کۆنترۆڵەکان و HUD
struct GameView: View {
    let settings: GameSettings
    let netSession: NetSession?
    let netCfg: NetMatchConfig?

    @StateObject private var engine: GameEngine
    @Environment(\.dismiss) private var dismiss
    @State private var lastAim: CGSize = .zero

    init(settings: GameSettings, netSession: NetSession?, netCfg: NetMatchConfig?) {
        self.settings = settings
        self.netSession = netSession
        self.netCfg = netCfg
        _engine = StateObject(wrappedValue: GameEngine(settings: settings, netSession: netSession, netCfg: netCfg))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // سینەکەی سێ ڕەهەندی — دراگکردن لێرە ئامانجگرتنە
            SceneViewRepresentable(engine: engine)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let dx = Float(value.translation.width - lastAim.width)
                            let dy = Float(value.translation.height - lastAim.height)
                            lastAim = value.translation
                            engine.input.addAim(dx: dx, dy: dy)
                        }
                        .onEnded { _ in lastAim = .zero }
                )

            // HUD ی سەرەوە — بێ دەستلێدان
            topHUD
                .allowsHitTesting(false)

            // فلاشی زیان
            if engine.hud.damageFlash > 0.05 {
                Color.red.opacity(engine.hud.damageFlash * 0.35)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // کۆنترۆڵەکان — دەستلێدانی چالاک
            bottomControls

            // سکۆپ — بێ دەستلێدان
            if engine.hud.scoped && !engine.hud.gameOver {
                scopeOverlay
                    .allowsHitTesting(false)
            }

            // سپاونی دووبارە
            if let t = engine.hud.respawnIn {
                respawnOverlay(t: t)
                    .allowsHitTesting(false)
            }

            // پاوز و کۆتایی — دەستلێدانی چالاک
            if engine.hud.paused {
                pauseMenu
            }
            if engine.hud.gameOver {
                gameOverMenu()
            }
        }
        .statusBarHidden()
        .onDisappear {
            engine.input.send(.pause)
        }
    }

    // MARK: - HUD ی سەرەوە

    private var topHUD: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // نەخشەی بچووک
                MiniMapView(entries: engine.hud.minimap,
                            halfSize: engine.arenaHalfSize)
                    .frame(width: 110, height: 110)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.leading, 10)

                Spacer()

                // کات + ئەنجام
                VStack(spacing: 4) {
                    Text(engine.hud.timerText)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("کوشتن: \(engine.hud.kills)   مردن: \(engine.hud.deaths)")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.9))
                    Text("\(engine.hud.fps) FPS")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

                Spacer()

                // پاوز
                Button {
                    engine.input.send(.pause)
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.4), in: Circle())
                }
                .padding(.trailing, 10)
            }
            .padding(.top, 6)

            // فییدی کوشتن
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(engine.hud.feed.suffix(5).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.45), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 10)
            .padding(.top, 6)

            Spacer()
        }
    }

    // MARK: - کۆنترۆڵەکانی خوارەوە

    private var bottomControls: some View {
        VStack {
            Spacer()

            // HP + گوڵە
            HStack(spacing: 8) {
                // HP
                VStack(alignment: .leading, spacing: 3) {
                    Text("HP \(Int(engine.hud.hp))")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.25))
                            Capsule()
                                .fill(hpColor)
                                .frame(width: g.size.width * engine.hud.hp / 100)
                        }
                    }
                    .frame(width: 120, height: 9)
                }

                // گوڵە
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("\(engine.hud.ammo)/∞")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                        if engine.hud.reloading {
                            Text("بارکردنەوە...")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    Text("\(engine.hud.weaponName) • \(engine.hud.scopeName)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .allowsHitTesting(false)

            // کۆنترۆڵەکان
            HStack(alignment: .bottom) {
                // جۆیستیک
                JoystickView { x, y in
                    engine.input.moveX = x
                    engine.input.moveY = y
                }
                .frame(width: 130, height: 130)
                .padding(.leading, 12)

                Spacer()

                // دوگمەکانی لای ڕاست
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        ControlButton(icon: "scope", label: "سکۆپ") {
                            engine.input.send(.scopeTap)
                        }
                        ControlButton(icon: "arrow.triangle.2.circlepath", label: "گۆڕینی سکۆپ") {
                            engine.input.send(.cycleScope)
                        }
                    }
                    HStack(spacing: 10) {
                        ControlButton(icon: "arrow.up.to.line", label: "باز") {
                            engine.input.send(.jump)
                        }
                        ControlButton(icon: "arrow.down.to.line", label: "نیشتن") {
                            engine.input.send(.crouch)
                        }
                    }
                }
                .padding(.trailing, 12)

                // دوگمەی تەقە
                FireButton { down in
                    engine.input.fireDown = down
                }
                .padding(.trailing, 16)
            }
            .padding(.bottom, 10)

            // هێڵی دووەم: POV + چەک + گوڵە
            HStack {
                Spacer()
                ControlButton(icon: "eye", label: engine.hud.tpp ? "TPP" : "FPP") {
                    engine.input.send(.togglePOV)
                }
                ControlButton(icon: "arrow.left.arrow.right", label: "چەک") {
                    engine.input.send(.switchWeapon)
                }
                ControlButton(icon: "arrow.clockwise", label: "گلوول") {
                    engine.input.send(.reload)
                }
                .padding(.trailing, 16)
            }
            .padding(.bottom, 6)
        }
    }

    private func respawnOverlay(t: Double) -> some View {
        VStack(spacing: 8) {
            Text("کوژرایت! 💀")
                .font(.title.bold())
                .foregroundStyle(.white)
            Text("گەڕانەوە لە \(Int(t) + 1)...")
                .font(.title2)
                .foregroundStyle(.orange)
        }
        .padding(24)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
    }

    private var hpColor: Color {
        engine.hud.hp > 60 ? .green : (engine.hud.hp > 30 ? .orange : .red)
    }

    private var scopeOverlay: some View {
        ZStack {
            Color.black.opacity(0.93)
                .ignoresSafeArea()
                .mask(
                    ZStack {
                        Rectangle().fill(Color.black)
                        Circle().fill(Color.black).frame(width: 380).blendMode(.destinationOut)
                    }
                )
                .compositingGroup()
                .allowsHitTesting(false)
            // خاچی ئامانج
            ZStack {
                Rectangle().fill(.white.opacity(0.9)).frame(width: 2, height: 26)
                Rectangle().fill(.white.opacity(0.9)).frame(width: 26, height: 2)
            }
            .allowsHitTesting(false)
        }
    }

    private var pauseMenu: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("وەستا ⏸")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                Button {
                    engine.input.send(.resume)
                } label: {
                    Label("بەردەوامبوون", systemImage: "play.fill")
                        .frame(maxWidth: 240)
                }
                .buttonStyle(GradientButtonStyle())
                Button {
                    engine.restartMatchPublic()
                } label: {
                    Label("یاری نوێ", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                Button {
                    dismiss()
                } label: {
                    Label("گەڕانەوە بۆ مینیو", systemImage: "house.fill")
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
    }

    private func gameOverMenu() -> some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(engine.hud.winnerText)
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(.white)
                Text("کۆتایی یاری — ئەنجامەکان")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))

                VStack(spacing: 8) {
                    ForEach(engine.hud.ranking) { row in
                        HStack {
                            if row.isPlayer {
                                Text("تۆ")
                                    .font(.headline)
                                    .foregroundStyle(.cyan)
                            } else {
                                Text(row.name)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                            Spacer()
                            Text("\(row.kills) کوشتن")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                            Text("• \(row.deaths) مردن")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .frame(maxWidth: 340)
                .padding(.horizontal)

                HStack(spacing: 12) {
                    Button {
                        engine.restartMatchPublic()
                    } label: {
                        Label("یاری نوێ", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(GradientButtonStyle())
                    Button {
                        dismiss()
                    } label: {
                        Label("مینیو", systemImage: "house.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            }
            .padding()
        }
    }
}

// MARK: - داخستنی یاری نوێ (بۆ ئینجین — public wrapper)
extension GameEngine {
    func restartMatchPublic() {
        restartMatch()
    }
    var arenaHalfSize: Float { arena.halfSize }
}

// MARK: - SceneKit View

struct SceneViewRepresentable: UIViewRepresentable {
    @ObservedObject var engine: GameEngine

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.isMultipleTouchEnabled = true
        engine.start(on: view)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

// MARK: - کۆنترۆڵەکان

struct JoystickView: View {
    var onChange: (Float, Float) -> Void
    @State private var drag: CGSize = .zero

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.white.opacity(0.35), lineWidth: 2)
                .background(Circle().fill(.black.opacity(0.25)))
            Circle()
                .fill(.white.opacity(0.55))
                .frame(width: 48, height: 48)
                .offset(x: drag.width, y: drag.height)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    var dx = value.translation.width
                    var dy = value.translation.height
                    let maxD: CGFloat = 46
                    let d = sqrt(dx * dx + dy * dy)
                    if d > maxD {
                        dx = dx / d * maxD
                        dy = dy / d * maxD
                    }
                    drag = CGSize(width: dx, height: dy)
                    onChange(Float(dx / maxD), Float(dy / maxD))
                }
                .onEnded { _ in
                    drag = .zero
                    onChange(0, 0)
                }
        )
    }
}

struct FireButton: View {
    var onPress: (Bool) -> Void

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [.white.opacity(0.25), .black.opacity(0.35)], center: .center, startRadius: 2, endRadius: 38))
            .overlay(
                Circle().strokeBorder(.white.opacity(0.4), lineWidth: 2)
            )
            .overlay(Image(systemName: "bolt.fill").foregroundStyle(.white.opacity(0.9)))
            .frame(width: 76, height: 76)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onPress(true) }
                    .onEnded { _ in onPress(false) }
            )
    }
}

struct ControlButton: View {
    let icon: String
    let label: String
    var action: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.4), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
        }
        .contentShape(Rectangle())
        .onTapGesture { action() }
    }
}

// MARK: - نەخشەی بچووک

struct MiniMapView: View {
    let entries: [MiniEntry]
    let halfSize: Float

    var body: some View {
        Canvas { ctx, size in
            // دیوارەکان
            ctx.stroke(Path(CGRect(x: 2, y: 2, width: size.width - 4, height: size.height - 4)),
                       with: .color(.white.opacity(0.5)), lineWidth: 2)

            let scale = (size.width - 16) / CGFloat(halfSize * 2)
            let cx = size.width / 2
            let cy = size.height / 2

            for e in entries {
                let x = cx + CGFloat(e.x) * scale
                let y = cy + CGFloat(e.z) * scale
                let r: CGFloat = e.isPlayer ? 4 : 3.2
                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(e.color))
                if e.isPlayer {
                    ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)), with: .color(.white.opacity(0.7)), lineWidth: 1.2)
                }
            }
        }
    }
}
