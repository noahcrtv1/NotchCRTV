import Foundation
import NotchCore

// Testes de lógica (parser, recorrência, ações, lembretes, persistência). swift run SelfTest
// Relógio fixo: segunda-feira, 26/10/2026 10:00.

let cal = TaskParser.calendar
func date(_ d: Int, _ m: Int, _ h: Int = 0, _ mi: Int = 0, y: Int = 2026) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
}
let now = date(26, 10, 10)
let df = DateFormatter()
df.locale = Locale(identifier: "pt_BR")
df.dateFormat = "dd/MM HH:mm"

var passed = 0, failed = 0, group = ""
func suite(_ name: String) { group = name; print("\n— \(name)") }
func expect(_ cond: @autoclosure () -> Bool, _ label: String, _ detail: @autoclosure () -> String = "") {
    if cond() { passed += 1 } else { failed += 1; print("FAIL [\(group)] \(label) \(detail())") }
}

// MARK: - Parser

suite("Parser PT-BR")
func check(_ input: String, at: Date = now, title: String, due: String?, tags: [String] = [], prio: Int = 0,
           rec: Recurrence? = nil, est: Int? = nil, persistent: Bool = false, defaulted: Bool = false) {
    let p = TaskParser.parse(input, now: at)
    let got = p.due.map(df.string)
    var errs: [String] = []
    if p.title != title { errs.append("title '\(p.title)' != '\(title)'") }
    if got != due { errs.append("due \(got ?? "nil") != \(due ?? "nil")") }
    if p.tags != tags { errs.append("tags \(p.tags)") }
    if p.priority != prio { errs.append("prio \(p.priority)") }
    if p.recurrence != rec { errs.append("rec \(String(describing: p.recurrence))") }
    if p.estimateMinutes != est { errs.append("est \(String(describing: p.estimateMinutes))") }
    if p.persistent != persistent { errs.append("persistent \(p.persistent)") }
    if p.defaultedDue != defaulted { errs.append("defaulted \(p.defaultedDue)") }
    if p.due != nil && !p.hasTime { errs.append("hasTime false") }
    expect(errs.isEmpty, "“\(input)”", errs.joined(separator: "; "))
}

check("editar vídeo Be Brave amanhã 15h", title: "editar vídeo Be Brave", due: "27/10 15:00")
check("ligar pro João às 14h30 #igreja !", title: "ligar pro João", due: "26/10 14:30", tags: ["igreja"], prio: 1)
check("reunião 9h", title: "reunião", due: "27/10 09:00")
check("toda sexta 18h ensaio", title: "ensaio", due: "30/10 18:00", rec: .weekly(6))
check("postar stories todo dia 20h", title: "postar stories", due: "26/10 20:00", rec: .daily)
check("pagar aluguel todo dia 5", title: "pagar aluguel", due: "05/11 17:00", rec: .monthly(5))
check("tirar lixo em 30 min", title: "tirar lixo", due: "26/10 10:30")
check("daqui a 2 horas ver render", title: "ver render", due: "26/10 12:00")
check("entregar arte dia 15/11 às 9h30 ~1h30 !!", title: "entregar arte", due: "15/11 09:30", prio: 2, est: 90)
check("culto na quarta às 7 da noite", title: "culto", due: "28/10 19:00")
check("comprar cabo segunda", title: "comprar cabo", due: "26/10 17:00")
check("comprar cabo segunda", at: date(26, 10, 18), title: "comprar cabo", due: "02/11 17:00")
check("depois de amanhã revisar contrato", title: "revisar contrato", due: "28/10 17:00")
check("relatório dias úteis 8h", title: "relatório", due: "27/10 08:00", rec: .weekdays)
check("renovar domínio dia 20 de novembro", title: "renovar domínio", due: "20/11 17:00")
check("backup HD !!!", title: "backup HD", due: "26/10 17:00", prio: 2, persistent: true, defaulted: true)
check("ter ideia de vídeo", title: "ter ideia de vídeo", due: "26/10 17:00", defaulted: true)
check("algo pra fazer", at: date(26, 10, 18, 30), title: "algo pra fazer", due: "26/10 23:59", defaulted: true)
check("as fotos do evento hoje meio-dia", title: "as fotos do evento", due: "26/10 12:00")
check("call na sex 16h", title: "call", due: "30/10 16:00")
check("dentista em 1h", title: "dentista", due: "26/10 11:00")
check("fechar mês dia 3", title: "fechar mês", due: "03/11 17:00")
check("render em 90 min", title: "render", due: "26/10 11:30")
check("subir vídeo em 1h30", title: "subir vídeo", due: "26/10 11:30")
check("às 9 café", title: "café", due: "27/10 09:00")
check("backup meia-noite", title: "backup", due: "27/10 00:00")
check("toda segunda às 8h reunião", title: "reunião", due: "02/11 08:00", rec: .weekly(2))
check("todo dia 26 fatura", title: "fatura", due: "26/10 17:00", rec: .monthly(26))
check("todos os dias 7h orar", title: "orar", due: "27/10 07:00", rec: .daily)
check("arte ~45min #crtv #igreja", title: "arte", due: "26/10 17:00", tags: ["crtv", "igreja"], est: 45, defaulted: true)
check("data 15/13 errada", title: "data 15/13 errada", due: "26/10 17:00", defaulted: true)
check("às 25h algo", title: "às 25h algo", due: "26/10 17:00", defaulted: true)
check("ENTREGAR AMANHÃ ÀS 14H", title: "ENTREGAR", due: "27/10 14:00")
check("hoje 9h relatório", title: "relatório", due: "26/10 09:00")
check("dia 28/10/2027 viagem", title: "viagem", due: "28/10 17:00")
check("prova 10/01", title: "prova", due: "10/01 17:00")
expect(TaskParser.parse("prova 10/01", now: now).due.map { cal.component(.year, from: $0) } == 2027, "data passada sem ano vai pro ano seguinte")
check("   ", title: "", due: "26/10 17:00", defaulted: true)
check("revisar - amanhã", title: "revisar", due: "27/10 17:00")

