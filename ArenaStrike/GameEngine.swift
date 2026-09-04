import Foundation
import SceneKit
import SwiftUI
import simd

// MARK: - Input

enum InputCommand {
    case scopeTap, jump, crouch, togglePOV, cycleScope, switchWeapon, reload
    case pause, resume, restart, quit
}

/// دۆخی چوونەژوورەوە — لە SwiftUI ەوە دەخوێنرێتەوە
final class InputState {
    var moveX: Float = 0
    var moveY: Float = 0
    var aimDX: Float = 0
    var aimDY: Float = 0
    var fireDown = false
    var commands: [InputCommand] = []

    func send(_ c: InputCommand) { commands.append(c) }
    func addAim(dx: Float, dy: Float) { aimDX += dx; aimDY += dy }
    func drain() -> [InputCommand] {
        let c = commands
        commands.removeAll()
        return c
    }
    func consumeAim() -> (Float, Float) {
        let r = (aimDX, aimDY)
        aimDX = 0; aimDY = 0
        return r
    }
}

// MARK: - HUD State

struct MiniEntry: Identifiable {
    let id = UUID()
    let x: Float
    let z: Float
    let color: Color
    let isPlayer: Bool
    let isOpponent: Bool
}

struct RankRow: Identifiable {
    let id = UUID()
    let name: String
    let kills: Int
    let deaths: Int
    let isPlayer: Bool
}

final class GameHUD: ObservableObject {
    @Published var hp: Double = 100
    @Published var ammo = 40
    @Published var magSize = 40
    @Published var reloading = false
    @Published var kills = 0
    @Published var deaths = 0
    @Published var timerText = "5:00"
    @Published var feed: [String] = []
    @Published var minimap: [MiniEntry] = []
    @Published var scoped = false
    @Published var scopeName = "ئاسن (Iron)"
    @Published var weaponName = "M416"
    @Published var respawnIn: Double?
    @Published var gameOver = false
    @Published var winnerText = ""
    @Published var ranking: [RankRow] = []
    @Published var fps = 0
    @Published var paused = false
    @Published var damageFlash = 0.0
    @Published var tpp = true
    @Published var crouching = false

    func addFeed(_ text: String) {
        feed.append(text)
        if feed.count > 5 { feed.removeFirst(feed.count - 5) }
    }
}

// MARK: - Entities

private final class Entity {
    let id: String            // "player", "bot0".."bot3", "opponent"
    let root: SCNNode

    init(id: String, root: SCNNode) {
        self.id = id
        self.root = root
    }

    var hp: Double = 100
    var alive = true
    var kills = 0
    var deaths = 0
    var respawnTimer: Double = 0
    var lastDamager: String?
    var velocityY: Float = 0
    var grounded = true
    var walkPhase: Double = 0
    var crouching = false
}

// MARK: - Game Engine

final class GameEngine: NSObject, ObservableObject, SCNSceneRendererDelegate {

    let scene = SCNScene()
    let input = InputState()
    let hud = GameHUD()
    let settings: GameSettings

    private weak var view: SCNView?
    private let netSession: NetSession?
    private let netCfg: NetMatchConfig?

    // جیهان
    private var arena = ArenaData(halfSize: 30)
    private let cameraNode = SCNNode()
    private let cameraHolder = SCNNode()
    private var viewmodelGun: SCNNode?

    // یاریزان و بۆتەکان
    private var player: Entity!
    private var bots: [Entity] = []
    private var botAIs: [BotAI] = []
    private var opponent: Entity?

    // چەک
    private var weaponKind: WeaponKind = .m416
    private var scopeIndex = 0
    private var ammo = 40
    private var fireTimer: Double = 0
    private var reloadTimer: Double = 0
    private var scoped = false
    private var pitch: Float = 0
    private var shake: Float = 0
    private var damagePulse: Double = 0

    // کات و ئەنجام
    private var matchTime: Double = 300
    private var lastStateSent: Double = 0
    private var fpsFrames = 0
    private var fpsTimer: Double = 0
    private var lastUpdate: TimeInterval = 0
    private var over = false
    private var oppTargetPos = SIMD3<Float>.zero
    private var oppYaw: Float = 0
    private var oppHp: Double = 100
    private var oppAlive = true
    private var oppWeapon = "M416"
    private var oppFiring = false
    private var oppFireFlash: Double = 0

