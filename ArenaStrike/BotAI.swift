import Foundation
import SceneKit
import simd

/// ئەی ئای بۆتەکان — ٤ ئاست + ڕۆڵی هەڕەمەکی لە هەر سپاونێک
final class BotAI {
    enum Role { case rusher, flanker, marksman, defender }

    let id: String                 // "bot0".."bot3"
    let level: BotLevel
    var role: Role = .rusher

    // دۆخەکان
    private enum State { case patrol, engage, reposition, dead }
    private var state: State = .patrol

    // تایمەرەکان
    private var reactionTimer: Double = 0
    private var shootTimer: Double = 0
    private var burstLeft: Int = 0
    private var burstPause: Double = 0
    private var strafeTimer: Double = 0
    private var strafeDir: Float = 1
    private var flankTimer: Double = 0
    private var idleTimer: Double = 0
    private var lastPos: SIMD3<Float> = .zero

    // ڕێڕەو
    var targetWaypoint = -1
    private var path: [Int] = []
    private var pathIndex = 0

    // داتای شەڕ (بۆ بزوێنەرەکە دەخوێندرێتەوە)
    var wantsToShoot = false
    var aimPoint = SIMD3<Float>.zero
    var currentPos = SIMD3<Float>.zero
    var visibleToPlayer = false
    var moving: SIMD3<Float> = .zero

    init(id: String, level: BotLevel) {
        self.id = id
        self.level = level
    }

    var name: String {
        switch level {
        case .easy:   return "بۆت (خراپ)"
        case .normal: return "بۆت (باش)"
        case .hard:   return "بۆت (زۆرباش)"
        case .insane: return "بۆت (ئەستێرەیی)"
        }
    }

    // ڕێکخستنەکان بەپێی ئاست
    private var moveSpeed: Float {
        switch level {
        case .easy: return 3.0
        case .normal: return 3.7
        case .hard: return 4.4
        case .insane: return 5.1
        }
    }
    private var reactionTime: Double {
        switch level {
        case .easy: return 1.15
        case .normal: return 0.65
        case .hard: return 0.38
        case .insane: return 0.14
        }
    }
    private var accuracyDeg: Float {
        switch level {
        case .easy: return 8.5
        case .normal: return 4.8
        case .hard: return 2.9
        case .insane: return 1.15
        }
    }
    private var fireInterval: Double {
        switch level {
        case .easy: return 0.34
        case .normal: return 0.22
        case .hard: return 0.15
        case .insane: return 0.10
        }
    }
    private var burstSize: Int {
        switch level {
        case .easy: return 2
        case .normal: return 3
        case .hard: return 5
        case .insane: return 9
        }
    }
    var damage: Double {
        switch level {
        case .easy: return 9
        case .normal: return 14
        case .hard: return 21
        case .insane: return 30
        }
    }
    private var headshotBias: Float {
        level == .insane ? 0.45 : 0.08
    }

    // MARK: - هەر سپاونێک: ڕۆڵی نوێ
    func onSpawn() {
        let roles: [Role] = [.rusher, .flanker, .marksman, .defender]
        role = roles.randomElement()!
        state = .patrol
        path = []
        targetWaypoint = -1
        reactionTimer = 0
        burstLeft = 0
        idleTimer = 0
    }

    func markDead() {
        state = .dead
        wantsToShoot = false
    }

    var isDead: Bool { state == .dead }

