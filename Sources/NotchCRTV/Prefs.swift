import AppKit
import NotchCore

/// Preferências em UserDefaults. As views usam @AppStorage com as mesmas chaves.
enum Prefs {
    enum Key {
        static let showNotch = "showNotch"
        static let showMenuBar = "showMenuBar"
        static let showOverlay = "showOverlay"
        static let hotkey = "hotkey"
        static let offsets = "alertOffsets"          // "15,5,0"
        static let sound = "sound"
        static let nagMinutes = "nagMinutes"
        static let morningHour = "morningHour"
        static let reviewHour = "reviewHour"
        static let endOfDayHour = "endOfDayHour"
        static let morningSummary = "morningSummary"
        static let eveningReview = "eveningReview"
        static let pomodoroWork = "pomodoroWork"
        static let pomodoroBreak = "pomodoroBreak"
        static let appTags = "appTags"               // "com.adobe.PremierePro.25=edição;..."
        static let overlayHideApps = "overlayHideApps"
        static let lastMorning = "lastMorning"
        static let lastReview = "lastReview"
        static let overlayOrigin = "overlayOrigin"
        static let notchHeight = "notchHeight"
        static let glass = "glass"
        static let deadlineHour = "deadlineHour"
        static let islandStyle = "islandStyle"
    }

    static let d = UserDefaults.standard

    static func registerDefaults() {
        d.register(defaults: [
            Key.showNotch: true, Key.showMenuBar: true, Key.showOverlay: false,
            Key.hotkey: 0, Key.offsets: "15,5,0", Key.sound: "Glass", Key.nagMinutes: 2,
            Key.morningHour: 8, Key.reviewHour: 21, Key.endOfDayHour: 22,
            Key.morningSummary: true, Key.eveningReview: true,
            Key.notchHeight: 280, Key.islandStyle: true, Key.deadlineHour: 17, Key.glass: true,
            Key.pomodoroWork: 25, Key.pomodoroBreak: 5,
            Key.appTags: "Adobe Premiere Pro=edição;DaVinci Resolve=edição;Adobe After Effects=motion;Adobe Photoshop=arte",
            Key.overlayHideApps: "Adobe Premiere Pro;Keynote",
        ])
    }

    static var defaultOffsets: [Int] {
        (d.string(forKey: Key.offsets) ?? "15,5,0").split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.sorted(by: >)
    }
    static func offsets(for t: TaskItem) -> [Int] { (t.alertOffsets ?? defaultOffsets).sorted(by: >) }

    static var deadlineHour: Int { min(23, max(1, d.integer(forKey: Key.deadlineHour))) }
    static var sound: String { d.string(forKey: Key.sound) ?? "Glass" }
    static var nagMinutes: Int { max(1, d.integer(forKey: Key.nagMinutes)) }
    static var morningHour: Int { d.integer(forKey: Key.morningHour) }
    static var reviewHour: Int { d.integer(forKey: Key.reviewHour) }
    static var endOfDayHour: Int { d.integer(forKey: Key.endOfDayHour) }
    static var pomodoroWork: Int { max(1, d.integer(forKey: Key.pomodoroWork)) }
    static var pomodoroBreak: Int { max(1, d.integer(forKey: Key.pomodoroBreak)) }

    /// nome do app → tag
    static var appTags: [String: String] {
        var out: [String: String] = [:]
        for pair in (d.string(forKey: Key.appTags) ?? "").split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, !kv[0].isEmpty, !kv[1].isEmpty { out[kv[0]] = kv[1].replacingOccurrences(of: "#", with: "").lowercased() }
        }
        return out
    }
    static var overlayHideApps: Set<String> {
        Set((d.string(forKey: Key.overlayHideApps) ?? "").split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) })
    }

    static let sounds = ["Glass", "Ping", "Pop", "Purr", "Hero", "Submarine", "Funk", "Tink", "Blow", "Bottle", "Frog", "Morse", "Sosumi", "Basso", "Nenhum"]

    static func playSound(_ name: String? = nil) {
        let n = name ?? sound
        guard n != "Nenhum" else { return }
        NSSound(named: NSSound.Name(n))?.play()
    }
}