// MARK: - Recorrência

suite("Recorrência")
expect(Recurrence.weekdays.next(after: date(30, 10, 18)) == date(2, 11, 18), "dias úteis: sexta → segunda")
expect(Recurrence.monthly(31).next(after: date(31, 10, 9)) == date(30, 11, 9), "dia 31 em mês de 30 dias")
expect(Recurrence.weekly(6).next(after: date(30, 10, 18)) == date(6, 11, 18), "semanal: próxima sexta")
expect(Recurrence.daily.next(after: date(31, 12, 7)) == date(1, 1, 7, y: 2027), "virada de ano")
expect(Recurrence.monthly(5).label == "todo dia 5" && Recurrence.weekly(6).label == "toda sexta", "rótulos")

// MARK: - Ações

suite("Ações")
func task(_ title: String, due: Date?, hasTime: Bool = true, prio: Int = 0, est: Int? = nil, rec: Recurrence? = nil) -> TaskItem {
    var t = TaskItem(title: title)
    t.due = due; t.hasTime = hasTime; t.priority = prio; t.estimateMinutes = est; t.recurrence = rec
    t.createdAt = date(20, 10, 8)
    return t
}

do {
    var e = TaskEngine(calendar: cal)
    let a = task("A", due: date(26, 10, 15))
    e.add(a)
    e.complete(a.id, now: now)
    expect(e.task(a.id)?.done == true, "concluir marca done")
    expect(e.task(a.id)?.doneAt == now, "doneAt = agora")
    expect(e.history.count == 1, "histórico +1")
    expect(e.pending.isEmpty && e.completed.count == 1, "sai das pendentes, vai pras concluídas")
    e.complete(a.id, now: now)
    expect(e.history.count == 1, "concluir duas vezes não duplica histórico")
    e.reopen(a.id)
    expect(e.task(a.id)?.done == false && e.history.isEmpty && e.pending.count == 1, "reabrir desfaz tudo")
    e.reopen(a.id)
    expect(e.pending.count == 1, "reabrir pendente não quebra")
    e.complete(UUID(), now: now)
    expect(e.history.isEmpty, "id inexistente é ignorado")
}

do {
    var e = TaskEngine(calendar: cal)
    var r = task("Stories", due: date(23, 10, 20), rec: .daily)
    r.subtasks = [Subtask(title: "gravar", done: true)]
    r.firedAlerts = [15, 5, 0]
    r.snoozedUntil = date(23, 10, 21)
    e.add(r)
    e.complete(r.id, now: now)
    let t = e.task(r.id)!
    expect(!t.done, "recorrente continua pendente")
    expect(t.due == date(26, 10, 20), "recorrente atrasada 3 dias pula pra próxima futura", df.string(from: t.due!))
    expect(t.firedAlerts.isEmpty && t.snoozedUntil == nil, "recorrente zera avisos e soneca")
    expect(t.subtasks.allSatisfy { !$0.done }, "recorrente zera etapas")
    expect(e.history.count == 1, "recorrente registra histórico")
    e.complete(r.id, now: now)
    expect(e.task(r.id)!.due == date(27, 10, 20) && e.history.count == 2, "recorrente concluída de novo avança mais um dia")
}