    init(settings: GameSettings, netSession: NetSession?, netCfg: NetMatchConfig?) {
        self.settings = settings
        self.netSession = netSession
        self.netCfg = netCfg
        super.init()

        let meters = netCfg?.arenaMeters ?? settings.arenaSize.meters
        let minutes = netCfg?.minutes ?? settings.matchMinutes
        matchTime = Double(minutes) * 60
        weaponKind = (netCfg?.weapon ?? settings.defaultWeapon) == "AKM" ? .akm : .m416
        let arenaSeed = netCfg?.seed ?? UInt32.random(in: 0...UInt32.max)

        buildScene(meters: meters, seed: arenaSeed)
        setupCamera()
        player = makeSoldier(accent: UIColor(red: 0.2, green: 0.75, blue: 0.4, alpha: 1), name: "player")
        spawn(player, at: arena.spawns[Int.random(in: 0..<arena.spawns.count)])
        setupViewModelGun()

        if netSession == nil {
            // تاکە یاری: ٤ بۆت بە ئاستی هەڵبژێردراو
            let level = settings.botLevel
            for i in 0..<4 {
                let accent: UIColor
                switch level {
                case .easy:   accent = UIColor(red: 0.6, green: 0.6, blue: 0.62, alpha: 1)
                case .normal: accent = UIColor(red: 0.3, green: 0.7, blue: 0.35, alpha: 1)
                case .hard:   accent = UIColor(red: 0.25, green: 0.5, blue: 0.9, alpha: 1)
                case .insane: accent = UIColor(red: 0.95, green: 0.2, blue: 0.2, alpha: 1)
                }
                let bot = makeSoldier(accent: accent, name: "bot\(i)")
                spawn(bot, at: farSpawn(from: player.root.position))
                bots.append(bot)
                botAIs.append(BotAI(id: "bot\(i)", level: level))
            }
        } else {
            // ١ڤ١: دروستکردنی دوژمنی تۆڕی
            let opp = makeSoldier(accent: UIColor(red: 0.95, green: 0.45, blue: 0.15, alpha: 1), name: "opponent")
            opp.root.categoryBitMask = 0
            for child in opp.root.childNodes { child.categoryBitMask = 8 }
            let sp = arena.spawns[netSession!.isHost ? 1 : 5]
            opp.root.position = SCNVector3(sp.x, 0, sp.z)
            opponent = opp
            oppTargetPos = sp
        }

        // ناوی بۆتەکان لە feed
        hud.weaponName = weaponKind.spec.name
        hud.ammo = weaponKind.spec.magSize
        hud.magSize = weaponKind.spec.magSize
        ammo = weaponKind.spec.magSize
        hud.tpp = settings.defaultTPP
        hud.scopeName = ScopeKind.allCases[scopeIndex].name
        SoundEngine.shared.volume = Float(settings.volume)

        if let netSession {
            netSession.onMsg = { [weak self] msg in self?.handleNet(msg) }
            netSession.send(.hello(name: settings.playerName), reliable: true)
        }
    }

    // MARK: - Scene setup

    private func buildScene(meters: Float, seed: UInt32) {
        arena = ArenaBuilder.build(scene: scene, sizeMeters: meters, seed: seed)

        // ئاسمان و ڕووناکی
        scene.background.contents = UIColor(red: 0.055, green: 0.07, blue: 0.14, alpha: 1)
        scene.lightingEnvironment.contents = UIColor(red: 0.1, green: 0.14, blue: 0.24, alpha: 1)
        scene.lightingEnvironment.intensity = 1.2

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 260
        ambient.light?.color = UIColor(red: 0.55, green: 0.65, blue: 0.85, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 1200
        sun.light?.color = UIColor(red: 0.9, green: 0.85, blue: 0.78, alpha: 1)
        sun.light?.castsShadow = true
        sun.light?.shadowMode = .deferred
        sun.light?.shadowColor = UIColor.black.withAlphaComponent(0.55)
        sun.eulerAngles = SCNVector3(-Float.pi / 3.2, Float.pi / 5, 0)
        scene.rootNode.addChildNode(sun)

        scene.fogColor = UIColor(red: 0.05, green: 0.07, blue: 0.13, alpha: 1)
        scene.fogStartDistance = meters * 0.7
        scene.fogEndDistance = meters * 2.2
        scene.fogDensityExponent = 1.0
    }

    private func setupCamera() {
        cameraHolder.position = SCNVector3(0, 1.7, 0)
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.08
        cameraNode.camera?.zFar = 400
        cameraNode.camera?.fieldOfView = 72
        cameraNode.camera?.wantsHDR = true
        cameraHolder.addChildNode(cameraNode)
        cameraNode.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(cameraHolder)
        view?.pointOfView = cameraNode
    }

    /// دروستکردنی سەربازی سادە — لاشە + سەر + دەست و قاچ + چەک
    private func makeSoldier(accent: UIColor, name: String) -> Entity {
        let root = SCNNode()
        root.name = name

        let cloth = SCNMaterial()
        cloth.diffuse.contents = UIColor(red: 0.18, green: 0.24, blue: 0.16, alpha: 1)
        cloth.roughness.contents = 0.9
        cloth.lightingModel = .physicallyBased

        let accentMat = SCNMaterial()
        accentMat.diffuse.contents = accent
        accentMat.roughness.contents = 0.6
        accentMat.lightingModel = .physicallyBased

        let skin = SCNMaterial()
        skin.diffuse.contents = UIColor(red: 0.82, green: 0.66, blue: 0.5, alpha: 1)
        skin.roughness.contents = 0.8
        skin.lightingModel = .physicallyBased

        func part(_ geo: SCNGeometry, _ mat: SCNMaterial, _ pos: SCNVector3, _ nm: String) -> SCNNode {
            let n = SCNNode(geometry: geo)
            n.geometry?.materials = [mat]
            n.position = pos
            n.name = nm
            root.addChildNode(n)
            return n
        }

        // لاشە
        let torso = part(SCNCapsule(capRadius: 0.30, height: 0.78), cloth,
                         SCNVector3(0, 0.95, 0), "\(name)_torso")
        torso.eulerAngles.z = .pi / 2
        _ = part(SCNSphere(radius: 0.155), skin, SCNVector3(0, 1.62, 0), "\(name)_head")
        let helmet = part(SCNSphere(radius: 0.17), accentMat, SCNVector3(0, 1.66, 0), "\(name)_helmet")
        helmet.scale = SCNVector3(1, 0.55, 1)

        // قاچەکان
        let legL = part(SCNCapsule(capRadius: 0.085, height: 0.55), cloth,
                        SCNVector3(-0.12, 0.28, 0), "\(name)_legL")
        let legR = part(SCNCapsule(capRadius: 0.085, height: 0.55), cloth,
                        SCNVector3(0.12, 0.28, 0), "\(name)_legR")
        legL.pivot = SCNMatrix4MakeTranslation(0, 0.55, 0)
        legR.pivot = SCNMatrix4MakeTranslation(0, 0.55, 0)

        // دەستەکان
        let armL = part(SCNCapsule(capRadius: 0.065, height: 0.48), cloth,
                        SCNVector3(-0.38, 1.05, 0), "\(name)_armL")
        let armR = part(SCNCapsule(capRadius: 0.065, height: 0.48), cloth,
                        SCNVector3(0.38, 1.05, 0), "\(name)_armR")
        armL.pivot = SCNMatrix4MakeTranslation(0, 0.48, 0)
        armR.pivot = SCNMatrix4MakeTranslation(0, 0.48, 0)

        // چەک
        let gunHolder = SCNNode()
        gunHolder.name = "\(name)_gunHolder"
        gunHolder.position = SCNVector3(0.30, 1.12, 0.30)
        let body = SCNNode(geometry: SCNBox(width: 0.07, height: 0.16, length: 0.85, chamferRadius: 0.02))
        body.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)
        body.geometry?.firstMaterial?.roughness.contents = 0.5
        body.geometry?.firstMaterial?.metalness.contents = 0.7
        body.geometry?.firstMaterial?.lightingModel = .physicallyBased
        let barrel = SCNNode(geometry: SCNCylinder(radius: 0.02, height: 0.35))
        barrel.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)
        barrel.geometry?.firstMaterial?.metalness.contents = 0.9
        barrel.geometry?.firstMaterial?.lightingModel = .physicallyBased
        barrel.eulerAngles.x = .pi / 2
        barrel.position = SCNVector3(0, 0.02, -0.55)
        gunHolder.addChildNode(body)
        gunHolder.addChildNode(barrel)
        root.addChildNode(gunHolder)

