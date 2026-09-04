import SwiftUI
import SceneKit

/// ئاستەکانی کوالیتی وێنە
enum QualityLevel: String, CaseIterable, Identifiable {
    case low = "نزم (Low)"
    case hd = "HD"
    case hdr = "HDR"
    case uhd = "UHD"

    var id: String { rawValue }

    var antialiasing: SCNAntialiasingMode {
        switch self {
        case .low:  return .none
        case .hd:   return .multisampling2X
        case .hdr:  return .multisampling4X
        case .uhd:  return .multisampling4X
        }
    }

    var shadowMap: Int {
        switch self {
        case .low:  return 512
        case .hd:   return 1024
        case .hdr:  return 2048
        case .uhd:  return 2048
        }
    }

    var shadowOn: Bool { self != .low }
}

/// مۆدی FPS
enum FPSMode: String, CaseIterable, Identifiable {
    case auto = "خۆکار (Auto)"
    case f30 = "30 FPS"
    case f45 = "45 FPS"
    case f60 = "60 FPS"
    case f90 = "90 FPS"
    case f120 = "120 FPS"

    var id: String { rawValue }

    func targetFPS(deviceMax: Int) -> Int {
        switch self {
        case .auto: return deviceMax
        case .f30:  return 30
        case .f45:  return 45
        case .f60:  return 60
        case .f90:  return min(90, deviceMax)
        case .f120: return min(120, deviceMax)
        }
    }
}

/// ئاستی بۆتەکان — ١=خراپ، ٢=باش، ٣=زۆر باش، ٤=ئەستێرەیی (زیرەکتر لە مرۆڤ)
enum BotLevel: Int, CaseIterable, Identifiable {
    case easy = 1, normal = 2, hard = 3, insane = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .easy:   return "١ — خراپ (سەرەتایی)"
        case .normal: return "٢ — باش"
        case .hard:   return "٣ — زۆر باش"
        case .insane: return "٤ — ئەستێرەیی (زیرەکتر لە مرۆڤ)"
        }
    }
}

/// قەبارەی ئەرێنا
enum ArenaSize: String, CaseIterable, Identifiable {
    case small = "بچووک (40م)"
    case medium = "مامناوەند (60م)"
    case large = "گەورە (80م)"

    var id: String { rawValue }
    var meters: Float {
        switch self {
        case .small:  return 40
        case .medium: return 60
        case .large:  return 80
        }
    }
}

/// ڕێکخستنەکانی یاری — هەموو لە UserDefaults پارێزراون
final class GameSettings: ObservableObject {
    @Published var aimSensitivity: Double { didSet { save() } }
    @Published var scopeSensitivity: Double { didSet { save() } }
    @Published var invertY: Bool { didSet { save() } }
    @Published var quality: QualityLevel { didSet { save() } }
    @Published var fpsMode: FPSMode { didSet { save() } }
    @Published var defaultTPP: Bool { didSet { save() } }
    @Published var volume: Double { didSet { save() } }
    @Published var botLevel: BotLevel { didSet { save() } }
    @Published var arenaSize: ArenaSize { didSet { save() } }
    @Published var matchMinutes: Int { didSet { save() } }
    @Published var defaultWeapon: String { didSet { save() } }
    @Published var playerName: String { didSet { save() } }

    init() {
        let d = UserDefaults.standard
        aimSensitivity = d.object(forKey: "aimSens") as? Double ?? 1.0
        scopeSensitivity = d.object(forKey: "scopeSens") as? Double ?? 0.55
        invertY = d.bool(forKey: "invertY")
        quality = QualityLevel(rawValue: d.string(forKey: "quality") ?? "") ?? .hd
        fpsMode = FPSMode(rawValue: d.string(forKey: "fps") ?? "") ?? .auto
        defaultTPP = d.object(forKey: "defaultTPP") as? Bool ?? true
        volume = d.object(forKey: "volume") as? Double ?? 0.8
        botLevel = BotLevel(rawValue: d.integer(forKey: "botLevel")) ?? .normal
        arenaSize = ArenaSize(rawValue: d.string(forKey: "arena") ?? "") ?? .medium
        matchMinutes = d.object(forKey: "minutes") as? Int ?? 5
        defaultWeapon = d.string(forKey: "weapon") ?? "M416"
        playerName = d.string(forKey: "playerName") ?? UIDevice.current.name
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(aimSensitivity, forKey: "aimSens")
        d.set(scopeSensitivity, forKey: "scopeSens")
        d.set(invertY, forKey: "invertY")
        d.set(quality.rawValue, forKey: "quality")
        d.set(fpsMode.rawValue, forKey: "fps")
        d.set(defaultTPP, forKey: "defaultTPP")
        d.set(volume, forKey: "volume")
        d.set(botLevel.rawValue, forKey: "botLevel")
        d.set(arenaSize.rawValue, forKey: "arena")
        d.set(matchMinutes, forKey: "minutes")
        d.set(defaultWeapon, forKey: "weapon")
        d.set(playerName, forKey: "playerName")
    }

    var deviceMaxFPS: Int {
        let max = UIScreen.main.maximumFramesPerSecond
        return max > 0 ? max : 60
    }
}
