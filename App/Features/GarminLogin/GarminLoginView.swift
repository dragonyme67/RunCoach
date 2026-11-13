import SwiftUI
import WebKit
import RunCoachCore

/// Connexion Garmin (ARCHITECTURE.md §5.1.2) : la page officielle de Garmin dans une vue web.
/// L'utilisateur y tape ses identifiants et son code ; l'app ne les voit jamais, elle ne récupère que le ticket.
struct GarminLoginView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GarminWebView(log: { sync.log($0) }) { ticket in
                dismiss()
                Task { await sync.login(ticket: ticket) }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Connexion Garmin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }
}

/// `WKWebView` sans données persistantes. Le ticket `ST-…` est capté par trois crochets ; le premier gagne.
struct GarminWebView: UIViewRepresentable {
    let log: (String) -> Void
    let onTicket: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(log: log, onTicket: onTicket) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.captureScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        configuration.userContentController.add(context.coordinator, name: "rc")
        // User-Agent par défaut du WKWebView : ne pas le modifier (§9.1).
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: GarminIdentity.signInURL))
        context.coordinator.log("Ouverture de la page de connexion")
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "rc")
    }

    /// Crochet 2 : enveloppe `fetch` et `XMLHttpRequest` ; pour les réponses de connexion qui contiennent
    /// `serviceTicketId`, n'envoie à l'app que cette valeur.
    static let captureScript = """
    (function () {
      function check(url, text) {
        try {
          if (!/\\/api\\/(login|mfa\\/verifyCode)/.test(String(url))) return;
          var body = JSON.parse(text);
          if (body && body.serviceTicketId) window.webkit.messageHandlers.rc.postMessage(String(body.serviceTicketId));
        } catch (e) {}
      }
      var originalFetch = window.fetch;
      if (originalFetch) {
        window.fetch = function (input, init) {
          var url = (input && input.url) || input;
          return originalFetch.apply(this, arguments).then(function (response) {
            try { response.clone().text().then(function (text) { check(url, text); }); } catch (e) {}
            return response;
          });
        };
      }
      var open = XMLHttpRequest.prototype.open, send = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function (method, url) { this.__rcUrl = url; return open.apply(this, arguments); };
      XMLHttpRequest.prototype.send = function () {
        var request = this;
        request.addEventListener('load', function () { try { check(request.__rcUrl, request.responseText); } catch (e) {} });
        return send.apply(this, arguments);
      };
    })();
    """

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let log: (String) -> Void
        private let onTicket: (String) -> Void
        private var delivered = false

        init(log: @escaping (String) -> Void, onTicket: @escaping (String) -> Void) {
            self.log = log
            self.onTicket = onTicket
        }

        private func deliver(_ ticket: String?, via hook: String) {
            guard !delivered, let ticket else { return }
            delivered = true
            log("Ticket capté (\(hook))")
            onTicket(ticket)
        }

        /// Crochet 1 : la redirection finale vers l'adresse de service porte `?ticket=ST-…`.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .allow }
            // Hôte et chemin seulement : jamais les paramètres, qui peuvent contenir le ticket.
            log("→ \(url.host ?? "?")\(url.path)")
            guard let ticket = GarminIdentity.ticket(in: url.absoluteString) else { return .allow }
            deliver(ticket, via: "navigation")
            return .cancel
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            if let http = navigationResponse.response as? HTTPURLResponse {
                log("← \(http.statusCode) \(http.url?.host ?? "?")\(http.url?.path ?? "")")
            }
            return .allow
        }

        /// Crochet 3 : le ticket présent dans le contenu de la page.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] html, _ in
                self?.deliver((html as? String).flatMap(GarminIdentity.ticket(in:)), via: "contenu de la page")
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if !delivered { log("Chargement interrompu (code \((error as NSError).code))") }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            deliver((message.body as? String).flatMap(GarminIdentity.ticket(in:)), via: "réponse réseau")
        }
    }
}
