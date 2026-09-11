import Foundation
import SwiftUI
import WebKit

/// مۆدێلی دۆخی وێب — پێشکەوتن، هەڵە، و کۆنترۆڵی گەڕان
@MainActor
final class WebModel: ObservableObject {
    @Published var progress: Double = 0
    @Published var isLoading = false
    @Published var didFinishFirstLoad = false
    @Published var errorMessage: String?
    @Published var canGoBack = false

    weak var webView: WKWebView?

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    func reload() {
        errorMessage = nil
        if let webView, webView.url != nil {
            webView.reload()
        } else {
            webView?.load(URLRequest(url: AppConfig.startURL))
        }
    }

    func goHome() {
        errorMessage = nil
        webView?.load(URLRequest(url: AppConfig.startURL))
    }

    func goBack() {
        if webView?.canGoBack == true { webView?.goBack() }
    }
}

/// هەماهەنگکەری گەڕان — چوونەژوورەوە، پەڕەی نوێ، مۆڵەتی مێدیا، داگرتن
final class WebCoordinator: NSObject {

    private let model: WebModel
    private var progressObs: NSKeyValueObservation?
    private var backObs: NSKeyValueObservation?

    init(model: WebModel) {
        self.model = model
        super.init()
    }

    func observe(_ webView: WKWebView) {
        progressObs = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            Task { @MainActor in
                self?.model.progress = wv.estimatedProgress
            }
        }
        backObs = webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
            Task { @MainActor in
                self?.model.canGoBack = wv.canGoBack
            }
        }
    }

    func stopObserving() {
        progressObs?.invalidate()
        backObs?.invalidate()
    }
}

// MARK: - Navigation

extension WebCoordinator: WKNavigationDelegate {

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""

        // بەستەری تایبەت: تەلەفۆن، ئیمەیڵ، ئەپی دەرەکی
        if ["tel", "mailto", "sms", "facetime", "facetime-audio", "maps", "itms-apps"].contains(scheme) {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        guard scheme == "http" || scheme == "https" else {
            // scheme ی ئەپی تر (وەک whatsapp://) — بیدە بە سیستەم
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.cancel)
            }
            return
        }

        let host = url.host ?? ""

        // ماڵپەڕی خۆمان + پەڕەکانی چوونەژوورەوەی Google → لەناو ئەپەکەدا
        if host.matchesHost(in: AppConfig.internalHosts)
            || host.matchesHost(in: AppConfig.authHosts) {
            decisionHandler(.allow)
            return
        }

        // بەستەری دەرەکی کە بەکارهێنەر کرتەی لێکردووە → Safari
        if navigationAction.navigationType == .linkActivated {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        // ئەوانی تر (iframe، redirect، API) → ڕێگە بدە
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in
            model.isLoading = true
            model.errorMessage = nil
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            model.isLoading = false
            model.didFinishFirstLoad = true
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        handle(error)
    }

    private func handle(_ error: Error) {
        let ns = error as NSError
        // -999 = گەڕانەکە لەلایەن خودی پەڕەکەوە ڕاگیرا (ئاساییە)
        guard ns.code != NSURLErrorCancelled else { return }
        Task { @MainActor in
            model.isLoading = false
            model.errorMessage = friendlyMessage(for: ns)
        }
    }

    private func friendlyMessage(for error: NSError) -> String {
        switch error.code {
        case NSURLErrorNotConnectedToInternet:
            return "ئینتەرنێت نییە — پەیوەندییەکەت بپشکنە و دووبارە هەوڵ بدەرەوە."
        case NSURLErrorTimedOut:
            return "کاتی پەیوەندی تەواو بوو — دووبارە هەوڵ بدەرەوە."
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
            return "ناتوانرێت بگات بە سێرڤەرەکە — دواتر هەوڵ بدەرەوە."
        default:
            return "هەڵەیەک ڕوویدا لە بارکردنی پەڕەکە."
        }
    }

    // بارکردنەوەی خۆکار ئەگەر پرۆسەی وێب ڕووخا
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

// MARK: - UI (پەڕەی نوێ، مۆڵەتی کامێرا/مایک، ئاگاداریەکان)

extension WebCoordinator: WKUIDelegate {

    /// target="_blank" — لە هەمان ویندۆدا بیکەرەوە، نەک لەدەستی بدەیت
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            let host = url.host ?? ""
            if host.matchesHost(in: AppConfig.internalHosts)
                || host.matchesHost(in: AppConfig.authHosts) {
                webView.load(navigationAction.request)
            } else {
                UIApplication.shared.open(url)
            }
        }
        return nil
    }

    /// مۆڵەتی کامێرا و مایک — بەبێ ئەمە دەنگ و وێنە کار ناکەن
    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        if origin.host.matchesHost(in: AppConfig.internalHosts) {
            decisionHandler(.grant)
        } else {
            decisionHandler(.prompt)
        }
    }

    // ---- alert / confirm / prompt ی JavaScript ----

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        present(alert: message, actions: [("باشە", { completionHandler() })])
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        present(alert: message, actions: [
            ("پاشگەزبوونەوە", { completionHandler(false) }),
            ("باشە", { completionHandler(true) }),
        ])
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        guard let top = Self.topViewController() else {
            completionHandler(defaultText)
            return
        }
        let ac = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        ac.addTextField { $0.text = defaultText }
        ac.addAction(UIAlertAction(title: "پاشگەزبوونەوە", style: .cancel) { _ in
            completionHandler(nil)
        })
        ac.addAction(UIAlertAction(title: "باشە", style: .default) { _ in
            completionHandler(ac.textFields?.first?.text)
        })
        top.present(ac, animated: true)
    }

    private func present(alert message: String, actions: [(String, () -> Void)]) {
        guard let top = Self.topViewController() else {
            actions.last?.1()
            return
        }
        let ac = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        for (title, handler) in actions {
            ac.addAction(UIAlertAction(title: title, style: .default) { _ in handler() })
        }
        top.present(ac, animated: true)
    }

    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

// MARK: - داگرتنی فایل

extension WebCoordinator: WKDownloadDelegate {

    func webView(_ webView: WKWebView,
                 navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView,
                 navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var dest = dir.appendingPathComponent(suggestedFilename)
        var i = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            let name = (suggestedFilename as NSString).deletingPathExtension
            let ext = (suggestedFilename as NSString).pathExtension
            let newName = ext.isEmpty ? "\(name)-\(i)" : "\(name)-\(i).\(ext)"
            dest = dir.appendingPathComponent(newName)
            i += 1
        }
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url: URL = download.progress.fileURL else { return }
        Task { @MainActor in
            guard let top = Self.topViewController() else { return }
            let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            share.popoverPresentationController?.sourceView = top.view
            share.popoverPresentationController?.sourceRect = CGRect(
                x: top.view.bounds.midX, y: top.view.bounds.maxY - 60, width: 1, height: 1)
            top.present(share, animated: true)
        }
    }
}