    // MARK: - نوێکردنەوەی سەرەکی
    /// گەڕاندنەوە: خێرایی جوڵە و ئەوەی ئایا تەقە بکات
    func update(dt: Double,
                botPos: SIMD3<Float>,
                playerPos: SIMD3<Float>,
                playerAlive: Bool,
                los: Bool,
                distance: Float,
                arena: ArenaData,
                allBots: [BotAI]) -> SIMD3<Float> {

        currentPos = botPos
        moving = .zero
        wantsToShoot = false
        visibleToPlayer = false

        let dirToPlayer = normalize(SIMD3(playerPos.x - botPos.x, 0, playerPos.z - botPos.z))

        // دژە-کۆبوونەوە: لە بۆتەکانی تر دوور بکەوەرەوە
        var repel = SIMD3<Float>.zero
        for other in allBots where other !== self {
            let dx = botPos.x - other.currentPos.x
            let dz = botPos.z - other.currentPos.z
            let d2 = dx * dx + dz * dz
            if d2 < 12.25 && d2 > 0.0001 {
                let d = d2.squareRoot()
                repel += SIMD3(dx / d, 0, dz / d) * (3.5 - d) / 3.5
            }
        }

        // هەرگیز نەوەست: ئەگەر جوڵە بڕوا — ڕێڕەوی نوێ
        idleTimer += dt
        if idleTimer > 1.2 {
            idleTimer = 0
            targetWaypoint = -1
        }

        switch state {
        case .dead:
            return .zero

        case .patrol:
            if playerAlive && los && distance < visionRange {
                state = .engage
                reactionTimer = reactionTime
                strafeTimer = 0
            } else {
                return moveAlongPath(dt: dt, pos: botPos, arena: arena) + repel
            }

        case .engage:
            visibleToPlayer = true
            reactionTimer -= dt
            if !playerAlive {
                state = .patrol
                return moveAlongPath(dt: dt, pos: botPos, arena: arena) + repel
            }
            if !los {
                // بەدوای ڕاوەکەدا بڕۆ — ڕاستەوخۆ بەرەو دوایین شوێنی بینراو
                idleTimer = 0
                return dirToPlayer * moveSpeed + repel
            }

            // مەودای ئارەزوومەند بەپێی ڕۆڵ
            let idealDist: Float
            switch role {
            case .rusher: idealDist = 8
            case .flanker: idealDist = 28
            case .marksman: idealDist = 48
            case .defender: idealDist = 20
            }

            var vel = SIMD3<Float>.zero
            if distance > idealDist + 4 {
                vel = dirToPlayer * moveSpeed
            } else if distance < idealDist - 6 {
                vel = -dirToPlayer * moveSpeed * 0.8
            } else {
                // سترەیف — هەرگیز لە جێگای خۆتدا وەستاو تەقە مەکە
                strafeTimer -= dt
                if strafeTimer <= 0 {
                    strafeTimer = Double.random(in: 0.7...1.6)
                    strafeDir = -strafeDir
                }
                vel = SIMD3(-dirToPlayer.z, 0, dirToPlayer.x) * strafeDir * moveSpeed * 0.75
            }

            // ئاستی بەرز: فلانک و کشانەوە
            flankTimer -= dt
            if level == .hard || level == .insane {
                if flankTimer <= 0 {
                    flankTimer = Double.random(in: 3.5...6.5)
                    if state == .engage {
                        state = .reposition
                        targetWaypoint = pickFlankWaypoint(pos: botPos, playerPos: playerPos, arena: arena)
                    }
                }
            }

            // تەقە
            if reactionTimer <= 0 {
                if burstPause > 0 {
                    burstPause -= dt
                } else {
                    shootTimer -= dt
                    if shootTimer <= 0 {
                        if burstLeft <= 0 {
                            burstLeft = Int.random(in: 1...burstSize)
                            burstPause = Double.random(in: 0.25...0.8)
                        } else {
                            burstLeft -= 1
                            shootTimer = fireInterval
                            wantsToShoot = true
                            aimPoint = computeAimPoint(botPos: botPos, playerPos: playerPos)
                        }
                    }
                }
            }
            return vel + repel

        case .reposition:
            if playerAlive && los && flankTimer < -1.5 {
                state = .engage
                reactionTimer = 0.05
            }
            let mv = moveAlongPath(dt: dt, pos: botPos, arena: arena)
            if mv == .zero {
                state = .engage
                flankTimer = Double.random(in: 3.5...6.5)
            }
            return mv + repel
        }

        return moving
    }

    private var visionRange: Float {
        level == .insane ? 100 : (level == .hard ? 85 : (level == .normal ? 70 : 50))
    }

    // MARK: - ڕێڕەو
    private func moveAlongPath(dt: Double, pos: SIMD3<Float>, arena: ArenaData) -> SIMD3<Float> {
        if targetWaypoint < 0 || path.isEmpty {
            chooseTarget(pos: pos, arena: arena)
        }
        guard pathIndex < path.count else {
            targetWaypoint = -1
            chooseTarget(pos: pos, arena: arena)
            return .zero
        }
        let wp = arena.waypoints[path[pathIndex]]
        let target = SIMD3(wp.x, 0, wp.z)
        let to = target - SIMD3(pos.x, 0, pos.z)
        let dist = length(to)
        if dist < 1.0 {
            pathIndex += 1
            return .zero
        }
        return normalize(to) * moveSpeed
    }

