import AppKit
import UserNotifications
import NotchCore

/// Notificações + agendador. Um timer verifica a cada 10 s o que precisa disparar;
/// assim lembretes insistentes, soneca e recorrência ficam simples e consistentes.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private let center = UNUserNotificationCenter.current()
    private var lastNag: [UUID: Date] = [:]
    private var timer: Timer?

    func start() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        let done = UNNotificationAction(identifier: "done", title: "Concluir", options: [])
        let s5 = UNNotificationAction(identifier: "s5", title: "+5 min", options: [])
        let s60 = UNNotificationAction(identifier: "s60", title: "+1 hora", options: [])
        let tom = UNNotificationAction(identifier: "tomorrow", title: "Amanhã", options: [])
        let start = UNNotificationAction(identifier: "focus", title: "Começar (Pomodoro)", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "TASK", actions: [done, s5, s60, tom, start], intentIdentifiers: []),
            UNNotificationCategory(identifier: "INFO", actions: [], intentIdentifiers: []),
        ])
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            MainActor.assumeIsolated { Notifier.shared.tick() }
        }
        tick()
    }

    func tick() {
        let store = Store.shared
        let now = Date()
        for t in store.pending {
            guard let due = t.effectiveDue else { continue }
            if let o = TaskEngine.alertToFire(t, offsets: Prefs.offsets(for: t), now: now) {
                // atrasado há muito (app estava fechado): avisa só uma vez como "atrasada"
                post(t, offset: o, due: due)
                store.markFired(t.id, upTo: o)
                lastNag[t.id] = now
                continue
            }
            if t.persistent, due < now, let last = lastNag[t.id] ?? Optional(.distantPast),
               now.timeIntervalSince(last) >= TimeInterval(Prefs.nagMinutes * 60) {
                post(t, offset: 0, due: due, nag: true)
                lastNag[t.id] = now
            }
        }
        dailyRoutines(now)
    }

    private func dailyRoutines(_ now: Date) {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let key = ISO8601DateFormatter.string(from: now, timeZone: .current, formatOptions: [.withFullDate])
        let d = Prefs.d
        if d.bool(forKey: Prefs.Key.morningSummary), hour >= Prefs.morningHour, hour < Prefs.morningHour + 4,
           d.string(forKey: Prefs.Key.lastMorning) != key {
            d.set(key, forKey: Prefs.Key.lastMorning)
            postSummary()
        }
        if d.bool(forKey: Prefs.Key.eveningReview), hour >= Prefs.reviewHour, d.string(forKey: Prefs.Key.lastReview) != key {
            d.set(key, forKey: Prefs.Key.lastReview)
            let s = Store.shared
            if !(s.overdue + s.today).isEmpty { AppDelegate.shared.showReview() }
        }
    }

    func postSummary() {
        let s = Store.shared
        let list = s.overdue + s.today
        let c = UNMutableNotificationContent()
        c.title = "Bom dia ☀️"
        if list.isEmpty {
            c.body = "Nada agendado pra hoje. \(s.undated.count) sem horário na lista."
        } else {
            let first = list.first { $0.hasTime }.flatMap(\.effectiveDue).map { " Primeira às \(Fmt.time($0))." } ?? ""
            let late = s.overdue.isEmpty ? "" : " \(s.overdue.count) atrasada(s)."
            c.body = "Hoje: \(list.count) demanda(s).\(first)\(late)"
            if let o = s.overload { c.body += " ⚠️ \(Fmt.dur(o.planned)) planejadas pra \(Fmt.dur(o.available)) livres." }
        }
        c.categoryIdentifier = "INFO"
        c.sound = sound()
        center.add(UNNotificationRequest(identifier: "summary", content: c, trigger: nil))
    }

    func post(_ t: TaskItem, offset: Int, due: Date, nag: Bool = false) {
        let c = UNMutableNotificationContent()
        c.title = (t.priority > 0 ? String(repeating: "!", count: t.priority) + " " : "") + t.title
        let late = Date().timeIntervalSince(due)
        if late > 60 {
            c.body = (nag ? "Ainda pendente — " : "Atrasada — ") + "era \(Fmt.time(due)) (\(Fmt.dur(Int(late / 60))) atrás)"
        } else if offset == 0 {
            c.body = t.hasTime ? "Agora · \(Fmt.time(due))" : "Pra hoje"
        } else {
            c.body = "Em \(Fmt.dur(offset)) · \(Fmt.time(due))"
        }
        if !t.subtasks.isEmpty {
            c.body += " · \(t.subtasks.filter(\.done).count)/\(t.subtasks.count) etapas"
        }
        if !t.tags.isEmpty { c.subtitle = t.tags.map { "#" + $0 }.joined(separator: " ") }
        c.categoryIdentifier = "TASK"
        c.userInfo = ["id": t.id.uuidString]
        c.sound = sound()
        c.interruptionLevel = t.priority >= 2 || t.persistent ? .timeSensitive : .active
        center.add(UNNotificationRequest(identifier: t.id.uuidString, content: c, trigger: nil))
        NotchController.shared.flash()
    }

    func postInfo(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = sound(); c.categoryIdentifier = "INFO"
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    func clear(_ id: UUID) {
        center.removeDeliveredNotifications(withIdentifiers: [id.uuidString])
        lastNag[id] = nil
    }

    /// Copia o som do sistema escolhido pra ~/Library/Sounds, assim o Foco do macOS consegue silenciar.
    private func sound() -> UNNotificationSound? {
        let name = Prefs.sound
        guard name != "Nenhum" else { return nil }
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds")
        let file = "NotchCRTV-\(name).aiff"
        let dst = dir.appendingPathComponent(file)
        if !fm.fileExists(atPath: dst.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try? fm.copyItem(at: URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff"), to: dst)
        }
        return fm.fileExists(atPath: dst.path) ? UNNotificationSound(named: UNNotificationSoundName(file)) : .default
    }

    // MARK: - Delegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let idStr = response.notification.request.content.userInfo["id"] as? String
        let action = response.actionIdentifier
        Task { @MainActor in
            defer { completionHandler() }
            guard let idStr, let id = UUID(uuidString: idStr) else { return }
            let s = Store.shared
            switch action {
            case "done": s.complete(id)
            case "s5": s.snooze(id, minutes: 5)
            case "s60": s.snooze(id, minutes: 60)
            case "tomorrow": s.snoozeToTomorrow(id)
            case "focus": Focus.shared.start(id)
            default: NotchController.shared.expand(pinned: true)
            }
        }
    }
}