        // دامەزراندنی ماسک بەپێی جۆر
        root.categoryBitMask = 0
        for child in root.childNodes { child.categoryBitMask = 2 }
        if name.hasPrefix("bot") {
            for child in root.childNodes { child.categoryBitMask = 4 }
        }

        scene.rootNode.addChildNode(root)
        return Entity(id: name, root: root)
    }

    private func setupViewModelGun() {
        let gun = makeGunMesh()
        gun.name = "viewmodelGun"
        gun.position = SCNVector3(0.26, -0.22, -0.62)
        gun.eulerAngles = SCNVector3(-0.05, 0, 0)
        cameraNode.addChildNode(gun)
        viewmodelGun = gun
        gun.isHidden = true
    }

    private func makeGunMesh() -> SCNNode {
        let holder = SCNNode()
        let body = SCNNode(geometry: SCNBox(width: 0.06, height: 0.13, length: 0.75, chamferRadius: 0.02))
        body.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
        body.geometry?.firstMaterial?.metalness.contents = 0.8
        body.geometry?.firstMaterial?.roughness.contents = 0.4
        body.geometry?.firstMaterial?.lightingModel = .physicallyBased
        let barrel = SCNNode(geometry: SCNCylinder(radius: 0.018, height: 0.3))
        barrel.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.09, green: 0.09, blue: 0.1, alpha: 1)
        barrel.geometry?.firstMaterial?.metalness.contents = 0.9
        barrel.geometry?.firstMaterial?.lightingModel = .physicallyBased
        barrel.eulerAngles.x = .pi / 2
        barrel.position = SCNVector3(0, 0.02, -0.48)
        let mag = SCNNode(geometry: SCNBox(width: 0.05, height: 0.16, length: 0.09, chamferRadius: 0.01))
        mag.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.15, green: 0.14, blue: 0.1, alpha: 1)
        mag.geometry?.firstMaterial?.metalness.contents = 0.5
        mag.geometry?.firstMaterial?.lightingModel = .physicallyBased
        mag.position = SCNVector3(0, -0.12, -0.05)
        holder.addChildNode(body)
        holder.addChildNode(barrel)
        holder.addChildNode(mag)
        return holder
    }

    // MARK: - Spawning

    private func spawn(_ e: Entity, at pos: SCNVector3) {
        e.root.position = pos
        e.root.isHidden = false
        e.hp = 100
        e.alive = true
        e.respawnTimer = 0
        e.velocityY = 0
        e.grounded = true
        e.crouching = false
        if e.id.hasPrefix("bot"), let idx = Int(e.id.dropFirst(3)) {
            botAIs[idx].onSpawn()
        }
    }

    private func farSpawn(from pos: SCNVector3) -> SCNVector3 {
        var best = arena.spawns[0]
        var bestD: Float = -1
        for s in arena.spawns {
            let d = (s.x - pos.x) * (s.x - pos.x) + (s.z - pos.z) * (s.z - pos.z)
            if d > bestD { bestD = d; best = s }
        }
        return SCNVector3(best.x, 0, best.z)
    }

    private func botIndex(forId id: String) -> Int? {
        Int(id.dropFirst(3))
    }

    // MARK: - Render loop

    func start(on view: SCNView) {
        self.view = view
        view.scene = scene
        view.pointOfView = cameraNode
        view.delegate = self
        view.isPlaying = true
        view.rendersContinuously = true
        view.preferredFramesPerSecond = settings.fpsMode.targetFPS(deviceMax: settings.deviceMaxFPS)
        view.antialiasingMode = settings.quality.antialiasing
        view.backgroundColor = .black
        let shadowLight = scene.rootNode
            .childNodes(passingTest: { _, _ in true })
            .compactMap { $0.light }
            .first { $0.castsShadow }
        shadowLight?.shadowMapSize = CGSize(width: settings.quality.shadowMap,
                                            height: settings.quality.shadowMap)
        view.allowsCameraControl = false
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = lastUpdate == 0 ? 1.0 / 60.0 : min(time - lastUpdate, 0.1)
        lastUpdate = time
        update(dt: dt)
    }

    // MARK: - Update

    private func update(dt: Double) {
        let f = Float(dt)

        // فرمانەکان — ئەوانەی لە هەموو دۆخێکدا کاردەکەن
        let commands = input.drain()
        for cmd in commands {
            switch cmd {
            case .pause: hud.paused = true
            case .resume: hud.paused = false; lastUpdate = 0
            case .restart: restartMatch()
            default: break
            }
        }
        guard !hud.paused else { return }
        guard !over else { return }

        // FPS counter
        fpsFrames += 1
        fpsTimer += dt
        if fpsTimer >= 1 {
            hud.fps = fpsFrames
            fpsFrames = 0
            fpsTimer = 0
        }

        // فرمانەکانی یاری
        for cmd in commands {
            switch cmd {
            case .scopeTap: scoped.toggle(); hud.scoped = scoped
            case .cycleScope:
                scopeIndex = (scopeIndex + 1) % ScopeKind.allCases.count
                hud.scopeName = ScopeKind.allCases[scopeIndex].name
            case .switchWeapon:
                weaponKind = weaponKind == .m416 ? .akm : .m416
                ammo = weaponKind.spec.magSize
                hud.weaponName = weaponKind.spec.name
                hud.ammo = ammo
                hud.magSize = weaponKind.spec.magSize
                reloadTimer = 0
                SoundEngine.shared.play(.reload)
            case .togglePOV:
                hud.tpp.toggle()
            case .crouch:
                player.crouching.toggle()
                hud.crouching = player.crouching
            case .jump:
                if player.grounded { player.velocityY = 6.4; player.grounded = false }
            case .reload:
                startReload()
            default: break
            }
        }

        // کات
        if !over {
            matchTime -= dt
            if matchTime <= 0 {
                matchTime = 0
                endMatch()
            }
        }
        hud.timerText = String(format: "%d:%02d", Int(matchTime) / 60, Int(matchTime) % 60)

        updatePlayer(dt: f)
        updateBots(dt: f)
        updateOpponentVisual(dt: dt)
        updateCamera(dt: f)
        updateNet(dt: dt)

        // ڤیزواڵی گشتی
        shake = max(0, shake - f * 2.2)
        damagePulse = max(0, damagePulse - dt * 2.5)
        hud.damageFlash = damagePulse
        hud.hp = player.hp
        hud.kills = player.kills
        hud.deaths = player.deaths

        // کەمترین نەخشە
        buildMinimap()
    }

    // MARK: - Player

    private func updatePlayer(dt: Float) {
        guard player.alive else {
            player.respawnTimer -= Double(dt)
            hud.respawnIn = max(0, player.respawnTimer)
            if player.respawnTimer <= 0 {
                hud.respawnIn = nil
                spawn(player, at: farSpawn(from: player.root.position))
            }
            return
        }

        // ئامانجگرتن
        let (adx, ady) = input.consumeAim()
        let sens = Float(scoped ? settings.scopeSensitivity : settings.aimSensitivity)
        let inv: Float = settings.invertY ? -1 : 1
        let yawDelta = adx * sens * 0.0042
        let pitchDelta = ady * sens * 0.0042 * inv
        player.root.eulerAngles.y -= yawDelta
        pitch = min(1.35, max(-1.35, pitch + pitchDelta))

        // جوڵە
        let speed: Float = player.crouching ? 2.8 : 6.0
        var vel = SIMD3<Float>.zero
        if player.grounded {
            let mx = input.moveX, my = input.moveY
            let yaw = player.root.eulerAngles.y
            let fx = -sin(yaw), fz = -cos(yaw)
            let rx = cos(yaw), rz = -sin(yaw)
            vel = SIMD3(fx * -my + rx * mx, 0, fz * -my + rz * mx)
            let len = (vel.x * vel.x + vel.z * vel.z).squareRoot()
            if len > 1 { vel = SIMD3(vel.x / len, 0, vel.z / len) }
            vel *= speed
        }
        vel.y = player.velocityY
        player.velocityY -= 20 * dt
        var pos = SIMD3(player.root.position.x, player.root.position.y, player.root.position.z)
        pos += vel * dt
        if pos.y <= 0 {
            pos.y = 0
            player.velocityY = 0
            player.grounded = true
        }
        pos = arena.resolved(pos, radius: 0.42)
        player.root.position = SCNVector3(pos.x, pos.y, pos.z)

        // ئەنیمەیشنی ڕۆیشتن
        let speedNow = (vel.x * vel.x + vel.z * vel.z).squareRoot()
        player.walkPhase += Double(speedNow * dt * 2.2)
        animateWalk(player, speed: speedNow)

        // تەقەکردن
        fireTimer -= Double(dt)
        reloadTimer -= Double(dt)
        if reloadTimer <= 0 && hud.reloading {
            hud.reloading = false
            ammo = weaponKind.spec.magSize
            hud.ammo = ammo
        }
        if input.fireDown && ammo > 0 && !hud.reloading && fireTimer <= 0 {
            firePlayerShot()
        }
        if ammo == 0 && !hud.reloading && input.fireDown {
            startReload()
        }

        // دەرکەوتنی چەک بەپێی POV
        let tppBody = hud.tpp && !scoped
        viewmodelGun?.isHidden = tppBody
        showBodyGun(!tppBody)
    }

    private func startReload() {
        guard !hud.reloading, ammo < weaponKind.spec.magSize else { return }
        hud.reloading = true
        reloadTimer = weaponKind.spec.reloadTime
        SoundEngine.shared.play(.reload)
    }

    private func animateWalk(_ e: Entity, speed: Float) {
        guard let legL = e.root.childNode(withName: "\(e.id)_legL", recursively: false),
              let legR = e.root.childNode(withName: "\(e.id)_legR", recursively: false),
              let armL = e.root.childNode(withName: "\(e.id)_armL", recursively: false),
              let armR = e.root.childNode(withName: "\(e.id)_armR", recursively: false) else { return }
        let swing = sin(e.walkPhase) * min(speed / 3, 1) * 0.75
        legL.eulerAngles.x = swing
        legR.eulerAngles.x = -swing
        armL.eulerAngles.x = -swing * 0.6
        armR.eulerAngles.x = swing * 0.6
    }

    private func showBodyGun(_ hidden: Bool) {
        guard let gun = player.root.childNode(withName: "player_gunHolder", recursively: false) else { return }
        gun.isHidden = hidden
    }

    // MARK: - Shooting (player)

    private func firePlayerShot() {
        let spec = weaponKind.spec
        ammo -= 1
        hud.ammo = ammo
        fireTimer = spec.fireInterval

        // ریکۆیل
        let recoilScale: Float = scoped ? 0.75 : 1.5
        pitch += Float.random(in: 0...1) * spec.verticalRecoil * recoilScale
        let horiz = Float.random(in: -1...1) * spec.horizontalRecoil * recoilScale
        player.root.eulerAngles.y += horiz
        pitch = min(1.35, max(-1.35, pitch))
        shake = min(shake + 0.035, 0.09)

        // بڵاوبوونەوە
        var spread = scoped ? spec.adsSpread : spec.baseSpread
        if !player.grounded { spread *= 1.5 }
        if player.crouching { spread *= 0.65 }

        let origin = cameraNode.presentation.worldPosition
        let dir0 = cameraForward()
        let dir = cone(dir0, spread: Float(spread))

        raycastShot(from: origin, dir: dir, damageBase: spec.damage, range: spec.range,
                    headshotMult: spec.headshotMult, shooter: "player",
                    tracerFrom: gunMuzzleWorld())

        SoundEngine.shared.play(weaponKind == .akm ? .shotAKM : .shotM416)
        muzzleFlash()
    }

    private func gunMuzzleWorld() -> SIMD3<Float> {
        if let gun = viewmodelGun, !gun.isHidden {
            let p = gun.worldPosition
            return SIMD3(p.x, p.y, p.z - 0.55)
        }
        if let gun = player.root.childNode(withName: "player_gunHolder", recursively: false) {
            let p = gun.worldPosition
            return SIMD3(p.x, p.y, p.z - 0.55)
        }
        return cameraPosition() + cameraForward() * 0.5
    }

    private func cameraPosition() -> SIMD3<Float> {
        let p = cameraNode.presentation.worldPosition
        return SIMD3(p.x, p.y, p.z)
    }

    private func cameraForward() -> SIMD3<Float> {
        let node = cameraNode.presentation
        let m = node.worldTransform
        return SIMD3(-m.m31, -m.m32, -m.m33)
    }

    private func cone(_ dir: SIMD3<Float>, spread: Float) -> SIMD3<Float> {
        let a1 = Float.random(in: 0...1) * .pi * 2
        let a2 = Float.random(in: 0...1) * spread
        // بنیاتنان لەسەر بنەمای دەرچووی ڕاست و سەر
        var up = SIMD3<Float>(0, 1, 0)
        if abs(dot(dir, up)) > 0.98 { up = SIMD3(1, 0, 0) }
        let right = normalize(cross(dir, up))
        let realUp = normalize(cross(right, dir))
        let d = normalize(dir) * cos(a2) + (right * cos(a1) + realUp * sin(a1)) * sin(a2)
        return normalize(d)
    }

    private func raycastShot(from origin: SIMD3<Float>, dir: SIMD3<Float>,
                             damageBase: Double, range: Double,
                             headshotMult: Double, shooter: String,
                             tracerFrom: SIMD3<Float>) {
        let far = origin + dir * Float(range * 3)
        let hits = scene.rootNode.hitTestWithSegment(
            from: SCNVector3(origin.x, origin.y, origin.z),
            to: SCNVector3(far.x, far.y, far.z),
            options: [.searchMode: SCNHitTestSearchMode.all.rawValue, .categoryBitMask: 4 | 8 | 16 | 32]
        )

        guard let first = hits.first else {
            drawTracer(from: tracerFrom, to: far)
            return
        }

        let hitNode = first.node
        let hitPos = SIMD3(first.worldCoordinates.x, first.worldCoordinates.y, first.worldCoordinates.z)
        let dist = length(hitPos - origin)

        // دیاریکردنی خاوەنی پارچەکە
        let owner = ownerOf(hitNode)
        if owner == "player" && shooter != "player" {
            // بۆتەکان لێی دەدەن — لە updateBots دا بەڕێوە دەچێت
        }
        if owner != nil && owner != shooter {
            let headshot = hitNode.name?.hasSuffix("_head") == true || hitNode.name?.hasSuffix("_helmet") == true
            var dmg = damageBase * (1 - min(Double(dist) / range, 0.55))
            if headshot { dmg *= headshotMult }
            applyDamage(to: owner!, amount: dmg, from: shooter, headshot: headshot)
            SoundEngine.shared.play(.hit)
        }
        drawTracer(from: tracerFrom, to: hitPos)
        impact(at: hitPos)
    }

    private func ownerOf(_ node: SCNNode) -> String? {
        var n: SCNNode? = node
        while let cur = n {
            if let name = cur.name {
                if name == "player" || name == "opponent" || name.hasPrefix("bot") {
                    return name
                }
            }
            n = cur.parent
        }
        return nil
    }

    private func applyDamage(to id: String, amount: Double, from: String, headshot: Bool) {
        if id == "player" {
            guard player.alive else { return }
            player.hp -= amount
            player.lastDamager = from
            damagePulse = 1
            SoundEngine.shared.play(.hurt)
            if player.hp <= 0 {
                kill(entity: player, by: from, headshot: headshot)
            }
        } else if id == "opponent" {
            // لە ١ڤ١ دا: زیانەکە بۆ لاکەی تر دەنێردرێت
            netSession?.send(.shot(damage: amount, headshot: headshot, from: "player"), reliable: true)
        } else if let idx = botIndex(forId: id), idx < bots.count {
            let bot = bots[idx]
            guard bot.alive else { return }
            bot.hp -= amount
            bot.lastDamager = from
            if bot.hp <= 0 {
                kill(entity: bot, by: from, headshot: headshot)
            }
        }
    }

    private func kill(entity: Entity, by killer: String, headshot: Bool) {
        entity.alive = false
        entity.deaths += 1
        entity.respawnTimer = 4.0
        entity.root.isHidden = true

        // ئەنجامی کوشتن
        if killer == "player" {
            player.kills += 1
            let name = entity.id == "opponent" ? "هاوڕێ" : (botAIs[safeBotIndex(entity.id)].name)
            hud.addFeed(headshot ? "🔫 تۆ \(name)ت بە سەر کوشت!" : "🔫 تۆ \(name)ت کوشت")
        } else if entity.id == "player" {
            let killerName = killer == "opponent" ? "هاوڕێ" : botAIs[safeBotIndex(killer)].name
            hud.addFeed(headshot ? "💀 \(killerName) بە سەر کوشتیت" : "💀 \(killerName) کوشتیت")
        }

        // خاڵ بۆ بکوژ
        if entity.id == "player" && killer == "opponent" {
            netSession?.send(.died(killer: "player"), reliable: true)
        }
        if killer.hasPrefix("bot"), let idx = botIndex(forId: killer), idx < bots.count {
            bots[idx].kills += 1
        }
        if entity.id.hasPrefix("bot"), let idx = botIndex(forId: entity.id) {
            botAIs[idx].markDead()
        }
        SoundEngine.shared.play(.kill)
    }

    private func safeBotIndex(_ id: String) -> Int {
        max(0, botIndex(forId: id) ?? 0)
    }

    // MARK: - Bots

    private func updateBots(dt: Float) {
        let playerPos = SIMD3(player.root.position.x, player.root.position.y, player.root.position.z)
        let playerHead = playerPos + SIMD3(0, 1.55, 0)

        for i in 0..<bots.count {
            let bot = bots[i]
            let ai = botAIs[i]
            guard bot.alive else {
                bot.respawnTimer -= Double(dt)
                if bot.respawnTimer <= 0 {
                    spawn(bot, at: farSpawn(from: player.root.position))
                }
                continue
            }

            let botPos = SIMD3(bot.root.position.x, bot.root.position.y, bot.root.position.z)
            let dist = length(playerHead - botPos)
            let los = player.alive && dist < 90 && arena.hasLOS(botPos + SIMD3(0, 1.4, 0), playerHead)

            let vel = ai.update(dt: Double(dt),
                                botPos: botPos,
                                playerPos: playerPos,
                                playerAlive: player.alive,
                                los: los,
                                distance: dist,
                                arena: arena,
                                allBots: botAIs)

            var newPos = botPos + vel * dt
            newPos.y = 0
            newPos = arena.resolved(newPos, radius: 0.42)
            bot.root.position = SCNVector3(newPos.x, 0, newPos.z)

            // بەرەوڕووبوون بە یاریزان کاتێک دەیبینێت
            if los {
                let dx = playerPos.x - newPos.x
                let dz = playerPos.z - newPos.z
                bot.root.eulerAngles.y = atan2(-dx, -dz)
            } else if vel.x != 0 || vel.z != 0 {
                bot.root.eulerAngles.y = atan2(-vel.x, -vel.z)
            }

            // ئەنیمەیشن
            let speed = (vel.x * vel.x + vel.z * vel.z).squareRoot()
            bot.walkPhase += Double(speed * dt * 2.2)
            animateWalk(bot, speed: speed)

            // تەقەی بۆت
            if ai.wantsToShoot && player.alive {
                botShot(bot: bot, ai: ai)
            }
        }
    }

    private func botShot(bot: Entity, ai: BotAI) {
        let muzzle = SIMD3(bot.root.position.x, bot.root.position.y + 1.15, bot.root.position.z)
        let target = ai.aimPoint
        let dir = normalize(target - muzzle)
        let far = muzzle + dir * 200

        let hits = scene.rootNode.hitTestWithSegment(
            from: SCNVector3(muzzle.x, muzzle.y, muzzle.z),
            to: SCNVector3(far.x, far.y, far.z),
            options: [.searchMode: SCNHitTestSearchMode.all.rawValue, .categoryBitMask: 2 | 16 | 32]
        )
        if let first = hits.first {
            let hitPos = SIMD3(first.worldCoordinates.x, first.worldCoordinates.y, first.worldCoordinates.z)
            drawTracer(from: muzzle, to: hitPos, color: UIColor(red: 1, green: 0.7, blue: 0.3, alpha: 1))
            let owner = ownerOf(first.node)
            if owner == "player" {
                let headshot = first.node.name?.hasSuffix("_head") == true || first.node.name?.hasSuffix("_helmet") == true
                var dmg = ai.damage
                if headshot { dmg *= 1.8 }
                applyDamage(to: "player", amount: dmg, from: bot.id, headshot: headshot)
            } else {
                impact(at: hitPos)
            }
        } else {
            drawTracer(from: muzzle, to: far, color: UIColor(red: 1, green: 0.7, blue: 0.3, alpha: 1))
        }
        SoundEngine.shared.play(.shotAKM)
    }

    // MARK: - Camera

    private func updateCamera(dt: Float) {
        let headY: Float = player.crouching ? 1.05 : 1.65
        let targetHead = SIMD3(player.root.position.x, player.root.position.y + headY, player.root.position.z)

        if !hud.tpp || scoped {
            // FPP
            cameraHolder.position = SCNVector3(targetHead.x, targetHead.y, targetHead.z)
            cameraHolder.eulerAngles.y = player.root.eulerAngles.y
            cameraNode.position = SCNVector3(0, 0, 0)
            cameraNode.eulerAngles.x = pitch
            cameraNode.eulerAngles.y = 0
            cameraNode.eulerAngles.z = 0
            let fovTarget = scoped ? ScopeKind.allCases[scopeIndex].fov : 68
            cameraNode.camera?.fieldOfView = fovTarget
        } else {
            // TPP
            cameraHolder.position = SCNVector3(targetHead.x, targetHead.y, targetHead.z)
            cameraHolder.eulerAngles.y = player.root.eulerAngles.y
            cameraHolder.eulerAngles.x = pitch * 0.85
            let dist: Float = player.crouching ? 2.6 : 3.3
            let desired = SCNVector3(0, 1.35, dist)

            // کۆسپی کامێرا
            let camWorld = cameraHolder.convertPosition(desired, to: scene.rootNode)
            let targetWorld = cameraHolder.convertPosition(SCNVector3(0, 1.2, 0), to: scene.rootNode)
            let hits = scene.rootNode.hitTestWithSegment(
                from: targetWorld, to: camWorld,
                options: [.searchMode: SCNHitTestSearchMode.all.rawValue, .categoryBitMask: 16]
            )
            if let first = hits.first {
                let p = first.worldCoordinates
                let dx = p.x - targetWorld.x
                let dy = p.y - targetWorld.y
                let dz = p.z - targetWorld.z
                let hitDist = (dx * dx + dy * dy + dz * dz).squareRoot()
                cameraNode.position = SCNVector3(0, 1.35, max(0.6, hitDist - 0.25))
            } else {
                cameraNode.position = desired
            }
            cameraNode.eulerAngles = SCNVector3(pitch * 0.3, 0, 0)
            cameraNode.camera?.fieldOfView = 72
        }

        // لەرزین
        if shake > 0 {
            let s = shake
            cameraNode.position.x += Float.random(in: -s...s) * 0.5
            cameraNode.position.y += Float.random(in: -s...s) * 0.5
        }
    }

    // MARK: - Effects

    private func drawTracer(from: SIMD3<Float>, to: SIMD3<Float>, color: UIColor = UIColor(red: 1, green: 0.92, blue: 0.6, alpha: 0.95)) {
        let dir = to - from
        let len = length(dir)
        guard len > 0.1 else { return }
        let mid = (from + to) * 0.5
        let box = SCNBox(width: 0.016, height: 0.016, length: CGFloat(len), chamferRadius: 0)
        box.firstMaterial?.diffuse.contents = color
        box.firstMaterial?.emission.contents = color
        box.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(mid.x, mid.y, mid.z)
        node.look(at: SCNVector3(to.x, to.y, to.z))
        scene.rootNode.addChildNode(node)
        node.runAction(.sequence([
            .fadeOpacity(to: 0, duration: 0.09),
            .removeFromParentNode()
        ]))
    }

    private func impact(at pos: SIMD3<Float>) {
        let spark = SCNParticleSystem()
        spark.birthRate = 40
        spark.particleLifeSpan = 0.35
        spark.emissionDuration = 0.08
        spark.particleSize = 0.035
        spark.particleColor = UIColor(red: 1, green: 0.85, blue: 0.55, alpha: 1)
        spark.particleVelocity = 1.6
        spark.spreadingAngle = 60
        spark.emitterShape = SCNSphere(radius: 0.02)
        let node = SCNNode()
        node.position = SCNVector3(pos.x, pos.y, pos.z)
        scene.rootNode.addChildNode(node)
        node.addParticleSystem(spark)
        node.runAction(.sequence([.wait(duration: 0.5), .removeFromParentNode()]))
    }

    private func muzzleFlash() {
        guard let gun = viewmodelGun, !gun.isHidden else {
            flashAt(SIMD3(player.root.position.x, player.root.position.y + 1.2, player.root.position.z))
            return
        }
        let p = gun.worldPosition
        flashAt(SIMD3(p.x, p.y, p.z - 0.5))
    }

    private func flashAt(_ pos: SIMD3<Float>) {
        let flash = SCNParticleSystem()
        flash.birthRate = 120
        flash.particleLifeSpan = 0.06
        flash.emissionDuration = 0.04
        flash.particleSize = 0.05
        flash.particleColor = UIColor(red: 1, green: 0.8, blue: 0.4, alpha: 1)
        flash.particleVelocity = 2.5
        flash.spreadingAngle = 25
        flash.emitterShape = SCNSphere(radius: 0.015)
        let node = SCNNode()
        node.position = SCNVector3(pos.x, pos.y, pos.z)
        scene.rootNode.addChildNode(node)
        node.addParticleSystem(flash)
        node.runAction(.sequence([.wait(duration: 0.12), .removeFromParentNode()]))
    }

    // MARK: - Minimap

    private func buildMinimap() {
        var entries: [MiniEntry] = []
        entries.append(MiniEntry(x: player.root.position.x, z: player.root.position.z,
                                 color: Color(red: 0.2, green: 0.85, blue: 0.95), isPlayer: true, isOpponent: false))
        let botColors: [Color] = [
            Color(red: 0.65, green: 0.65, blue: 0.68),
            Color(red: 0.4, green: 0.85, blue: 0.45),
            Color(red: 0.35, green: 0.6, blue: 1.0),
            Color(red: 1.0, green: 0.3, blue: 0.3)
        ]
        for (i, bot) in bots.enumerated() where bot.alive {
            entries.append(MiniEntry(x: bot.root.position.x, z: bot.root.position.z,
                                     color: botColors[min(i, botColors.count - 1)], isPlayer: false, isOpponent: false))
        }
        if let opp = opponent, oppAlive {
            entries.append(MiniEntry(x: opp.root.position.x, z: opp.root.position.z,
                                     color: Color(red: 1, green: 0.55, blue: 0.2), isPlayer: false, isOpponent: true))
        }
        hud.minimap = entries
    }

    // MARK: - LAN ١ڤ١

    private func updateOpponentVisual(dt: Double) {
        guard let opp = opponent else { return }
        let current = SIMD3(opp.root.position.x, opp.root.position.y, opp.root.position.z)
        let t = Float(min(dt * 12, 1))
        let newPos = current + (oppTargetPos - current) * t
        opp.root.position = SCNVector3(newPos.x, newPos.y, newPos.z)
        opp.root.eulerAngles.y = oppYaw
        opp.root.isHidden = !oppAlive
        if oppFiring {
            oppFireFlash -= dt
            if oppFireFlash <= 0 { oppFiring = false }
        }
    }

    private func updateNet(dt: Double) {
        guard let netSession else { return }
        lastStateSent += dt
        if lastStateSent >= 1.0 / 15.0 {
            lastStateSent = 0
            let st = NetPlayerState(
                x: player.root.position.x, y: player.root.position.y, z: player.root.position.z,
                yaw: player.root.eulerAngles.y, pitch: pitch,
                hp: player.hp, alive: player.alive, scoped: scoped,
                weapon: weaponKind.rawValue,
                kills: player.kills, deaths: player.deaths,
                clock: matchTime, firing: input.fireDown
            )
            netSession.send(.state(st))
        }
        hud.kills = player.kills
        hud.deaths = player.deaths
    }

    private func handleNet(_ msg: NetMsg) {
        switch msg {
        case .hello:
            break
        case .start:
            break
        case .state(let st):
            oppTargetPos = SIMD3(st.x, st.y, st.z)
            oppYaw = st.yaw
            oppHp = st.hp
            oppAlive = st.alive
            oppWeapon = st.weapon
            if st.firing { oppFiring = true; oppFireFlash = 0.15 }
            // کاتی خانەخوێ بەسەر میواندا دەسەپێنرێت
            if netSession?.isHost == false {
                matchTime = st.clock
            }
        case .shot(let damage, let headshot, _):
            guard player.alive else { return }
            player.hp -= damage
            damagePulse = 1
            SoundEngine.shared.play(.hurt)
            if player.hp <= 0 {
                kill(entity: player, by: "opponent", headshot: headshot)
            }
        case .died:
            // پەیامەکە واتە: "نێرەرەکە بەهۆی تۆوە مرد" — خاڵ بۆ تۆ
            player.kills += 1
            hud.addFeed("🔫 تۆ هاوڕێت کوشت")
        case .end(let result):
            hud.winnerText = result.winner
            hud.ranking = result.kills.map { name, kills in
                RankRow(name: name, kills: kills, deaths: 0, isPlayer: name == settings.playerName)
            }.sorted { $0.kills > $1.kills }
            hud.gameOver = true
        }
    }

    // MARK: - Match end & restart

    private func endMatch() {
        over = true
        if netSession == nil {
            var rows: [RankRow] = []
            rows.append(RankRow(name: "تۆ", kills: player.kills, deaths: player.deaths, isPlayer: true))
            for (i, bot) in bots.enumerated() {
                rows.append(RankRow(name: botAIs[i].name, kills: bot.kills, deaths: bot.deaths, isPlayer: false))
            }
            rows.sort { $0.kills > $1.kills }
            hud.ranking = rows
            hud.winnerText = rows.first?.isPlayer == true ? "🏆 براوە: تۆ" : "🏆 بۆتەکان بردیانەوە"
            hud.gameOver = true
        } else {
            let myKills = player.kills
            let myName = settings.playerName
            netSession?.send(.end(NetResult(winner: myName, kills: [myName: myKills])), reliable: true)
            hud.ranking = [RankRow(name: myName, kills: myKills, deaths: player.deaths, isPlayer: true)]
            hud.gameOver = true
        }
    }

    private func restartMatch() {
        over = false
        hud.gameOver = false
        matchTime = Double((netCfg?.minutes ?? settings.matchMinutes)) * 60
        player.kills = 0
        player.deaths = 0
        spawn(player, at: arena.spawns[Int.random(in: 0..<arena.spawns.count)])
        for (i, bot) in bots.enumerated() {
            bot.kills = 0
            bot.deaths = 0
            spawn(bot, at: arena.spawns[(i + 2) % arena.spawns.count])
        }
        ammo = weaponKind.spec.magSize
        hud.ammo = ammo
        hud.feed = []
        hud.paused = false
    }

    @inline(__always)
    private func normalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let l = length(v)
        return l > 0.0001 ? v / l : .zero
    }

    @inline(__always)
    private func length(_ v: SIMD3<Float>) -> Float {
        (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
    }
}
