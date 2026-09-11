import Foundation

/// ڕێکخستنی ئەپەکە — ئەگەر ماڵپەڕەکە گۆڕا، تەنها ئێرە بگۆڕە
enum AppConfig {

    /// بەستەری سەرەکی کە ئەپەکە دەیکاتەوە
    static let startURL = URL(string: "https://rawandios.dev/vx/chat")!

    /// دۆمەینەکانی سەر بە ئەپەکە — لەناو ئەپەکەدا دەکرێنەوە
    static let internalHosts: Set<String> = [
        "rawandios.dev",
        "www.rawandios.dev",
    ]

    /// دۆمەینەکانی چوونەژوورەوە — لەناو ئەپەکەدا دەکرێنەوە بەڵام
    /// بە User-Agent ی Safari ی ڕەسەن (بۆ ئەوەی Google بلۆکی نەکات)
    static let authHosts: Set<String> = [
        "accounts.google.com",
        "accounts.youtube.com",
        "myaccount.google.com",
        "ssl.gstatic.com",
        "www.google.com",
        "apis.google.com",
        "content.googleapis.com",
        "oauth2.googleapis.com",
        "googleusercontent.com",
    ]

    /// User-Agent ی Safari ی ڕەسەنی iOS — Google چوونەژوورەوەی پێ ڕێگە دەدات
    static let safariUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    /// ڕەنگی پاشبنەما پێش بارکردنی ماڵپەڕەکە
    static let backgroundHex = "#0B0B14"
}

extension String {
    /// گەڕان بۆ ئەوەی هۆستێک سەر بەم کۆمەڵەیە یان نا (لقەکانیشی)
    func matchesHost(in set: Set<String>) -> Bool {
        let host = lowercased()
        if set.contains(host) { return true }
        return set.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