    private func chooseTarget(pos: SIMD3<Float>, arena: ArenaData) {
        guard !arena.waypoints.isEmpty else { return }
        // دوورترین خاڵ بە چەند هەڵبژاردەیەکی هەڕەمەکی — بۆ دابەشبوونی بۆتەکان
        var best = -1
        var bestDist: Float = -1
        for _ in 0..<6 {
            let i = Int.random(in: 0..<arena.waypoints.count)
            let wp = arena.waypoints[i]
            let d = (wp.x - pos.x) * (wp.x - pos.x) + (wp.z - pos.z) * (wp.z - pos.z)
            if d > bestDist { bestDist = d; best = i }
        }
        targetWaypoint = best
        path = findPath(from: pos, to: best, arena: arena)
        pathIndex = 0
    }

    private func pickFlankWaypoint(pos: SIMD3<Float>, playerPos: SIMD3<Float>, arena: ArenaData) -> Int {
        // خاڵێک کە گۆشەیەکی نوێ دەدات بە بەرامبەر یاریزانەکە
        var candidates: [Int] = []
        for (i, wp) in arena.waypoints.enumerated() {
            let dx = wp.x - pos.x, dz = wp.z - pos.z
            let d2 = dx * dx + dz * dz
            if d2 > 100 && d2 < 1600 {
                candidates.append(i)
            }
        }
        guard !candidates.isEmpty else {
            return Int.random(in: 0..<arena.waypoints.count)
        }
        return candidates.randomElement()!
    }

    /// A* سادە لەسەر گرافی ڕێڕەوەکان
    private func findPath(from pos: SIMD3<Float>, to target: Int, arena: ArenaData) -> [Int] {
        // نزیکترین خاڵ بە پێگەی ئێستا
        var start = -1
        var best: Float = .greatestFiniteMagnitude
        for (i, wp) in arena.waypoints.enumerated() {
            let d = (wp.x - pos.x) * (wp.x - pos.x) + (wp.z - pos.z) * (wp.z - pos.z)
            if d < best { best = d; start = i }
        }
        guard start >= 0 else { return [target] }

        var open: [Int] = [start]
        var cameFrom: [Int: Int] = [:]
        var gScore: [Int: Float] = [start: 0]
        var fScore: [Int: Float] = [start: heuristic(start, target, arena)]

        while !open.isEmpty {
            open.sort { (fScore[$0] ?? .greatestFiniteMagnitude) < (fScore[$1] ?? .greatestFiniteMagnitude) }
            let current = open.removeFirst()
            if current == target {
                var path: [Int] = [current]
                var c = current
                while let prev = cameFrom[c] {
                    path.append(prev)
                    c = prev
                }
                return path.reversed()
            }
            for nb in arena.waypoints[current].neighbors {
                let tentative = (gScore[current] ?? .greatestFiniteMagnitude) + 4
                if tentative < (gScore[nb] ?? .greatestFiniteMagnitude) {
                    cameFrom[nb] = current
                    gScore[nb] = tentative
                    fScore[nb] = tentative + heuristic(nb, target, arena)
                    if !open.contains(nb) { open.append(nb) }
                }
            }
        }
        return [target]
    }

    private func heuristic(_ a: Int, _ b: Int, _ arena: ArenaData) -> Float {
        let wa = arena.waypoints[a], wb = arena.waypoints[b]
        return abs(wa.x - wb.x) + abs(wa.z - wb.z)
    }

    // MARK: - مەبەستی ئامانجگرتن
    private func computeAimPoint(botPos: SIMD3<Float>, playerPos: SIMD3<Float>) -> SIMD3<Float> {
        let headPos = playerPos + SIMD3(0, 1.55, 0)
        // لەئاستی بەرزدا: بە مەیلی سەر
        let target = Float.random(in: 0...1) < headshotBias ? headPos : playerPos + SIMD3(0, 0.7, 0)
        // هەڵەی ئامانجگرتن بەپێی ئاست
        let err = accuracyDeg * .pi / 180
        let ang = Float.random(in: -err...err)
        let cosA = cos(ang), sinA = sin(ang)
        let d = target - botPos
        let rotX = SIMD3(d.x * cosA - d.z * sinA, d.y, d.x * sinA + d.z * cosA)
        return botPos + rotX
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
