import SwiftUI
import WebKit

/// Интерактивный артефакт в окне чата (владелец 01.10.2026: «как у тебя
/// артефакты, только прямо в окне чата»). Роль пишет блок ```html — целую
/// страницу или фрагмент с HTML/CSS/JS, — и он живёт в ленте: кнопки
/// нажимаются, графики рисуются, игры играются. Тап по «развернуть» —
/// на весь экран.
///
/// Песочница: отдельный WKWebView без общих cookie и хранилища
/// (`nonPersistent`), переходы по ссылкам уходят в Safari, а не внутрь
/// артефакта, у страницы нет мостов в приложение, кроме сообщения о своей
/// высоте. Скрипты с CDN (Chart.js, D3 и т.п.) грузятся — базовый адрес https.
struct ChatHTMLView: View {
    let html: String
    @State private var height: CGFloat = 160
    @State private var isFullScreen = false

    /// Выше этого артефакт в ленте не растёт — дальше «развернуть».
    private static let inlineMaxHeight: CGFloat = 520

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ChatWebView(html: html, height: $height, isScrollEnabled: height > Self.inlineMaxHeight)
                .frame(height: min(max(height, 60), Self.inlineMaxHeight))
        }
        .background(Color.tfCard, in: RoundedRectangle(cornerRadius: TFRadius.xl))
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.xl))
        .overlay(RoundedRectangle(cornerRadius: TFRadius.xl).strokeBorder(Color.tfStroke, lineWidth: TFBorder.width))
        .fullScreenCover(isPresented: $isFullScreen) {
            NavigationStack {
                ChatWebView(html: html, height: .constant(0), isScrollEnabled: true)
                    .ignoresSafeArea(edges: .bottom)
                    .background(Color.tfBackground)
                    .navigationTitle(Self.title(of: html) ?? "Интерактив")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Закрыть") { isFullScreen = false }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(item: html, preview: SharePreview("Артефакт.html")) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
            }
        }
    }

    private var header: some View {
        HStack(spacing: TFSpacing.sm) {
            Image(systemName: "sparkles.rectangle.stack")
                .foregroundStyle(Color.tfRed)
            Text(Self.title(of: html) ?? "Интерактив")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.tfText)
                .lineLimit(1)
            Spacer()
            Menu {
                Button { UIPasteboard.general.string = html } label: {
                    Label("Скопировать код", systemImage: "doc.on.doc")
                }
                ShareLink(item: html, preview: SharePreview("Артефакт.html")) {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 32, height: 32)
            }
            .foregroundStyle(Color.tfSub)
            Button { isFullScreen = true } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 32, height: 32)
            }
            .foregroundStyle(Color.tfSub)
            .accessibilityLabel("Развернуть на весь экран")
        }
        .padding(.leading, TFSpacing.md)
        .padding(.trailing, TFSpacing.xs)
        .padding(.vertical, TFSpacing.xs)
    }

    /// Заголовок артефакта — из `<title>`, если роль его задала.
    static func title(of html: String) -> String? {
        guard let open = html.range(of: "<title>", options: .caseInsensitive),
              let close = html.range(of: "</title>", options: .caseInsensitive, range: open.upperBound..<html.endIndex)
        else { return nil }
        let title = html[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : String(title.prefix(60))
    }

    /// Фрагмент без `<html>` оборачиваем в страницу с мобильной разметкой и
    /// стилями под тему приложения; целую страницу отдаём как есть.
    static func document(_ html: String) -> String {
        if html.range(of: "<html", options: .caseInsensitive) != nil { return html }
        return """
        <!doctype html>
        <html><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
        :root { color-scheme: light dark; }
        html, body { margin: 0; background: transparent; }
        body { padding: 12px; font: -apple-system-body; font-family: -apple-system, system-ui, sans-serif;
               color: #171717; -webkit-text-size-adjust: 100%; }
        @media (prefers-color-scheme: dark) { body { color: #ffffff; } }
        button { font: inherit; }
        </style>
        </head><body>
        \(html)
        </body></html>
        """
    }
}

/// WKWebView для артефакта: сообщает свою высоту, ссылки открывает в Safari.
struct ChatWebView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat
    var isScrollEnabled: Bool

    /// Сообщает высоту документа при каждом её изменении.
    private static let heightScript = """
    (function() {
      function report() {
        var h = Math.ceil(document.documentElement.scrollHeight);
        window.webkit.messageHandlers.tfHeight.postMessage(h);
      }
      if (window.ResizeObserver) { new ResizeObserver(report).observe(document.documentElement); }
      window.addEventListener('load', report);
      report();
    })();
    """

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.allowsInlineMediaPlayback = true
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: Self.heightScript,
                                              injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: true))
        controller.add(WeakMessageHandler(context.coordinator), name: "tfHeight")
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = isScrollEnabled
        webView.scrollView.bounces = isScrollEnabled
        webView.navigationDelegate = context.coordinator
        context.coordinator.load(html, into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.scrollView.isScrollEnabled = isScrollEnabled
        webView.scrollView.bounces = isScrollEnabled
        context.coordinator.height = $height
        context.coordinator.load(html, into: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "tfHeight")
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var height: Binding<CGFloat>
        private var loadedHTML: String?

        init(height: Binding<CGFloat>) { self.height = height }

        /// Грузим только новый код: перерисовка ленты не должна сбрасывать
        /// состояние артефакта (набранное, нажатое).
        func load(_ html: String, into webView: WKWebView) {
            guard html != loadedHTML else { return }
            loadedHTML = html
            webView.loadHTMLString(ChatHTMLView.document(html),
                                   baseURL: URL(string: "https://artifact.taskflow.local/"))
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let value = message.body as? NSNumber else { return }
            let newHeight = CGFloat(truncating: value)
            guard newHeight > 0, abs(newHeight - height.wrappedValue) > 1 else { return }
            DispatchQueue.main.async { self.height.wrappedValue = newHeight }
        }

        /// Ссылка, по которой нажали, — в Safari; сама страница артефакта и
        /// его iframe грузятся как обычно.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            if action.navigationType == .linkActivated, let url = action.request.url {
                UIApplication.shared.open(url)
                return .cancel
            }
            return .allow
        }
    }
}

/// WKUserContentController держит обработчик сильно — прокси не даёт
/// координатору и веб-вью держать друг друга вечно.
@MainActor
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
