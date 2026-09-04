import Foundation
import SceneKit
import simd

/// سنووقی AABB بۆ دژەبەیەکداچوون
struct AABB {
    var minX: Float, minZ: Float, maxX: Float, maxZ: Float

    func intersects(circleX: Float, circleZ: Float, radius: Float) -> Bool {
        let cx = min(max(circleX, minX), maxX)
        let cz = min(max(circleZ, minZ), maxZ)
        let dx = circleX - cx
        let dz = circleZ - cz
        return (dx * dx + dz * dz) < (radius * radius)
    }

    /// پاڵنانی خاڵەکە بۆ دەرەوەی سنووقەکە
    func pushOut(x: Float, z: Float, radius: Float) -> (Float, Float) {
        let cx = min(max(x, minX), maxX)
        let cz = min(max(z, minZ), maxZ)
        var dx = x - cx
        var dz = z - cz
        let d = (dx * dx + dz * dz).squareRoot()
        if d < 0.0001 {
            // ناوەندی سنووقەکە — بە باریکترین لای دەرکە
            let left = x - minX, right = maxX - x, top = z - minZ, bottom = maxZ - z
            let m = min(left, right, top, bottom)
            if m == left { dx = -(radius - left) } else if m == right { dx = radius - right } else if m == top { dz = -(radius - top) } else { dz = radius - bottom }
            return (x + dx, z + dz)
        }
        if d >= radius { return (x, z) }
        let push = radius - d
        if d == 0 { return (x + push, z) }
        return (x + dx / d * push, z + dz / d * push)
    }

    func segmentHits(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool {
        // تاقیکردنەوەی سادە: خاڵەکانی ناوەڕاستی پارچەکە لەناو سنووقەکەدان؟
        let steps = 8
        for i in 0...steps {
            let t = Float(i) / Float(steps)
            let p = a + (b - a) * t
            if p.x >= minX && p.x <= maxX && p.z >= minZ && p.z <= maxZ {
                return true
            }
        }
        return false
    }
}

/// خاڵی ڕێڕەو بۆ بۆتەکان
struct Waypoint {
    let x: Float
    let z: Float
    var neighbors: [Int] = []
}

/// داتای ئەرێنا — هەر یارییەک بە شێوەیەکی هەڕەمەکی ڕێکدەخرێت
struct ArenaData {
    var halfSize: Float
    var walls: [AABB] = []          // دیوارەکانی دەوروبەر
    var covers: [AABB] = []         // کۆسپەکان
    var coverNodes: [SCNNode] = []
    var waypoints: [Waypoint] = []
    var spawns: [SIMD3<Float>] = []

    /// پاککردنەوەی پێگەیەک لە دژەبەیەکداچوون
    func resolved(_ pos: SIMD3<Float>, radius: Float = 0.5) -> SIMD3<Float> {
        var x = min(max(pos.x, -halfSize + radius), halfSize - radius)
        var z = min(max(pos.z, -halfSize + radius), halfSize - radius)
        for cover in covers {
            let (nx, nz) = cover.pushOut(x: x, z: z, radius: radius)
            x = nx; z = nz
        }
        return SIMD3(x, pos.y, z)
    }

    /// لەبەرچاو بوون — هیچ کۆسپێک لە نێوانیاندا نییە
    func hasLOS(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool {
        for cover in covers where cover.segmentHits(a, b) {
            return false
        }
        return true
    }
}

/// دروستکەری ئەرێنا
enum ArenaBuilder {

    static func build(scene: SCNScene, sizeMeters: Float, seed: UInt32) -> ArenaData {
        var data = ArenaData(halfSize: sizeMeters / 2)
        let h = data.halfSize

        // زەوی
        let ground = SCNNode(geometry: SCNPlane(width: CGFloat(sizeMeters), height: CGFloat(sizeMeters)))
        ground.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.16, green: 0.22, blue: 0.14, alpha: 1)
        ground.geometry?.firstMaterial?.roughness.contents = 0.95
        ground.geometry?.firstMaterial?.lightingModel = .physicallyBased
        ground.eulerAngles.x = -.pi / 2
        ground.name = "ground"
        ground.categoryBitMask = 32
        scene.rootNode.addChildNode(ground)

        // دیوارەکانی دەوروبەر
        let wallHeight: Float = 3.5
        let wallThick: Float = 0.6
        let wallMat = SCNMaterial()
        wallMat.diffuse.contents = UIColor(red: 0.38, green: 0.40, blue: 0.44, alpha: 1)
        wallMat.roughness.contents = 0.85
        wallMat.lightingModel = .physicallyBased

        func addWall(_ x: Float, _ z: Float, _ w: Float, _ d: Float) {
            let box = SCNNode(geometry: SCNBox(width: CGFloat(w), height: CGFloat(wallHeight), length: CGFloat(d), chamferRadius: 0))
            box.geometry?.materials = [wallMat]
            box.position = SCNVector3(x, wallHeight / 2, z)
            box.name = "wall"
            box.categoryBitMask = 16
            scene.rootNode.addChildNode(box)
            data.walls.append(AABB(minX: x - w / 2, minZ: z - d / 2, maxX: x + w / 2, maxZ: z + d / 2))
        }
        let full = sizeMeters + wallThick
        addWall(0, -h - wallThick / 2, full, wallThick)   // باکوور
        addWall(0, h + wallThick / 2, full, wallThick)    // باشوور
        addWall(-h - wallThick / 2, 0, wallThick, full)   // ڕۆژئاوا
        addWall(h + wallThick / 2, 0, wallThick, full)    // ڕۆژهەڵات

