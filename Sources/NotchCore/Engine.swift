import Foundation

public enum Urgency: Equatable { case calm, soon, overdue }

/// Toda a regra de negócio das demandas, sem UI e com `now` injetável (testável).
public struct TaskEngine: Equatable {
    public var tasks: [TaskItem]
    public var history: [DoneRecord]
    public var calendar: Calendar

    public init(tasks: [TaskItem] = [], history: [DoneRecord] = [], calendar: Calendar = .current) {
        self.tasks = tasks; self.history = history; self.calendar = calendar
    }

    // MARK: - Consultas

    public var pending: [TaskItem] { tasks.filter { !$0.done } }

    public static func sorted(_ list: [TaskItem]) -> [TaskItem] {
        list.sorted {
            switch ($0.effectiveDue, $1.effectiveDue) {
            case let (a?, b?): return a == b ? ($0.priority == $1.priority ? $0.createdAt < $1.createdAt : $0.priority > $1.priority) : a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return $0.priority == $1.priority ? $0.createdAt < $1.createdAt : $0.priority > $1.priority
            }
        }
    }

    public func isOverdue(_ t: TaskItem, now: Date) -> Bool {
        guard !t.done, let d = t.effectiveDue else { return false }
        return t.hasTime ? d < now : calendar.startOfDay(for: d) < calendar.startOfDay(for: now)
    }

    public func overdue(now: Date) -> [TaskItem] { Self.sorted(pending.filter { isOverdue($0, now: now) }) }

    public func today(now: Date) -> [TaskItem] {
        Self.sorted(pending.filter { t in
            guard let d = t.effectiveDue, !isOverdue(t, now: now) else { return false }
            return calendar.isDate(d, inSameDayAs: now)
        })
    }

    public func upcoming(now: Date) -> [TaskItem] {
        Self.sorted(pending.filter { t in
            guard let d = t.effectiveDue, !isOverdue(t, now: now) else { return false }
            return !calendar.isDate(d, inSameDayAs: now)
        })
    }

    public var undated: [TaskItem] { Self.sorted(pending.filter { $0.effectiveDue == nil }) }

    public var completed: [TaskItem] {
        tasks.filter(\.done).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }

    public func doneCount(on day: Date) -> Int { history.filter { calendar.isDate($0.date, inSameDayAs: day) }.count }

    public func urgency(now: Date) -> Urgency {
        if !overdue(now: now).isEmpty { return .overdue }
        let limit = now.addingTimeInterval(15 * 60)
        if pending.contains(where: { t in t.hasTime && (t.effectiveDue.map { $0 > now && $0 <= limit } ?? false) }) { return .soon }
        return .calm
    }

    /// Minutos estimados das pendentes de hoje (e atrasadas) vs. minutos até `endHour`. nil = cabe.
    public func overload(now: Date, endHour: Int) -> (planned: Int, available: Int)? {
        let planned = (overdue(now: now) + today(now: now)).compactMap(\.estimateMinutes).reduce(0, +)
        guard planned > 0 else { return nil }
        let end = calendar.date(bySettingHour: min(endHour, 23), minute: endHour >= 24 ? 59 : 0, second: 0, of: now)!
        let available = max(0, Int(end.timeIntervalSince(now) / 60))
        return planned > available ? (planned, available) : nil
    }

    public func task(_ id: UUID) -> TaskItem? { tasks.first { $0.id == id } }

    // MARK: - Mudanças

    public mutating func add(_ t: TaskItem) { tasks.append(t) }

    public mutating func update(_ t: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == t.id }) else { return }
        var n = t
        if tasks[i].due != t.due { n.firedAlerts = []; n.snoozedUntil = nil }
        tasks[i] = n
    }

    /// Conclui. Recorrente: registra no histórico e avança pra próxima ocorrência futura.
    public mutating func complete(_ id: UUID, now: Date) {
        guard let i = tasks.firstIndex(where: { $0.id == id }), !tasks[i].done else { return }
        let t = tasks[i]
        history.append(DoneRecord(title: t.title, tags: t.tags, date: now))
        if let rec = t.recurrence, let due = t.due {
            var next = rec.next(after: due, calendar: calendar)
            while next <= now { next = rec.next(after: next, calendar: calendar) }
            tasks[i].due = next
            tasks[i].snoozedUntil = nil
            tasks[i].firedAlerts = []
            for j in tasks[i].subtasks.indices { tasks[i].subtasks[j].done = false }
        } else {
            tasks[i].done = true
            tasks[i].doneAt = now
        }
    }

    public mutating func reopen(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }), tasks[i].done else { return }
        let title = tasks[i].title
        tasks[i].done = false
        tasks[i].doneAt = nil
        if let h = history.lastIndex(where: { $0.title == title }) { history.remove(at: h) }
    }

    public mutating func snooze(_ id: UUID, minutes: Int, now: Date) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].snoozedUntil = now.addingTimeInterval(TimeInterval(minutes * 60))
        tasks[i].firedAlerts = []
        tasks[i].hasTime = true
    }

    /// Joga pra amanhã mantendo o horário (ou `defaultHour` se não tinha).
    public mutating func moveToTomorrow(_ id: UUID, now: Date, defaultHour: Int) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        let t = tasks[i]
        let hm = t.hasTime && t.due != nil ? calendar.dateComponents([.hour, .minute], from: t.due!) : DateComponents(hour: defaultHour, minute: 0)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        tasks[i].due = calendar.date(bySettingHour: hm.hour ?? defaultHour, minute: hm.minute ?? 0, second: 0, of: tomorrow)
        tasks[i].hasTime = true
        tasks[i].snoozedUntil = nil
        tasks[i].firedAlerts = []
    }

    public mutating func delete(_ id: UUID) { tasks.removeAll { $0.id == id } }

    public mutating func clearCompleted() { tasks.removeAll(where: \.done) }

    public mutating func toggleSubtask(_ id: UUID, _ sub: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }),
              let j = tasks[i].subtasks.firstIndex(where: { $0.id == sub }) else { return }
        tasks[i].subtasks[j].done.toggle()
    }

    // MARK: - Lembretes

    /// Qual aviso disparar agora (minutos-antes), ou nil. Escolhe o mais recente vencido ainda não disparado.
    public static func alertToFire(_ t: TaskItem, offsets: [Int], now: Date) -> Int? {
        guard !t.done, let due = t.effectiveDue else { return nil }
        let offs = t.hasTime ? offsets : [0]
        return offs.filter { now >= due.addingTimeInterval(TimeInterval(-$0 * 60)) && !t.firedAlerts.contains($0) }.min()
    }

    /// Marca como disparados todos os avisos >= offset (os anteriores perderam a vez).
    public mutating func markFired(_ id: UUID, upTo offset: Int, offsets: [Int]) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        let offs = tasks[i].hasTime ? offsets : [0]
        for o in offs where o >= offset && !tasks[i].firedAlerts.contains(o) { tasks[i].firedAlerts.append(o) }
    }

    // MARK: - Persistência

    public static func encode<T: Encodable>(_ v: T) throws -> Data {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(v)
    }

    public static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try dec.decode(type, from: data)
    }
}
