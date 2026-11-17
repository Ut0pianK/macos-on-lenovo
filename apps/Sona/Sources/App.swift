import SwiftUI

@main
struct SonaApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var player = Player()
    @StateObject private var lastfm = LastFM()
    @StateObject private var converter = Converter()
    @StateObject private var nav = Navigator()

    var body: some Scene {
        WindowGroup("Sona", id: "main") {
            ContentView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(converter)
                .environmentObject(nav)
                .frame(minWidth: 380, minHeight: 320)
                .onAppear { player.attach(library); GlobalHotKeys.shared.attach(player); player.lastfm = lastfm; converter.library = library; Task { await lastfm.flush() } }
        }
        .defaultSize(width: 1180, height: 720)
        .commands {
            CommandMenu("재생") {
                Button(player.isPlaying ? "일시 정지" : "재생") { player.playPause() }
                    .keyboardShortcut("p", modifiers: .command)
                Button("다음 곡") { player.next() }.keyboardShortcut(.rightArrow, modifiers: .command)
                Button("이전 곡") { player.previous() }.keyboardShortcut(.leftArrow, modifiers: .command)
                Divider()
                Button("소리 크게") { player.volume = min(1, player.volume + 0.1) }.keyboardShortcut(.upArrow, modifiers: .command)
                Button("소리 작게") { player.volume = max(0, player.volume - 0.1) }.keyboardShortcut(.downArrow, modifiers: .command)
                Divider()
                Toggle("셔플", isOn: Binding(get: { player.shuffle }, set: { player.shuffle = $0 }))
            }
        }

        Settings {
            SettingsView().environmentObject(library).environmentObject(player).environmentObject(lastfm).environmentObject(converter)
        }
    }
}