        // کۆسپەکان — کرات و کۆنتێنەر و دیواری کورت، بە شێوەی هەڕەمەکی بەڵام دیاریکراو بە seed
        var seed = seed
        func rnd() -> Float {
            seed = seed &* 1103515245 &+ 12345
            return Float((seed >> 16) & 0x7FFF) / 32767.0
        }

        let crateMat = SCNMaterial()
        crateMat.diffuse.contents = UIColor(red: 0.55, green: 0.42, blue: 0.24, alpha: 1)
        crateMat.roughness.contents = 0.9
        crateMat.lightingModel = .physicallyBased

        let containerMat = SCNMaterial()
        containerMat.diffuse.contents = UIColor(red: 0.32, green: 0.36, blue: 0.40, alpha: 1)
        containerMat.roughness.contents = 0.7
        containerMat.metalness.contents = 0.4
        containerMat.lightingModel = .physicallyBased

        let lowWallMat = SCNMaterial()
        lowWallMat.diffuse.contents = UIColor(red: 0.46, green: 0.46, blue: 0.50, alpha: 1)
        lowWallMat.roughness.contents = 0.85
        lowWallMat.lightingModel = .physicallyBased

        let margin: Float = 5
        let count = sizeMeters < 50 ? 10 : (sizeMeters < 70 ? 16 : 22)
        var attempts = 0
        while data.covers.count < count && attempts < 400 {
            attempts += 1
            let x = (rnd() * 2 - 1) * (h - margin)
            let z = (rnd() * 2 - 1) * (h - margin)
            // نزیک ناوەند نەبێت (ناوچەی سپاون سەرەتا)
            if abs(x) < 6 && abs(z) < 6 { continue }

            let kind = Int(rnd() * 3)
            var box: SCNNode
            var w: Float, d: Float, hh: Float
            switch kind {
            case 0:
                w = 1.4; d = 1.4; hh = 1.4
                box = SCNNode(geometry: SCNBox(width: CGFloat(w), height: CGFloat(hh), length: CGFloat(d), chamferRadius: 0.05))
                box.geometry?.materials = [crateMat]
            case 1:
                w = 5; d = 2.4; hh = 2.6
                box = SCNNode(geometry: SCNBox(width: CGFloat(w), height: CGFloat(hh), length: CGFloat(d), chamferRadius: 0.08))
                box.geometry?.materials = [containerMat]
            default:
                w = 3; d = 0.7; hh = 1.1
                box = SCNNode(geometry: SCNBox(width: CGFloat(w), height: CGFloat(hh), length: CGFloat(d), chamferRadius: 0.05))
                box.geometry?.materials = [lowWallMat]
            }

            let aabb = AABB(minX: x - w / 2 - 0.3, minZ: z - d / 2 - 0.3, maxX: x + w / 2 + 0.3, maxZ: z + d / 2 + 0.3)
            // ڕێگا نەگرێت بە نێوان کۆسپەکانی تر
            var ok = true
            for c in data.covers {
                let overlapX = aabb.minX < c.maxX && aabb.maxX > c.minX
                let overlapZ = aabb.minZ < c.maxZ && aabb.maxZ > c.minZ
                if overlapX && overlapZ { ok = false; break }
            }
            guard ok else { continue }

            box.position = SCNVector3(x, hh / 2, z)
            box.name = "cover"
            box.categoryBitMask = 16
            scene.rootNode.addChildNode(box)
            data.coverNodes.append(box)
            data.covers.append(aabb)
        }

        // خاڵەکانی ڕێڕەو — گریدی ٤ مەتری، خاڵەکانی ناو کۆسپ لادەبرێن
        let step: Float = 4
        let n = Int(sizeMeters / step) + 1
        for iz in 0..<n {
            for ix in 0..<n {
                let x = -h + Float(ix) * step
                let z = -h + Float(iz) * step
                var blocked = false
                for c in data.covers where c.intersects(circleX: x, circleZ: z, radius: 1.2) {
                    blocked = true; break
                }
                if !blocked {
                    data.waypoints.append(Waypoint(x: x, z: z))
                }
            }
        }
        // دراوسێکان: نزیکترین ٤ خاڵ کە بێ کۆسپ بن
        for (i, wp) in data.waypoints.enumerated() {
            for (j, other) in data.waypoints.enumerated() where j != i {
                let dx = wp.x - other.x
                let dz = wp.z - other.z
                let dist = (dx * dx + dz * dz).squareRoot()
                if dist <= step * 1.42 + 0.1 {
                    let a = SIMD3(wp.x, 1.5, wp.z)
                    let b = SIMD3(other.x, 1.5, other.z)
                    var blocked = false
                    for c in data.covers where c.segmentHits(a, b) {
                        blocked = true; break
                    }
                    if !blocked { data.waypoints[i].neighbors.append(j) }
                }
            }
        }

        // خاڵەکانی سپاون — گۆشەکان و ناوەڕاستەکان
        data.spawns = [
            SIMD3(-h + 5, 0, -h + 5),
            SIMD3(h - 5, 0, -h + 5),
            SIMD3(-h + 5, 0, h - 5),
            SIMD3(h - 5, 0, h - 5),
            SIMD3(0, 0, h - 5),
            SIMD3(0, 0, -h + 5),
            SIMD3(h - 5, 0, 0),
            SIMD3(-h + 5, 0, 0)
        ]

        return data
    }
}
