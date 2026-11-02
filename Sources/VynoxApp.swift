import SwiftUI
import WebKit
import AVFoundation
import UniformTypeIdentifiers

struct Track: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

final class Player: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var tracks: [Track] = []
    @Published var current: Track?
    @Published var isPlaying = false
    @Published var downloading = false
    @Published var message: String?

    private var player: AVAudioPlayer?
    private let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let audioExts = ["mp3", "m4a", "wav", "aac", "flac", "aiff"]
    private var exts: [String] { Player.audioExts }

    override init() {
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        load()
    }

    func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        tracks = files
            .filter { exts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
            .map { Track(url: $0) }
    }

    func importFiles(_ urls: [URL]) {
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            if !FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.copyItem(at: url, to: dest)
            }
        }
        load()
    }

    func download(from text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: clean), let scheme = url.scheme, scheme.hasPrefix("http") else {
            message = "Das ist kein gültiger Link."
            return
        }
        guard exts.contains(url.pathExtension.lowercased()) else {
            message = "Der Link muss direkt auf eine Audiodatei zeigen (.mp3, .m4a, .wav …)."
            return
        }
        startDownload(url: url, ext: nil)
    }

    func startDownload(url: URL, ext: String?) {
        downloading = true
        let dir = self.dir
        URLSession.shared.downloadTask(with: url) { [weak self] tmp, response, error in
            var result = "Download fehlgeschlagen."
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            if let tmp = tmp, error == nil, status < 400 {
                var name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
                let have = URL(fileURLWithPath: name).pathExtension.lowercased()
                if let ext = ext, !Player.audioExts.contains(have) { name += "." + ext }
                let dest = dir.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: dest)
                do {
                    try FileManager.default.moveItem(at: tmp, to: dest)
                    result = "Gespeichert: " + dest.deletingPathExtension().lastPathComponent
                } catch {
                    result = "Speichern fehlgeschlagen."
                }
            }
            DispatchQueue.main.async {
                self?.downloading = false
                self?.load()
                self?.message = result
            }
        }.resume()
    }

    func delete(at offsets: IndexSet) {
        for i in offsets {
            if tracks[i] == current { stop() }
            try? FileManager.default.removeItem(at: tracks[i].url)
        }
        load()
    }

    func play(_ track: Track) {
        guard let p = try? AVAudioPlayer(contentsOf: track.url) else { return }
        p.delegate = self
        p.play()
        player = p
        current = track
        isPlaying = true
    }

    func toggle() {
        guard let p = player else {
            if let first = tracks.first { play(first) }
            return
        }
        if p.isPlaying { p.pause(); isPlaying = false } else { p.play(); isPlaying = true }
    }

    func stop() {
        player?.stop()
        player = nil
        current = nil
        isPlaying = false
    }

    func next() { step(1) }
    func previous() { step(-1) }

    private func step(_ d: Int) {
        guard !tracks.isEmpty else { return }
        let i = current.flatMap { tracks.firstIndex(of: $0) } ?? -d
        play(tracks[(i + d + tracks.count) % tracks.count])
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        next()
    }
}

struct ContentView: View {
    @StateObject private var player = Player()
    @State private var importing = false
    @State private var linkAlert = false
    @State private var linkText = ""
    @State private var showBrowser = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(player.tracks) { t in
                    Button {
                        player.play(t)
                    } label: {
                        HStack {
                            Image(systemName: player.current == t ? "speaker.wave.2.fill" : "music.note")
                                .frame(width: 24)
                            Text(t.name).lineLimit(1)
                        }
                    }
                    .foregroundColor(player.current == t ? .accentColor : .primary)
                }
                .onDelete(perform: player.delete)
            }
            .overlay {
                if player.tracks.isEmpty {
                    Text("Tippe auf + und wähle Musikdateien aus.")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image("Logo").resizable().scaledToFit().frame(height: 32)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showBrowser = true } label: { Image(systemName: "globe") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Aus Dateien") { importing = true }
                        Button("Von Link") { linkAlert = true }
                    } label: { Image(systemName: "plus") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    if player.downloading { ProgressView("Lädt …") }
                    Text(player.current?.name ?? "Nichts spielt")
                        .font(.subheadline).lineLimit(1)
                    HStack(spacing: 40) {
                        Button { player.previous() } label: { Image(systemName: "backward.fill") }
                        Button { player.toggle() } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title)
                        }
                        Button { player.next() } label: { Image(systemName: "forward.fill") }
                    }
                    .font(.title2)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.audio],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { player.importFiles(urls) }
            }
            .alert("Link einfügen", isPresented: $linkAlert) {
                TextField("https://…/lied.mp3", text: $linkText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Abbrechen", role: .cancel) { linkText = "" }
                Button("Laden") {
                    player.download(from: linkText)
                    linkText = ""
                }
            } message: {
                Text("Direkter Link zu einer Audiodatei")
            }
        }
        .alert("Vynox", isPresented: Binding(
            get: { player.message != nil && !showBrowser },
            set: { if !$0 { player.message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(player.message ?? "")
        }
        .fullScreenCover(isPresented: $showBrowser) {
            BrowserView(player: player)
        }
    }
}

struct AudioFound {
    let url: URL
    let ext: String?
}

struct WebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate {
    let webView = WKWebView()
    @Published var address = "https://pixabay.com/music/"
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var found: AudioFound?

    override init() {
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        load(address)
    }

    func load(_ text: String) {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.lowercased().hasPrefix("http") { t = "https://" + t }
        if let url = URL(string: t) { webView.load(URLRequest(url: url)) }
    }

    private func refresh() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        if let u = webView.url?.absoluteString { address = u }
    }

    private func ext(for mime: String) -> String {
        if mime.contains("mp4") || mime.contains("m4a") { return "m4a" }
        if mime.contains("wav") { return "wav" }
        if mime.contains("aac") { return "aac" }
        if mime.contains("flac") { return "flac" }
        return "mp3"
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url,
           Player.audioExts.contains(url.pathExtension.lowercased()) {
            found = AudioFound(url: url, ext: nil)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let mime = navigationResponse.response.mimeType?.lowercased(),
           mime.hasPrefix("audio/"),
           let url = navigationResponse.response.url {
            found = AudioFound(url: url, ext: ext(for: mime))
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { refresh() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { refresh() }
}

struct BrowserView: View {
    @ObservedObject var player: Player
    @StateObject private var model = BrowserModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                Button { model.webView.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!model.canGoBack)
                Button { model.webView.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!model.canGoForward)
                TextField("Adresse", text: $model.address)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit { model.load(model.address) }
                    .padding(8)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(8)
            }
            .padding(10)
            if player.downloading { ProgressView("Lädt …").padding(4) }
            WebView(webView: model.webView)
        }
        .background(Color.black)
        .alert("Audiodatei gefunden", isPresented: Binding(
            get: { model.found != nil },
            set: { if !$0 { model.found = nil } }
        )) {
            if let f = model.found {
                Button("Herunterladen") { player.startDownload(url: f.url, ext: f.ext) }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(model.found?.url.lastPathComponent ?? "")
        }
        .alert("Vynox", isPresented: Binding(
            get: { player.message != nil },
            set: { if !$0 { player.message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(player.message ?? "")
        }
    }
}

@main
struct VynoxApp: App {
    var body: some Scene {
        WindowGroup { ContentView().preferredColorScheme(.dark).tint(.purple) }
    }
}
