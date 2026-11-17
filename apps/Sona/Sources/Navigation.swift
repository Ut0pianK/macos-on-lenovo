import SwiftUI

@MainActor
final class Navigator: ObservableObject {
    @Published var selection: SidebarItem? = .songs
    @Published var pickedArtist: String?
    @Published var pickedAlbum: String?

    func showArtist(_ t: Track) { pickedArtist = t.artistSort; selection = .artists }
    func showAlbum(_ t: Track) { pickedAlbum = t.albumSort; selection = .albums }
}

struct LinkCell: View {
    let text: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 4) {
            Text(text).lineLimit(1)
            if hover && !text.isEmpty {
                Button(action: action) { Image(systemName: "arrow.right.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("이동")
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}
