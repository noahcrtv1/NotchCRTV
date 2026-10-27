import SwiftUI
import NotchCore

/// Janela principal. "Início" mostra tudo que precisa ser feito; o notch fica pra olhada rápida.
enum MainSection: Hashable {
    case home, today, overdue, upcoming, all, done, history
    case tag(String)

    var title: String {
        switch self {
        case .home: return "Início"
        case .today: return "Hoje"
        case .overdue: return "Atrasadas"
        case .upcoming: return "Próximas"
        case .all: return "Todas a fazer"
        case .done: return "Concluídas"
        case .history: return "Histórico"
        case .tag(let t): return "#" + t
        }
    }
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .today: return "sun.max.fill"
        case .overdue: return "exclamationmark.circle.fill"
        case .upcoming: return "calendar"
        case .all: return "tray.full.fill"
        case .done: return "checkmark.circle.fill"
        case .history: return "chart.bar.fill"
        case .tag: return "number"
        }
    }
    var color: Color {
        switch self {
        case .home: return .accentColor
        case .today: return .orange
        case .overdue: return .red
        case .upcoming: return .blue
        case .all: return .gray
        case .done: return .green
        case .history: return .purple
        case .tag(let t): return tagColor(t)
        }
    }
}

final class MainNav: ObservableObject {
    static let shared = MainNav()
    @Published var section: MainSection? = .home
}

struct MainView: View {
    @EnvironmentObject var store: Store
    @ObservedObject var nav = MainNav.shared
    @State private var search = ""

    var allTags: [String] { Array(Set(store.pending.flatMap(\.tags))).sorted() }

