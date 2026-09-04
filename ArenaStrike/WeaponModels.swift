import Foundation

/// چەکەکان — M416 و AKM
/// هەموو باشترین ئەتاشمێنتەکان دانراون: کۆمپەنسەیتەر + گریپی ستوونی + گوڵەی درێژ + ستۆک
enum WeaponKind: String, CaseIterable {
    case m416 = "M416"
    case akm = "AKM"

    var spec: WeaponSpec {
        switch self {
        case .m416: return WeaponSpec(
            name: "M416",
            rpm: 750,               // گوڵە لە خولەکدا
            damage: 41,             // زیان لە مەودای نزیک
            range: 70,              // مەودای کاریگەر (مەتر)
            baseSpread: 0.035,      // بڵاوبوونەوە (ڕادیان) — هیپفایەر
            adsSpread: 0.008,
            verticalRecoil: 0.011,
            horizontalRecoil: 0.006,
            magSize: 40,            // گوڵەی درێژ
            reloadTime: 1.9,
            headshotMult: 2.2
        )
        case .akm: return WeaponSpec(
            name: "AKM",
            rpm: 600,
            damage: 48,
            range: 60,
            baseSpread: 0.05,
            adsSpread: 0.012,
            verticalRecoil: 0.02,
            horizontalRecoil: 0.011,
            magSize: 40,
            reloadTime: 2.3,
            headshotMult: 2.2
        )
        }
    }
}

struct WeaponSpec {
    let name: String
    let rpm: Double
    let damage: Double
    let range: Double
    let baseSpread: Double
    let adsSpread: Double
    let verticalRecoil: Double
    let horizontalRecoil: Double
    let magSize: Int
    let reloadTime: Double
    let headshotMult: Double

    var fireInterval: Double { 60.0 / rpm }
}

/// سکۆپەکان — هەموویان بەردەستن، سوڕانەوە بە دوگمە
enum ScopeKind: Int, CaseIterable {
    case iron = 0, holo, x2, x3, x4, x6, x8

    var name: String {
        switch self {
        case .iron: return "ئاسن (Iron)"
        case .holo: return "هۆلۆ (1x)"
        case .x2:   return "2x"
        case .x3:   return "3x"
        case .x4:   return "4x"
        case .x6:   return "6x"
        case .x8:   return "8x"
        }
    }

    /// زۆم بە گۆڕینی FOVـی کامێرا
    var fov: Double {
        switch self {
        case .iron: return 58
        case .holo: return 58
        case .x2:   return 42
        case .x3:   return 32
        case .x4:   return 24
        case .x6:   return 17
        case .x8:   return 13
        }
    }
}
