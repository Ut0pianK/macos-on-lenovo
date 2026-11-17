import AppKit
import Carbon.HIToolbox

@MainActor
final class GlobalHotKeys {
    static let shared = GlobalHotKeys()
    enum Action: UInt32, CaseIterable {
        case playPause = 1, next, previous, volumeUp, volumeDown
        var keyCode: Int {
            switch self {
            case .playPause: return kVK_ANSI_P
            case .next: return kVK_RightArrow
            case .previous: return kVK_LeftArrow
            case .volumeUp: return kVK_UpArrow
            case .volumeDown: return kVK_DownArrow
            }
        }
    }
    private var refs: [EventHotKeyRef] = []
    private var handlerInstalled = false
    weak var player: Player?

    var enabled: Bool = UserDefaults.standard.object(forKey: "globalHotKeys") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "globalHotKeys"); apply() }
    }

    func attach(_ player: Player) { self.player = player; apply() }

    private func apply() {
        for r in refs { UnregisterEventHotKey(r) }
        refs.removeAll()
        guard enabled else { return }
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &id)
                let raw = id.id
                DispatchQueue.main.async { MainActor.assumeIsolated { GlobalHotKeys.shared.fire(raw) } }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        for a in Action.allCases {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x534F4E41), id: a.rawValue)
            if RegisterEventHotKey(UInt32(a.keyCode), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref)
            }
        }
    }

    private func fire(_ raw: UInt32) {
        guard let player, let a = Action(rawValue: raw) else { return }
        switch a {
        case .playPause: player.playPause()
        case .next: player.next()
        case .previous: player.previous()
        case .volumeUp: player.volume = min(1, player.volume + 0.1)
        case .volumeDown: player.volume = max(0, player.volume - 0.1)
        }
    }
}