    var body: some View {
        NavigationSplitView {
            List(selection: $nav.section) {
                row(.home, nil)
                Section("A fazer") {
                    row(.today, store.today.count + store.overdue.count)
                    row(.overdue, store.overdue.count)
                    row(.upcoming, store.upcoming.count)
                    row(.all, store.pending.count)
                }
                Section("Feito") {
                    row(.done, store.completed.count)
                    row(.history, nil)
                }
                if !allTags.isEmpty {
                    Section("Tags") {
                        ForEach(allTags, id: \.self) { t in row(.tag(t), store.pending.filter { $0.tags.contains(t) }.count) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 215)
        } detail: {
            Group {
                if !search.isEmpty {
                    SearchResults(search: search)
                } else {
                    switch nav.section ?? .home {
                    case .home: HomeView()
                    case .history: HistoryView()
                    case let s: SectionView(section: s)
                    }
                }
            }
            .navigationTitle(search.isEmpty ? (nav.section ?? .home).title : "Busca")
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Buscar demandas")
        .toolbar {
            ToolbarItem {
                Button { AppDelegate.shared.capture() } label: { Label("Nova demanda", systemImage: "plus") }
                    .help("Nova demanda (⌥Espaço em qualquer app)")
            }
            ToolbarItem {
                Button { AppDelegate.shared.showSettings() } label: { Label("Ajustes", systemImage: "gearshape") }
            }
        }
        .frame(minWidth: 780, minHeight: 520)
        .overlay(alignment: .bottom) {
            if let err = store.loadError {
                Label(err, systemImage: "exclamationmark.triangle.fill").padding(10)
                    .background(.orange.opacity(0.2), in: Capsule()).padding()
            }
        }
    }

    func row(_ s: MainSection, _ count: Int?) -> some View {
        HStack {
            Label { Text(s.title) } icon: { Image(systemName: s.icon).foregroundStyle(s.color) }
            Spacer()
            if let count, count > 0 {
                Text("\(count)").font(.caption.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(s == .overdue ? .red : .secondary)
            }
        }
        .tag(s)
    }
}

/// Campo de nova demanda com prévia do que foi entendido.
struct QuickAddField: View {
    @EnvironmentObject var store: Store
    var placeholder = "Nova demanda… ex: editar vídeo sexta 15h #crtv ~2h"
    var extra: (String) -> String = { $0 }
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(Color.accentColor)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain).font(.system(size: 15))
                    .focused($focused)
                    .onSubmit(add)
                if !text.isEmpty {
                    Button("Adicionar", action: add).buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
            if !text.isEmpty { preview.transition(.opacity) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(focused ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.06), lineWidth: focused ? 1.5 : 1))
        .animation(.easeOut(duration: 0.15), value: text.isEmpty)
    }

    var preview: some View {
        TaskParser.defaultHour = Prefs.deadlineHour
        let p = TaskParser.parse(extra(text))
        return HStack(spacing: 6) {
            Text("Entendi:").font(.system(size: 11)).foregroundStyle(.secondary)
            Chip(text: p.title.isEmpty ? "sem título" : p.title, color: .primary)
            if p.due != nil {
                Chip(text: (p.defaultedDue ? "até " : "") + Fmt.when(p.makeTask()), color: .accentColor, icon: "clock")
            }
            if let r = p.recurrence { Chip(text: r.label, color: .teal, icon: "repeat") }
            if p.priority > 0 { Chip(text: p.priority == 1 ? "alta" : "crítica", color: .orange, icon: "exclamationmark") }
            if let e = p.estimateMinutes { Chip(text: Fmt.dur(e), color: .indigo, icon: "hourglass") }
            ForEach(p.tags, id: \.self) { Chip(text: "#" + $0, color: tagColor($0)) }
        }
        .fixedSize().frame(maxWidth: .infinity, alignment: .leading).clipped()
    }

    func add() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation(.snappy) { _ = store.quickAdd(extra(text)) }
        Prefs.playSound("Pop")
        text = ""
        focused = true
    }
}

// MARK: - Início

struct HomeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var focus: Focus

    var body: some View {
        let cal = Calendar.current
        let up = store.upcoming
        let tomorrow = up.filter { $0.effectiveDue.map(cal.isDateInTomorrow) ?? false }
        let weekEnd = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: store.now))!
        let week = up.filter { t in !tomorrow.contains(t) && (t.effectiveDue.map { $0 < weekEnd } ?? false) }
        let later = up.filter { t in !tomorrow.contains(t) && !week.contains(t) }
        let doneToday = store.completed.filter { $0.doneAt.map(cal.isDateInToday) ?? false }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                greeting
                QuickAddField()
                stats
                if let n = store.next, !n.done { NextCard(task: n) }
                if !(store.overdue + store.today).isEmpty {
                    DayTimeline()
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .environment(\.colorScheme, .dark)
                }
                if let o = store.overload {
                    Label("\(Fmt.dur(o.planned)) de demandas e só \(Fmt.dur(o.available)) até as \(Prefs.endOfDayHour)h — adie algo pra amanhã",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.medium)).foregroundStyle(.orange)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                if store.pending.isEmpty {
                    ContentUnavailableView("Tudo em dia", systemImage: "checkmark.seal.fill",
                                           description: Text("Nada pendente. Adicione acima ou com ⌥Espaço."))
                        .padding(.vertical, 30)
                }
                group("Atrasadas", "exclamationmark.circle.fill", .red, store.overdue)
                group("Hoje", "sun.max.fill", .orange, store.today, trailing: estimate(store.today))
                group("Amanhã", "sunrise.fill", .yellow, tomorrow)
                group("Próximos 7 dias", "calendar", .blue, week)
                group("Mais pra frente", "calendar.badge.clock", .indigo, later)
                group("Sem data", "tray.fill", .gray, store.undated)
                group("Feitas hoje", "checkmark.circle.fill", .green, doneToday)
            }
            .padding(24)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .animation(.snappy, value: store.pending.map(\.id))
    }

    @ViewBuilder func group(_ title: String, _ icon: String, _ color: Color, _ tasks: [TaskItem], trailing: String? = nil) -> some View {
        if !tasks.isEmpty { TaskGroupCard(title: title, icon: icon, color: color, tasks: tasks, trailing: trailing) }
    }

    func estimate(_ l: [TaskItem]) -> String? {
        let m = l.compactMap(\.estimateMinutes).reduce(0, +)
        return m > 0 ? "≈ \(Fmt.dur(m)) estimadas" : nil
    }

    var greeting: some View {
        let h = Calendar.current.component(.hour, from: store.now)
        let hi = h < 12 ? "Bom dia" : h < 18 ? "Boa tarde" : "Boa noite"
        let f = DateFormatter(); f.locale = Locale(identifier: "pt_BR"); f.dateFormat = "EEEE, d 'de' MMMM"
        let left = store.overdue.count + store.today.count
        return VStack(alignment: .leading, spacing: 4) {
            Text(f.string(from: store.now).capitalized).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            Text(left == 0 ? "\(hi)! Nada pendente pra hoje." : "\(hi)! \(left) \(left == 1 ? "demanda" : "demandas") pra hoje.")
                .font(.system(size: 26, weight: .bold))
        }
    }

    var stats: some View {
        HStack(spacing: 12) {
            StatCard(value: store.overdue.count, label: "Atrasadas", icon: "exclamationmark.circle.fill", color: .red, target: .overdue)
            StatCard(value: store.today.count, label: "Hoje", icon: "sun.max.fill", color: .orange, target: .today)
            StatCard(value: store.upcoming.count, label: "Próximas", icon: "calendar", color: .blue, target: .upcoming)
            StatCard(value: store.doneToday, label: "Feitas hoje", icon: "checkmark.circle.fill", color: .green, target: .done)
        }
    }
}

