import AppKit
import Carbon.HIToolbox

/// Atalho global via Carbon (não precisa de permissão de Acessibilidade).
final class Hotkey {
    static let shared = Hotkey()
    static let options: [(label: String, key: UInt32, mods: UInt32)] = [
        ("⌥ Espaço", UInt32(kVK_Space), UInt32(optionKey)),
        ("⌃⌥ Espaço", UInt32(kVK_Space), UInt32(optionKey | controlKey)),
        ("⌥⌘ N", UInt32(kVK_ANSI_N), UInt32(optionKey | cmdKey)),
        ("⌃⌥ N", UInt32(kVK_ANSI_N), UInt32(optionKey | controlKey)),
    ]

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: () -> Void = {}

    func register(index: Int) {
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { Hotkey.shared.action() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let o = Hotkey.options[max(0, min(index, Hotkey.options.count - 1))]
        let id = EventHotKeyID(signature: OSType(0x4E544348), id: 1) // "NTCH"
        RegisterEventHotKey(o.key, o.mods, id, GetApplicationEventTarget(), 0, &ref)
    }
}