enum Fmt {
    static func time(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "pt_BR"); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
    static func dur(_ min: Int) -> String {
        if min < 60 { return "\(min) min" }
        let h = min / 60, m = min % 60
        return m == 0 ? "\(h)h" : "\(h)h\(String(format: "%02d", m))"
    }
    static func when(_ t: TaskItem) -> String {
        guard let d = t.effectiveDue else { return "sem horário" }
        let cal = Calendar.current
        let f = DateFormatter(); f.locale = Locale(identifier: "pt_BR")
        var day: String
        if cal.isDateInToday(d) { day = "hoje" }
        else if cal.isDateInTomorrow(d) { day = "amanhã" }
        else if cal.isDateInYesterday(d) { day = "ontem" }
        else if let diff = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d)).day, diff > 0, diff < 7 {
            f.dateFormat = "EEEE"; day = f.string(from: d)
        } else { f.dateFormat = "dd/MM"; day = f.string(from: d) }
        return t.hasTime ? "\(day) \(time(d))" : day
    }
    /// "em 12 min", "há 5 min", "14:30"
    static func relative(_ d: Date, now: Date = Date()) -> String {
        let m = Int((d.timeIntervalSince(now) / 60).rounded())
        if m == 0 { return "agora" }
        if m > 0 && m < 60 { return "em \(m) min" }
        if m < 0 && m > -60 { return "há \(-m) min" }
        if Calendar.current.isDate(d, inSameDayAs: now) { return time(d) }
        return m > 0 ? "em \(dur(m))" : "há \(dur(-m))"
    }
    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }
}