struct StatCard: View {
    var value: Int
    var label: String
    var icon: String
    var color: Color
    var target: MainSection
    @State private var hover = false

    var body: some View {
        Button { MainNav.shared.section = target } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
                Text("\(value)").font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(color.opacity(hover ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .animation(.snappy, value: value)
    }
}

/// Destaque da próxima demanda com ações grandes.
struct NextCard: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var focus: Focus
    var task: TaskItem

    var body: some View {
        let overdue = store.isOverdue(task)
        let tint: Color = overdue ? .red : (store.urgency == .soon ? .orange : .accentColor)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(focus.taskID == task.id ? "EM FOCO" : overdue ? "ATRASADA" : "PRÓXIMA")
                    .font(.system(size: 11, weight: .heavy)).foregroundStyle(tint)
                Spacer()
                if focus.taskID == task.id {
                    Text(Fmt.clock(focus.remaining)).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                } else if let d = task.effectiveDue {
                    Text(Fmt.relative(d, now: store.now)).font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(overdue ? .red : .primary)
                }
            }
            Text(task.title).font(.system(size: 20, weight: .bold)).lineLimit(2)
            if !task.tags.isEmpty || task.estimateMinutes != nil {
                HStack(spacing: 5) {
                    if let e = task.estimateMinutes { Chip(text: Fmt.dur(e), color: .indigo, icon: "hourglass") }
                    ForEach(task.tags, id: \.self) { Chip(text: "#" + $0, color: tagColor($0)) }
                }
            }
            HStack(spacing: 8) {
                Button { withAnimation(.snappy) { store.complete(task.id) }; Prefs.playSound("Pop") } label: {
                    Label("Concluir", systemImage: "checkmark")
                }.buttonStyle(.borderedProminent).tint(.green)
                if focus.taskID == task.id {
                    Button { focus.stop() } label: { Label("Parar foco", systemImage: "stop.fill") }.buttonStyle(.bordered)
                } else {
                    Button { focus.start(task.id) } label: { Label("Começar foco", systemImage: "play.fill") }.buttonStyle(.bordered)
                }
                Menu {
                    Button("+15 min") { store.snooze(task.id, minutes: 15) }
                    Button("+1 hora") { store.snooze(task.id, minutes: 60) }
                    Button("Amanhã") { store.snoozeToTomorrow(task.id) }
                } label: { Label("Adiar", systemImage: "clock.arrow.circlepath") }
                    .fixedSize()
                Spacer()
                Button("Editar") { AppDelegate.shared.edit(task.id) }.buttonStyle(.link)
            }
            .controlSize(.large)
        }
        .padding(18)
        .background(
            LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.25)))
    }
}

