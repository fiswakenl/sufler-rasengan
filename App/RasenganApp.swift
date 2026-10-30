import SwiftUI
import WebKit
import ReplayKit

let group = "group.dev.sufler.rasengan"

@main
struct RasenganApp: App {
    var body: some Scene {
        WindowGroup { Web().ignoresSafeArea() }
    }
}

// Окно со страницей суфлёра. Вся логика и интерфейс приходят с сервера; приложение даёт странице только мост к захвату системного звука.
struct Web: UIViewRepresentable {
    func makeCoordinator() -> Bridge { Bridge() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.userContentController.add(context.coordinator, name: "rasengan")
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.uiDelegate = context.coordinator
        v.navigationDelegate = context.coordinator
        context.coordinator.web = v
        let s = Bundle.main.object(forInfoDictionaryKey: "SuflerURL") as? String ?? ""
        if let u = URL(string: s) { v.load(URLRequest(url: u)) }
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) {}
}

final class Bridge: NSObject, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
    weak var web: WKWebView?
    private let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))

    // Страница шлёт {cmd:"broadcast", url, token}: сохраняем адрес и ключ для расширения и открываем системное окно трансляции.
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let d = m.body as? [String: Any], d["cmd"] as? String == "broadcast" else { return }
        let ud = UserDefaults(suiteName: group)
        ud?.set(d["url"] as? String, forKey: "url")
        ud?.set(d["token"] as? String, forKey: "token")
        picker.preferredExtension = Bundle.main.bundleIdentifier.map { $0 + ".Broadcast" }
        picker.subviews.compactMap { $0 as? UIButton }.first?.sendActions(for: .allTouchEvents)
    }

    // Белый экран ничего не объясняет: ошибку загрузки показываем текстом.
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { show(w, e) }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { show(w, e) }
    private func show(_ w: WKWebView, _ e: Error) {
        let u = Bundle.main.object(forInfoDictionaryKey: "SuflerURL") as? String ?? "(адрес не задан)"
        w.loadHTMLString("<meta name=viewport content='width=device-width'><body style='font:17px -apple-system;padding:60px 24px'><h3>Не открылось</h3><p>\(u)</p><p style='color:#b04a3a'>\(e.localizedDescription)</p>", baseURL: nil)
    }

    // Микрофон странице разрешаем без повторного вопроса.
    @available(iOS 15.0, *)
    func webView(_ w: WKWebView, requestMediaCapturePermissionFor o: WKSecurityOrigin, initiatedByFrame f: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }
}
