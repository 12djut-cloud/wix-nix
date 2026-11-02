import SwiftUI
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

    private var player: AVAudioPlayer?
    private let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private let exts = ["mp3", "m4a", "wav", "aac", "flac", "aiff"]

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
                ToolbarItem(placement: .primaryAction) {
                    Button { importing = true } label: { Image(systemName: "plus") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
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
        }
    }
}

@main
struct VynoxApp: App {
    var body: some Scene {
        WindowGroup { ContentView().preferredColorScheme(.dark).tint(.purple) }
    }
}