do {
    var e = TaskEngine(calendar: cal)
    var a = task("A", due: date(26, 10, 9))
    a.firedAlerts = [15, 5, 0]
    e.add(a)
    expect(e.isOverdue(a, now: now), "9h é atrasada às 10h")
    e.snooze(a.id, minutes: 5, now: now)
    let s = e.task(a.id)!
    expect(s.effectiveDue == date(26, 10, 10, 5), "soneca +5 min")
    expect(!e.isOverdue(s, now: now) && s.firedAlerts.isEmpty, "soneca tira do atraso e rearma avisos")
    e.moveToTomorrow(a.id, now: now, defaultHour: 17)
    let m = e.task(a.id)!
    expect(m.due == date(27, 10, 9) && m.snoozedUntil == nil, "amanhã mantém o horário", df.string(from: m.due!))
    let b = task("B", due: nil)
    e.add(b)
    e.moveToTomorrow(b.id, now: now, defaultHour: 17)
    expect(e.task(b.id)!.due == date(27, 10, 17) && e.task(b.id)!.hasTime, "amanhã sem data usa 17h")
    e.delete(a.id)
    expect(e.task(a.id) == nil && e.tasks.count == 1, "excluir")
    var c = task("C", due: nil)
    c.subtasks = [Subtask(title: "x")]
    e.add(c)
    e.toggleSubtask(c.id, c.subtasks[0].id)
    expect(e.task(c.id)!.subtasks[0].done, "marcar etapa")
    e.complete(c.id, now: now)
    e.clearCompleted()
    expect(e.task(c.id) == nil && e.task(b.id) != nil, "limpar concluídas só remove feitas")
}

do {
    var e = TaskEngine(calendar: cal)
    var moved = task("Mudar", due: date(26, 10, 15))
    e.add(moved)
    moved.firedAlerts = [15]
    e.update(moved)
    moved.due = date(26, 10, 16)
    e.update(moved)
    expect(e.task(moved.id)!.firedAlerts.isEmpty, "mudar horário rearma avisos")
}

// MARK: - Seções e urgência

suite("Seções e urgência")
do {
    let late = task("atrasada", due: date(26, 10, 9))
    let lateDay = task("ontem", due: date(25, 10, 17))
    let soon = task("logo", due: date(26, 10, 10, 10), est: 30)
    let later = task("tarde", due: date(26, 10, 16), est: 60)
    let tomorrow = task("amanhã", due: date(27, 10, 9))
    let none = task("sem", due: nil)
    var done = task("feita", due: date(26, 10, 8)); done.done = true
    let e = TaskEngine(tasks: [later, none, tomorrow, soon, late, lateDay, done], calendar: cal)
    let o = e.overdue(now: now).map(\.title), t = e.today(now: now).map(\.title)
    let u = e.upcoming(now: now).map(\.title), n = e.undated.map(\.title)
    expect(o == ["ontem", "atrasada"], "atrasadas em ordem", "\(o)")
    expect(t == ["logo", "tarde"], "hoje em ordem", "\(t)")
    expect(u == ["amanhã"], "próximas", "\(u)")
    expect(n == ["sem"], "sem horário")
    expect(Set(o + t + u + n).count == e.pending.count && e.pending.count == 6, "seções cobrem todas as pendentes sem repetir")
    expect(e.urgency(now: now) == .overdue, "urgência: atrasada")
    let e2 = TaskEngine(tasks: [soon, later], calendar: cal)
    expect(e2.urgency(now: now) == .soon, "urgência: em 10 min")
    expect(TaskEngine(tasks: [later], calendar: cal).urgency(now: now) == .calm, "urgência: calma")
    expect(e2.overload(now: now, endHour: 22) == nil, "sem sobrecarga")
    let o2 = e2.overload(now: date(26, 10, 21, 30), endHour: 22)
    expect(o2?.planned == 90 && o2?.available == 30, "sobrecarga: 90 min pra 30 livres", "\(String(describing: o2))")
    expect(e2.overload(now: now, endHour: 24) == nil, "fim do expediente 24h não quebra")
    let hi = task("alta", due: date(26, 10, 16), prio: 2)
    expect(TaskEngine.sorted([later, hi, none]).map(\.title) == ["alta", "tarde", "sem"], "ordenação: prioridade no empate, sem data no fim")
}

// MARK: - Lembretes