// MARK: - Seções

struct SectionView: View {
    @EnvironmentObject var store: Store
    var section: MainSection

    var items: [TaskItem] {
        switch section {
        case .today: return store.overdue + store.today
        case .overdue: return store.overdue
        case .upcoming: return store.upcoming
        case .all: return store.sorted(store.pending)
        case .done: return store.completed
        case .tag(let t): return store.sorted(store.pending.filter { $0.tags.contains(t) })
        case .home, .history: return []
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if section != .done && section != .overdue {
                    QuickAddField(placeholder: placeholder, extra: extra)
                }
                if section == .today && !items.isEmpty {
                    DayTimeline()
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .environment(\.colorScheme, .dark)
                }
                if items.isEmpty {
                    ContentUnavailableView(section == .done ? "Nada concluído ainda" : "Tudo em dia",
                                           systemImage: section == .done ? "tray" : "checkmark.seal.fill")
                        .padding(.vertical, 40)
                } else if section == .done {
                    doneGroups
                } else {
                    TaskGroupCard(title: section.title, icon: section.icon, color: section.color, tasks: items)
                }
            }
            .padding(24).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }
        .animation(.snappy, value: items.map(\.id))
    }

    var placeholder: String {
        if case .tag(let t) = section { return "Nova demanda em #\(t)…" }
        return "Nova demanda… (sem data = hoje até as \(Prefs.deadlineHour)h)"
    }

    func extra(_ text: String) -> String {
        if case .tag(let tag) = section, !text.lowercased().contains("#\(tag)") { return text + " #\(tag)" }
        return text
    }

    @ViewBuilder var doneGroups: some View {
        let cal = Calendar.current
        let groups = Dictionary(grouping: items) { cal.startOfDay(for: $0.doneAt ?? $0.createdAt) }.sorted { $0.key > $1.key }
        ForEach(groups, id: \.key) { day, tasks in
            TaskGroupCard(title: dayLabel(day), icon: "checkmark.circle.fill", color: .green, tasks: tasks)
        }
        Button("Limpar concluídas") { withAnimation { store.clearCompleted() } }.buttonStyle(.link)
    }

    func dayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Hoje" }
        if cal.isDateInYesterday(d) { return "Ontem" }
        let f = DateFormatter(); f.locale = Locale(identifier: "pt_BR"); f.dateFormat = "EEEE, d 'de' MMMM"
        return f.string(from: d).capitalized
    }
}

struct SearchResults: View {
    @EnvironmentObject var store: Store
    var search: String
    var body: some View {
        let hits = store.tasks.filter { t in
            t.title.localizedCaseInsensitiveContains(search) || t.notes.localizedCaseInsensitiveContains(search)
                || t.tags.contains { $0.localizedCaseInsensitiveContains(search) }
        }
        ScrollView {
            VStack(spacing: 16) {
                let open = store.sorted(hits.filter { !$0.done }), done = hits.filter(\.done)
                if hits.isEmpty { ContentUnavailableView.search(text: search).padding(.vertical, 40) }
                if !open.isEmpty { TaskGroupCard(title: "A fazer", icon: "circle", color: .accentColor, tasks: open) }
                if !done.isEmpty { TaskGroupCard(title: "Concluídas", icon: "checkmark.circle.fill", color: .green, tasks: done) }
            }
            .padding(24).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }
    }
}
