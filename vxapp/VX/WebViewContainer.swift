import SwiftUI
import WebKit

/// پێچەرەوەی WKWebView — هەموو تایبەتمەندییەکانی وێب چالاک دەکات:
/// چوونەژوورەوەی Google، کامێرا/مایک، بارکردن و داگرتنی فایل، cookies، JS
struct WebViewContainer: UIViewRepresentable {

    @ObservedObject var model: WebModel

    func makeCoordinator() -> WebCoordinator { WebCoordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // ---- ناوەڕۆکی مێدیا: ڤیدیۆ لەناو پەڕەکەدا، بەبێ داواکاری کرتە ----
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true

        // ---- پاشەکەوتکردنی هەمیشەیی: cookie و session نامێننەوە ----
        config.websiteDataStore = .default()
        config.processPool = WKProcessPool()

        // ---- JavaScript بە تەواوی چالاک ----
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        // ---- کردنەوەی پەڕەی نوێ (target=_blank) لە هەمان ویندۆدا ----
        config.suppressesIncrementalRendering = false

        let webView = FullWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor(hex: AppConfig.backgroundHex)
        webView.scrollView.backgroundColor = UIColor(hex: AppConfig.backgroundHex)

        // ---- User-Agent ی Safari ی ڕەسەن ----
        // بەبێ ئەمە Google دەڵێت "this browser is not secure" و
        // ڕێگە بە چوونەژوورەوە نادات لەناو ئەپەکەدا
        webView.customUserAgent = AppConfig.safariUserAgent

        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }

        // ---- چاودێری پێشکەوتن و بەستەر ----
        context.coordinator.observe(webView)
        model.attach(webView)

        webView.load(URLRequest(url: AppConfig.startURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: WebCoordinator) {
        coordinator.stopObserving()
    }
}

/// WKWebView کە کیبۆردی خۆماڵی iOS بەکاردەهێنێت و
/// ڕێگە دەدات بە inputAccessoryView ی ئاسایی
final class FullWebView: WKWebView {
    override var safeAreaInsets: UIEdgeInsets {
        // ژێرەوەی شاشە بە تەواوی بەکاردەهێنێت (بۆ باری نووسین)
        var insets = super.safeAreaInsets
        insets.bottom = 0
        return insets
    }
}

extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = CGFloat((value & 0xFF0000) >> 16) / 255
        let g = CGFloat((value & 0x00FF00) >> 8) / 255
        let b = CGFloat(value & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