suite("Lembretes")
do {
    let offs = [15, 5, 0]
    var e = TaskEngine(calendar: cal)
    let t = task("Reunião", due: date(26, 10, 10, 20))
    e.add(t)
    expect(TaskEngine.alertToFire(e.task(t.id)!, offsets: offs, now: now) == nil, "20 min antes: nada")
    let at6 = date(26, 10, 10, 6)
    expect(TaskEngine.alertToFire(e.task(t.id)!, offsets: offs, now: at6) == 15, "14 min antes: aviso de 15")
    e.markFired(t.id, upTo: 15, offsets: offs)
    expect(TaskEngine.alertToFire(e.task(t.id)!, offsets: offs, now: at6) == nil, "não repete o de 15")
    expect(TaskEngine.alertToFire(e.task(t.id)!, offsets: offs, now: date(26, 10, 10, 16)) == 5, "4 min antes: aviso de 5")
    let late = date(26, 10, 11)
    let u = TaskEngine(tasks: [t], calendar: cal)
    expect(TaskEngine.alertToFire(u.task(t.id)!, offsets: offs, now: late) == 0, "app fechado: dispara só o de agora")
    var u2 = u
    u2.markFired(t.id, upTo: 0, offsets: offs)
    expect(u2.task(t.id)!.firedAlerts.sorted() == [0, 5, 15], "marca todos os anteriores")
    expect(TaskEngine.alertToFire(u2.task(t.id)!, offsets: offs, now: late) == nil, "nada mais depois")
    var allDay = task("dia", due: date(26, 10, 17), hasTime: false)
    expect(TaskEngine.alertToFire(allDay, offsets: offs, now: date(26, 10, 16, 50)) == nil, "sem horário: só avisa na hora")
    expect(TaskEngine.alertToFire(allDay, offsets: offs, now: date(26, 10, 17)) == 0, "sem horário: aviso na hora")
    allDay.done = true
    expect(TaskEngine.alertToFire(allDay, offsets: offs, now: date(26, 10, 18)) == nil, "concluída não avisa")
    var custom = task("custom", due: date(26, 10, 11))
    custom.alertOffsets = [60]
    expect(TaskEngine.alertToFire(custom, offsets: custom.alertOffsets!, now: now) == 60, "aviso personalizado de 60 min")
    var snoozed = task("soneca", due: date(26, 10, 9))
    snoozed.snoozedUntil = date(26, 10, 10, 30)
    expect(TaskEngine.alertToFire(snoozed, offsets: offs, now: now) == nil, "soneca adia o aviso")
}

// MARK: - Persistência

suite("Persistência")
do {
    var t = task("Persistir", due: date(26, 10, 15), prio: 2, est: 30, rec: .weekly(3))
    t.tags = ["crtv"]; t.subtasks = [Subtask(title: "a")]; t.attachments = ["/tmp/x", "https://a.b"]
    t.notes = "ção ✓"; t.persistent = true; t.alertOffsets = [10]
    let h = [DoneRecord(title: "x", tags: ["y"], date: date(25, 10, 9))]
    let data = try! TaskEngine.encode([t])
    let back = try! TaskEngine.decode([TaskItem].self, data)
    expect(back == [t], "tarefas: ida e volta idênticas")
    expect(try! TaskEngine.decode([DoneRecord].self, TaskEngine.encode(h)) == h, "histórico: ida e volta")
    for r in [Recurrence.daily, .weekdays, .weekly(5), .monthly(31)] {
        expect(try! TaskEngine.decode(Recurrence.self, TaskEngine.encode(r)) == r, "recorrência \(r.label) codifica")
    }
    expect((try? TaskEngine.decode([TaskItem].self, Data("lixo".utf8))) == nil, "arquivo corrompido não derruba (retorna erro)")
}

// MARK: - Fluxo completo

suite("Fluxo: criar pelo texto → concluir")
do {
    var e = TaskEngine(calendar: cal)
    let p = TaskParser.parse("editar culto #igreja !", now: now)
    e.add(p.makeTask())
    let id = e.tasks[0].id
    expect(e.today(now: now).count == 1, "sem data entra em Hoje")
    expect(e.task(id)!.due == date(26, 10, 17), "prazo 17h")
    e.complete(id, now: now)
    expect(e.today(now: now).isEmpty && e.completed.first?.id == id && e.doneCount(on: now) == 1, "concluir tira de Hoje e conta no dia")
}

print("\n\(passed) ok, \(failed) falha(s)")
print(failed == 0 ? "TUDO OK" : "FALHOU")
exit(failed == 0 ? 0 : 1)
