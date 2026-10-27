import Foundation

public enum Recurrence: Codable, Equatable, Hashable {
    case daily
    case weekdays
    /// 1 = domingo … 7 = sábado (Calendar.weekday)
    case weekly(Int)
    /// dia do mês
    case monthly(Int)

    public var label: String {
        switch self {
        case .daily: return "todo dia"
        case .weekdays: return "dias úteis"
        case .weekly(let w): return "toda \(Weekday.name(w))"
        case .monthly(let d): return "todo dia \(d)"
        }
    }

    /// Próxima ocorrência estritamente depois de `date`, mantendo hora/minuto.
    public func next(after date: Date, calendar cal: Calendar = .current) -> Date {
        let hm = cal.dateComponents([.hour, .minute], from: date)
        var d = date
        for _ in 0..<400 {
            d = cal.date(byAdding: .day, value: 1, to: d)!
            let wd = cal.component(.weekday, from: d)
            let day = cal.component(.day, from: d)
            let ok: Bool
            switch self {
            case .daily: ok = true
            case .weekdays: ok = (2...6).contains(wd)
            case .weekly(let w): ok = wd == w
            case .monthly(let m):
                let last = cal.range(of: .day, in: .month, for: d)!.count
                ok = day == min(m, last)
            }
            if ok {
                return cal.date(bySettingHour: hm.hour ?? 9, minute: hm.minute ?? 0, second: 0, of: d)!
            }
        }
        return d
    }

    /// Primeira ocorrência em `date` ou depois (mesmo dia conta se o horário ainda não passou).
    public func first(onOrAfter date: Date, hour: Int, minute: Int, now: Date, calendar cal: Calendar = .current) -> Date {
        let sameDay = cal.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
        if sameDay > now && matches(sameDay, cal) { return sameDay }
        return next(after: sameDay, calendar: cal)
    }

    func matches(_ d: Date, _ cal: Calendar) -> Bool {
        let wd = cal.component(.weekday, from: d)
        switch self {
        case .daily: return true
        case .weekdays: return (2...6).contains(wd)
        case .weekly(let w): return wd == w
        case .monthly(let m): return cal.component(.day, from: d) == m
        }
    }
}

public enum Weekday {
    public static func name(_ w: Int) -> String {
        ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"][(w - 1 + 7) % 7]
    }
}

public struct Subtask: Codable, Identifiable, Equatable, Hashable {
    public var id = UUID()
    public var title: String
    public var done = false
    public init(title: String, done: Bool = false) { self.title = title; self.done = done }
}

public struct TaskItem: Codable, Identifiable, Equatable, Hashable {
    public var id = UUID()
    public var title: String
    public var notes = ""
    public var due: Date?
    /// false = só data (dia inteiro); lembrete usa o horário padrão da manhã.
    public var hasTime = true
    public var tags: [String] = []
    /// 0 normal, 1 alta (!), 2 crítica (!!)
    public var priority = 0
    public var subtasks: [Subtask] = []
    public var estimateMinutes: Int?
    public var recurrence: Recurrence?
    /// caminhos de arquivo/pasta ou URLs
    public var attachments: [String] = []
    public var done = false
    public var doneAt: Date?
    public var createdAt = Date()
    public var snoozedUntil: Date?
    /// minutos-antes já disparados para o vencimento atual
    public var firedAlerts: [Int] = []
    /// lembrete insistente: repete até concluir ou adiar
    public var persistent = false
    /// nil = usa padrão das preferências
    public var alertOffsets: [Int]?

    public init(title: String) { self.title = title }

    /// Momento que manda nos lembretes (soneca vence o original).
    public var effectiveDue: Date? { snoozedUntil ?? due }
}

public struct DoneRecord: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var title: String
    public var tags: [String]
    public var date: Date
    public init(title: String, tags: [String], date: Date) { self.title = title; self.tags = tags; self.date = date }
}
