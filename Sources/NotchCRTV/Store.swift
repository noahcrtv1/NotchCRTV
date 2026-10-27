import AppKit
import NotchCore

/// Fachada do app sobre o TaskEngine (regras testadas no NotchCore): publica mudanças e salva em disco.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var engine = TaskEngine()
    /// tag destacada pelo app em primeiro plano (ex.: Premiere → "edição")
    @Published var contextTag: String?
    @Published var contextApp: String?
    @Published var now = Date()
    @Published var loadError: String?

    private let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchCRTV", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private var tasksURL: URL { dir.appendingPathComponent("tasks.json") }
    private var historyURL: URL { dir.appendingPathComponent("history.json") }

    private init() {
        engine = TaskEngine(tasks: load([TaskItem].self, tasksURL) ?? [], history: load([DoneRecord].self, historyURL) ?? [])
        // relógio publicado a cada 15 s (contagens/regressivas); o notch tem o próprio a cada 1 s quando há foco
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            MainActor.assumeIsolated { Store.shared.now = Date() }
        }
    }

    private func load<T: Decodable>(_ type: T.Type, _ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do { return try TaskEngine.decode(type, data) } catch {
            // não sobrescreve: guarda cópia do arquivo ruim
            try? FileManager.default.copyItem(at: url, to: url.appendingPathExtension("corrompido-\(Int(Date().timeIntervalSince1970))"))
            loadError = "Não consegui ler \(url.lastPathComponent); cópia salva ao lado."
            return nil
        }
    }

    private func change(_ f: (inout TaskEngine) -> Void) {
        var e = engine
        f(&e)
        guard e != engine else { return }
        engine = e
        now = Date()
        try? TaskEngine.encode(engine.tasks).write(to: tasksURL, options: .atomic)
        try? TaskEngine.encode(engine.history).write(to: historyURL, options: .atomic)
    }

    // MARK: - Consultas

    var tasks: [TaskItem] { engine.tasks }
    var history: [DoneRecord] { engine.history }
    var pending: [TaskItem] { engine.pending }
    var overdue: [TaskItem] { engine.overdue(now: now) }
    var today: [TaskItem] { engine.today(now: now) }
    var upcoming: [TaskItem] { engine.upcoming(now: now) }
    var undated: [TaskItem] { engine.undated }
    var completed: [TaskItem] { engine.completed }
    var urgency: Urgency { engine.urgency(now: now) }
    var overload: (planned: Int, available: Int)? { engine.overload(now: now, endHour: Prefs.endOfDayHour) }
    var doneToday: Int { engine.doneCount(on: now) }

    func sorted(_ l: [TaskItem]) -> [TaskItem] { TaskEngine.sorted(l) }
    func isOverdue(_ t: TaskItem) -> Bool { engine.isOverdue(t, now: now) }
    func task(_ id: UUID) -> TaskItem? { engine.task(id) }

    /// Próxima (atrasadas primeiro), respeitando o filtro de contexto.
    var next: TaskItem? {
        let base = contextTag.map { tag in pending.filter { $0.tags.contains(tag) } } ?? pending
        return sorted(base).first
    }

    // MARK: - Mudanças

    @discardableResult
    func add(_ t: TaskItem) -> TaskItem { change { $0.add(t) }; return t }
    func update(_ t: TaskItem) { change { $0.update(t) } }
    func mutate(_ id: UUID, _ f: (inout TaskItem) -> Void) {
        change { e in if let i = e.tasks.firstIndex(where: { $0.id == id }) { f(&e.tasks[i]) } }
    }

    func complete(_ id: UUID) {
        change { $0.complete(id, now: Date()) }
        Notifier.shared.clear(id)
        if Focus.shared.taskID == id, task(id)?.done != false { Focus.shared.stop() }
    }

    func reopen(_ id: UUID) { change { $0.reopen(id) } }

    func snooze(_ id: UUID, minutes: Int) {
        change { $0.snooze(id, minutes: minutes, now: Date()) }
        Notifier.shared.clear(id)
    }

    func snoozeToTomorrow(_ id: UUID) {
        change { $0.moveToTomorrow(id, now: Date(), defaultHour: Prefs.deadlineHour) }
        Notifier.shared.clear(id)
    }

    func delete(_ id: UUID) {
        change { $0.delete(id) }
        Notifier.shared.clear(id)
        if Focus.shared.taskID == id { Focus.shared.stop() }
    }

    func clearCompleted() { change { $0.clearCompleted() } }
    func toggleSubtask(_ id: UUID, _ sub: UUID) { change { $0.toggleSubtask(id, sub) } }

    func markFired(_ id: UUID, upTo offset: Int) {
        guard let t = task(id) else { return }
        change { $0.markFired(id, upTo: offset, offsets: Prefs.offsets(for: t)) }
    }

    /// Cria demanda a partir de texto livre (+ anexos opcionais). Sem data/hora: hoje até as 17h.
    @discardableResult
    func quickAdd(_ text: String, attachments: [String] = []) -> TaskItem? {
        TaskParser.defaultHour = Prefs.deadlineHour
        let p = TaskParser.parse(text)
        guard !p.title.isEmpty || !attachments.isEmpty else { return nil }
        var t = p.makeTask()
        if t.title.isEmpty { t.title = attachments.first.map(display) ?? "Demanda" }
        t.attachments = attachments
        if t.tags.isEmpty, let ctx = contextTag { t.tags = [ctx] }
        return add(t)
    }
}
