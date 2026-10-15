import SwiftUI
import WebKit

// MARK: - Sheet wrapper

struct VideoPlayerSheet: View {
    let url: URL
    let exerciseName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            EmbeddedVideoPlayer(url: url)
                .ignoresSafeArea()
                .navigationTitle(exerciseName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

// MARK: - WKWebView wrapper

struct EmbeddedVideoPlayer: UIViewRepresentable {
    let url: URL

    private var embedURL: URL {
        let str = url.absoluteString

        // Vimeo: https://vimeo.com/123456789
        if str.contains("vimeo.com/"), !str.contains("player.vimeo.com") {
            if let rawID = str.components(separatedBy: "vimeo.com/").last {
                let id = rawID.components(separatedBy: "?").first ?? rawID
                if let u = URL(string: "https://player.vimeo.com/video/\(id)?autoplay=0&playsinline=1&color=007AFF&byline=0&portrait=0&title=0") {
                    return u
                }
            }
        }

        // YouTube: https://www.youtube.com/watch?v=XXXXX
        if str.contains("youtube.com/watch"),
           let comps = URLComponents(string: str),
           let id = comps.queryItems?.first(where: { $0.name == "v" })?.value,
           let u = URL(string: "https://www.youtube.com/embed/\(id)?playsinline=1") {
            return u
        }

        // YouTube short: https://youtu.be/XXXXX
        if str.contains("youtu.be/"),
           let rawID = str.components(separatedBy: "youtu.be/").last {
            let id = rawID.components(separatedBy: "?").first ?? rawID
            if let u = URL(string: "https://www.youtube.com/embed/\(id)?playsinline=1") {
                return u
            }
        }

        return url
    }

    class Coordinator {
        var loadedURL: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .black
        webView.isOpaque = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let target = embedURL
        guard context.coordinator.loadedURL != target else { return }
        context.coordinator.loadedURL = target
        var request = URLRequest(url: target)
        // Vimeo requires a referrer to allow embedding
        if target.host?.contains("vimeo.com") == true {
            request.setValue("https://player.vimeo.com", forHTTPHeaderField: "Referer")
        }
        webView.load(request)
    }
}
