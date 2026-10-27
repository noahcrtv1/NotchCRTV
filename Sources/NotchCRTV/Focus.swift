import AppKit
import NotchCore

/// Pomodoro ligado a uma demanda. Enquanto ativo, o notch entra em modo foco.
@MainActor
final class Focus: ObservableObject {
    static let shared = Focus()
    enum Phase { case work, rest }

    @Published private(set) var taskID: UUID?
    @Published private(set) var phase: Phase = .work
    @Published private(set) var endsAt = Date()
    @Published private(set) var cycles = 0
    @Published private(set) var paused: TimeInterval?
    private var timer: Timer?

    var active: Bool { taskID != nil }
    var task: TaskItem? { taskID.flatMap(Store.shared.task) }
    var remaining: Int { Int((paused ?? endsAt.timeIntervalSinceNow).rounded()) }
    var total: Int { (phase == .work ? Prefs.pomodoroWork : Prefs.pomodoroBreak) * 60 }
    var progress: Double { 1 - Double(max(0, remaining)) / Double(total) }

    func start(_ id: UUID) {
        taskID = id; phase = .work; cycles = 0; paused = nil
        endsAt = Date().addingTimeInterval(TimeInterval(Prefs.pomodoroWork * 60))
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { Focus.shared.tick() }
        }
        NotchController.shared.expand(pinned: false)
    }

    func togglePause() {
        if let p = paused { endsAt = Date().addingTimeInterval(p); paused = nil }
        else { paused = endsAt.timeIntervalSinceNow }
    }

    func skip() { switchPhase(notify: false) }

    func stop() {
        timer?.invalidate(); timer = nil
        taskID = nil; paused = nil
    }

    private func tick() {
        guard active, paused == nil else { return }
        objectWillChange.send() // contador a cada segundo
        if task == nil { stop(); return }
        if endsAt <= Date() { switchPhase(notify: true) }
    }

    private func switchPhase(notify: Bool) {
        if phase == .work {
            cycles += 1
            phase = .rest
            endsAt = Date().addingTimeInterval(TimeInterval(Prefs.pomodoroBreak * 60))
            if notify { Notifier.shared.postInfo("Pausa ☕️", "\(cycles) ciclo(s) em “\(task?.title ?? "")”. \(Prefs.pomodoroBreak) min de descanso.") }
        } else {
            phase = .work
            endsAt = Date().addingTimeInterval(TimeInterval(Prefs.pomodoroWork * 60))
            if notify { Notifier.shared.postInfo("Bora 🎯", "Volta pra “\(task?.title ?? "")” — \(Prefs.pomodoroWork) min.") }
        }
        paused = nil
        NotchController.shared.flash()
    }
}
