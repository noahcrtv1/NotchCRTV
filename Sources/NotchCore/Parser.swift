import Foundation

public struct ParsedTask: Equatable {
    public var title: String
    public var due: Date?
    public var hasTime = false
    public var tags: [String] = []
    public var priority = 0
    public var persistent = false
    public var estimateMinutes: Int?
    public var recurrence: Recurrence?
    /// true quando o prazo veio do padrão (texto não tinha data/horário)
    public var defaultedDue = false

    public func makeTask() -> TaskItem {
        var t = TaskItem(title: title)
        t.due = due
        t.hasTime = hasTime
        t.tags = tags
        t.priority = priority
        t.persistent = persistent
        t.estimateMinutes = estimateMinutes
        t.recurrence = recurrence
        return t
    }
}

/// Linguagem natural PT-BR: "editar vídeo Be Brave amanhã 15h #crtv !", "toda sexta 18h",
/// "em 30 min", "dia 15/11 às 9h30", "~1h30" (estimativa), "!!!" (crítica + insistente).
public enum TaskParser {
    public static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "pt_BR")
        c.timeZone = .current
        return c
    }()

    /// Prazo padrão: sem horário vira "até as 17h". Sem data nem horário vira hoje até as 17h.
    public static var defaultHour = 17
    /// Sem data nem horário: true = hoje no horário padrão; false = fica sem data.
    public static var defaultToToday = true

    static let weekdayFull: [String: Int] = [
        "domingo": 1, "segunda": 2, "segunda-feira": 2, "terca": 3, "terca-feira": 3,
        "quarta": 4, "quarta-feira": 4, "quinta": 5, "quinta-feira": 5,
        "sexta": 6, "sexta-feira": 6, "sabado": 7,
    ]
    static let weekdayShort: [String: Int] = ["dom": 1, "seg": 2, "ter": 3, "qua": 4, "qui": 5, "sex": 6, "sab": 7]
    static let months: [String: Int] = [
        "janeiro": 1, "jan": 1, "fevereiro": 2, "fev": 2, "marco": 3, "mar": 3, "abril": 4, "abr": 4,
        "maio": 5, "mai": 5, "junho": 6, "jun": 6, "julho": 7, "jul": 7, "agosto": 8, "ago": 8,
        "setembro": 9, "set": 9, "outubro": 10, "out": 10, "novembro": 11, "nov": 11, "dezembro": 12, "dez": 12,
    ]
    static let numberWords: [String: Int] = [
        "um": 1, "uma": 1, "dois": 2, "duas": 2, "tres": 3, "quatro": 4, "cinco": 5, "seis": 6,
        "dez": 10, "quinze": 15, "vinte": 20, "trinta": 30, "quarenta": 40,
    ]
    static let weekdayLead: Set<String> = ["na", "no", "nessa", "nesta", "neste", "nesse", "proxima", "proximo", "prox"]
    static let timeLead: Set<String> = ["as", "a", "ate", "pelas", "lá", "la"]
    static let danglers: Set<String> = ["de", "as", "às", "na", "no", "em", "para", "pra", "-", "–", ",", "e", "a", "ate", "até"]

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ",.;()\"'"))
    }

    static func match(_ s: String, _ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: "^" + pattern + "$"),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : String(s[Range(r, in: s)!])
        }
    }

    public static func parse(_ text: String, now: Date = Date()) -> ParsedTask {
        let cal = calendar
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let f = words.map(fold)
        let n = words.count
        var used = Set<Int>()

        var out = ParsedTask(title: "")
        var dayOffset: Int?
        var weekday: Int?
        var explicit: (day: Int, month: Int?, year: Int?)?
        var hour: Int?, minute = 0
        var relative: Int?

        func at(_ i: Int) -> String? { i >= 0 && i < n && !used.contains(i) ? f[i] : nil }
        func take(_ idx: Int...) { idx.forEach { used.insert($0) } }
        func takeLead(_ i: Int, _ set: Set<String>) {
            if let p = at(i - 1), set.contains(p) {
                take(i - 1)
                if let pp = at(i - 2), set.contains(pp) { take(i - 2) }
            }
        }
        func int(_ s: String?) -> Int? {
            guard let s else { return nil }
            return Int(s) ?? numberWords[s]
        }
        /// "da tarde"/"da noite"/"da manhã" depois de um horário
        func period(after i: Int) {
            guard let h = hour, at(i + 1) == "da" || at(i + 1) == "de", let p = at(i + 2) else { return }
            switch p {
            case "tarde", "noite": if h < 12 { hour = h + 12 }; take(i + 1, i + 2)
            case "manha", "madrugada": take(i + 1, i + 2)
            default: break
            }
        }
        func unitMinutes(_ u: String) -> Int? {
            switch u {
            case "m", "min", "mins", "minuto", "minutos": return 1
            case "h", "hr", "hrs", "hora", "horas": return 60
            default: return nil
            }
        }

        var i = 0
        while i < n {
            defer { i += 1 }
            guard let w = at(i) else { continue }

            // #tag
            if w.hasPrefix("#"), w.count > 1 {
                out.tags.append(String(w.dropFirst())); take(i); continue
            }
            // ! / !! / !!!
            if let m = match(w, "(!{1,3})") {
                out.priority = m[1].count == 1 ? 1 : 2
                out.persistent = m[1].count == 3
                take(i); continue
            }
            // ~30min / ~1h / ~1h30
            if let m = match(w, "~(\\d+)(min|m|h)?(\\d+)?(min)?") {
                let a = Int(m[1]) ?? 0
                if m[2] == "h" { out.estimateMinutes = a * 60 + (Int(m[3]) ?? 0) } else { out.estimateMinutes = a }
                take(i); continue
            }
            // recorrência
            if ["toda", "todo", "todas", "todos"].contains(w) {
                if at(i + 1) == "os", at(i + 2) == "dias" { out.recurrence = .daily; take(i, i + 1, i + 2); continue }
                if at(i + 1) == "dia" || at(i + 1) == "dias" {
                    if let d = int(at(i + 2)), (1...31).contains(d) { out.recurrence = .monthly(d); take(i, i + 1, i + 2); continue }
                    if at(i + 2) == "util" || at(i + 2) == "uteis" { out.recurrence = .weekdays; take(i, i + 1, i + 2); continue }
                    out.recurrence = .daily; take(i, i + 1); continue
                }
                if at(i + 1) == "mes", at(i + 2) == "dia", let d = int(at(i + 3)), (1...31).contains(d) {
                    out.recurrence = .monthly(d); take(i, i + 1, i + 2, i + 3); continue
                }
                if let nx = at(i + 1), let wd = weekdayFull[nx] ?? weekdayShort[nx] ?? weekdayFull[String(nx.dropLast())] {
                    out.recurrence = .weekly(wd); take(i, i + 1); continue
                }
            }
            if w == "diariamente" { out.recurrence = .daily; take(i); continue }
            if w == "dias", at(i + 1) == "uteis" { out.recurrence = .weekdays; take(i, i + 1); continue }

            // dias relativos
            if w == "hoje" || w == "hj" { dayOffset = 0; take(i); continue }
            if w == "amanha" {
                if at(i - 1) == "de", at(i - 2) == "depois" { dayOffset = 2; take(i - 2, i - 1, i) } else { dayOffset = 1; take(i) }
                continue
            }
            // dia da semana
            if let wd = weekdayFull[w] {
                weekday = wd; take(i); takeLead(i, weekdayLead); continue
            }
            if let wd = weekdayShort[w], let p = at(i - 1), weekdayLead.contains(p) {
                weekday = wd; take(i); takeLead(i, weekdayLead); continue
            }
            // 15/11 ou 15/11/2026
            if let m = match(w, "(\\d{1,2})/(\\d{1,2})(?:/(\\d{2,4}))?"), let dd = Int(m[1]), let mm = Int(m[2]), (1...31).contains(dd), (1...12).contains(mm) {
                var y = Int(m[3]); if let yy = y, yy < 100 { y = 2000 + yy }
                explicit = (Int(m[1])!, Int(m[2])!, y); take(i)
                if at(i - 1) == "dia" { take(i - 1); takeLead(i - 1, ["no", "em"]) } else { takeLead(i, ["em", "no"]) }
                continue
            }
            // dia 15 [de novembro]
            if w == "dia", let d = int(at(i + 1)), (1...31).contains(d) {
                var mo: Int?
                take(i, i + 1)
                if at(i + 2) == "de", let mm = at(i + 3).flatMap({ months[$0] }) { mo = mm; take(i + 2, i + 3) }
                explicit = (d, mo, nil)
                takeLead(i, ["no", "em", "ate"])
                i += 1; continue
            }
            // 15 de novembro
            if let d = Int(w), (1...31).contains(d), at(i + 1) == "de", let mm = at(i + 2).flatMap({ months[$0] }) {
                explicit = (d, mm, nil); take(i, i + 1, i + 2); takeLead(i, ["em", "no"]); continue
            }
            // horários: 15h, 15h30, 15:30, 9hs
            if let m = match(w, "(\\d{1,2})(?:h|hs|hrs|:)(\\d{2})?(?:h|hs|min)?"), let h = Int(m[1]), h < 24 {
                hour = h; minute = Int(m[2]) ?? 0
                take(i); takeLead(i, timeLead); period(after: i); continue
            }
            if w == "meio-dia" || (w == "meio" && at(i + 1) == "dia") {
                hour = 12; minute = 0; take(i); if w == "meio" { take(i + 1) }; takeLead(i, timeLead); continue
            }
            if w == "meia-noite" { hour = 0; minute = 0; take(i); takeLead(i, timeLead); continue }
            // "às 3 [da tarde]"
            if w == "as" || w == "pelas", let h = Int(at(i + 1) ?? ""), h < 24 {
                hour = h; minute = 0; take(i, i + 1); period(after: i + 1); i += 1; continue
            }
            // em 30 min / daqui a 2 horas / em 1h
            if w == "em" || w == "daqui" {
                var j = i + 1
                if at(j) == "a" { j += 1 }
                if at(j) == "meia", at(j + 1) == "hora" {
                    relative = 30; (i...(j + 1)).forEach { take($0) }; i = j + 1; continue
                }
                if let tok = at(j), let m = match(tok, "(\\d+)(min|m|h|hr|hrs)?(\\d{2})?") ?? (numberWords[tok].map { [tok, String($0), "", ""] }) {
                    let a = Int(m[1]) ?? 0
                    if !m[2].isEmpty, let u = unitMinutes(m[2]) {
                        relative = a * u + (Int(m[3]) ?? 0); (i...j).forEach { take($0) }; i = j; continue
                    }
                    if let u = at(j + 1).flatMap(unitMinutes) {
                        relative = a * u; (i...(j + 1)).forEach { take($0) }; i = j + 1; continue
                    }
                }
            }
        }

        // título: o que sobrou, sem preposição pendurada no fim
        var rest = (0..<n).filter { !used.contains($0) }.map { words[$0] }
        while let last = rest.last, danglers.contains(fold(last)) || last == "-" { rest.removeLast() }
        while let first = rest.first, first == "-" || first == "," { rest.removeFirst() }
        out.title = rest.joined(separator: " ")

        // resolve data
        let today = cal.startOfDay(for: now)
        if let r = relative {
            out.due = now.addingTimeInterval(TimeInterval(r * 60)); out.hasTime = true
            return out
        }

        var day: Date?
        if let e = explicit {
            let comps = cal.dateComponents([.year, .month, .day], from: today)
            var dc = DateComponents(year: e.year ?? comps.year, month: e.month ?? comps.month, day: e.day)
            var d = cal.date(from: dc)
            if let dd = d, dd < today, e.year == nil {
                if e.month == nil { dc.month = (comps.month! % 12) + 1; if comps.month == 12 { dc.year = comps.year! + 1 } }
                else { dc.year = comps.year! + 1 }
                d = cal.date(from: dc)
            }
            day = d
        } else if let off = dayOffset {
            day = cal.date(byAdding: .day, value: off, to: today)
        } else if let wd = weekday {
            var diff = (wd - cal.component(.weekday, from: today) + 7) % 7
            if diff == 0 {
                let h = hour ?? defaultHour, mi = hour == nil ? 0 : minute
                let later = cal.date(bySettingHour: h, minute: mi, second: 0, of: today)! > now
                if !later { diff = 7 }
            }
            day = cal.date(byAdding: .day, value: diff, to: today)
        }

        if let rec = out.recurrence {
            out.hasTime = true
            out.due = rec.first(onOrAfter: day ?? today, hour: hour ?? defaultHour, minute: hour == nil ? 0 : minute, now: now, calendar: cal)
            return out
        }

        if let h = hour {
            var d = cal.date(bySettingHour: h, minute: minute, second: 0, of: day ?? today)!
            if day == nil, d <= now { d = cal.date(byAdding: .day, value: 1, to: d)! }
            out.due = d; out.hasTime = true
        } else if let day {
            out.due = cal.date(bySettingHour: defaultHour, minute: 0, second: 0, of: day)
            out.hasTime = true
        } else if defaultToToday {
            // mesmo dia, até o horário padrão; se já passou, até o fim do dia
            let deadline = cal.date(bySettingHour: defaultHour, minute: 0, second: 0, of: today)!
            out.due = deadline > now ? deadline : cal.date(bySettingHour: 23, minute: 59, second: 0, of: today)!
            out.hasTime = true
            out.defaultedDue = true
        }
        return out
    }
}
