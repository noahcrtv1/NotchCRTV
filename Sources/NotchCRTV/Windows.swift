import AppKit
import SwiftUI
import Charts
import ServiceManagement
import NotchCore

// MARK: - Overlay flutuante

@MainActor
final class OverlayController {
    static let shared = OverlayController()
    private var panel: NSPanel?
    private var timer: Timer?
    private var wanted = false

    func setEnabled(_ on: Bool) {
        wanted = on
        if on {
            if panel == nil { build() }
            refresh()
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                MainActor.assumeIsolated { OverlayController.shared.refresh() }
            }
        } else {
            timer?.invalidate(); timer = nil
            panel?.orderOut(nil)
        }
    }

    /// Some quando o app da frente está na lista ou em tela cheia.
    func refresh() {
        guard wanted, let panel else { return }
        let front = NSWorkspace.shared.frontmostApplication
        let hideByName = front?.localizedName.map { Prefs.overlayHideApps.contains($0) } ?? false
        if hideByName || frontIsFullScreen(front) { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    private func frontIsFullScreen(_ app: NSRunningApplication?) -> Bool {
        guard let pid = app?.processIdentifier, pid != ProcessInfo.processInfo.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let screens = NSScreen.screens.map(\.frame.size)
        return list.contains { w in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid, (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            return screens.contains { $0.width == b["Width"] && $0.height == b["Height"] }
        }
    }

    private func build() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 220),
                        styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        p.level = .floating
        p.isFloatingPanel = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary]
        p.hidesOnDeactivate = false
        p.contentView = NSHostingView(rootView: OverlayView().environmentObject(Store.shared).environmentObject(Focus.shared))
        p.setFrameAutosaveName("NotchCRTVOverlay")
        if !p.setFrameUsingName("NotchCRTVOverlay"), let sc = NSScreen.main {
            p.setFrameOrigin(NSPoint(x: sc.visibleFrame.maxX - 320, y: sc.visibleFrame.maxY - 260))
        }
        panel = p
    }
}

struct OverlayView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var focus: Focus
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(store.urgency.color).frame(width: 8, height: 8)
                Text("NotchCRTV").font(.system(size: 11, weight: .bold))
                if focus.active { Text("· foco \(Fmt.clock(focus.remaining))").font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(.orange) }
                Spacer()
                Button { AppDelegate.shared.capture() } label: { Image(systemName: "plus") }.buttonStyle(.plain)
                Button { Prefs.d.set(false, forKey: Prefs.Key.showOverlay) } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    .help("Esconder overlay")
            }
            .padding(.horizontal, 10).padding(.top, 8)
            let items = Array((store.overdue + store.today + store.upcoming + store.undated).prefix(6))
            if items.isEmpty {
                Text("Tudo em dia ✓").font(.system(size: 12)).foregroundStyle(.secondary).padding(10)
            } else {
                ScrollView { VStack(spacing: 0) { ForEach(items) { TaskRow(task: $0, compact: true) } } }
            }
        }
        .frame(minWidth: 240, minHeight: 120)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(store.urgency == .calm ? Color.primary.opacity(0.08) : store.urgency.color.opacity(0.6)))
    }
}

// MARK: - Barra de menu

struct MenuBarLabel: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var focus: Focus
    var body: some View {
        if focus.active {
            Text("⏱ \(Fmt.clock(focus.remaining))").monospacedDigit()
        } else if let n = store.next, let d = n.effectiveDue, n.hasTime, Calendar.current.isDateInToday(d) || store.isOverdue(n) {
            Text("\(store.isOverdue(n) ? "⚠︎" : "◉") \(store.pending.count) · \(short(n.title)) \(Fmt.time(d))")
        } else {
            Text("◉ \(store.pending.count)")
        }
    }
    func short(_ s: String) -> String { s.count > 22 ? String(s.prefix(21)) + "…" : s }
}

struct MenuBarContent: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Demandas").font(.system(size: 13, weight: .bold))
                Spacer()
                Button { AppDelegate.shared.capture() } label: { Label("Nova", systemImage: "plus") }.buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding(10)
            DayTimeline().environment(\.colorScheme, .dark).padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 10)
            TaskListView(compact: true).frame(height: 380)
            Divider()
            HStack {
                Button("Abrir app") { AppDelegate.shared.showMain() }
                Button("Revisão do dia") { AppDelegate.shared.showReview() }
                Button("Resumo") { Notifier.shared.postSummary() }
                Spacer()
                Button("Ajustes") { AppDelegate.shared.showSettings() }
                Button("Sair") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless).font(.system(size: 11)).padding(10)
        }
        .frame(width: 380)
    }
}

// MARK: - Revisão do fim do dia

struct ReviewView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let list = store.overdue + store.today
        let doneToday = store.history.filter { Calendar.current.isDateInToday($0.date) }
        VStack(alignment: .leading, spacing: 12) {
            Text("Revisão do dia").font(.system(size: 20, weight: .bold))
            Text("\(doneToday.count) concluída(s) hoje · \(list.count) ficou(aram) pendente(s)").foregroundStyle(.secondary)
            if list.isEmpty {
                Label("Nada pendente. Bom trabalho!", systemImage: "checkmark.seal.fill").foregroundStyle(.green).padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(list) { t in
                            HStack {
                                TaskRow(task: t, compact: true)
                                Button("Amanhã") { withAnimation { store.snoozeToTomorrow(t.id) } }
                            }
                        }
                    }
                }
                Button {
                    withAnimation { list.forEach { store.snoozeToTomorrow($0.id) } }
                } label: { Label("Mover todas pra amanhã", systemImage: "sunrise.fill") }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460, height: 440, alignment: .topLeading)
    }
}

// MARK: - Editor

struct EditorView: View {
    @EnvironmentObject var store: Store
    @State var task: TaskItem
    @State private var hasDue: Bool
    @State private var newSub = ""
    @State private var offsetsText: String
    @State private var breaking = false
    var close: () -> Void

    init(task: TaskItem, close: @escaping () -> Void) {
        _task = State(initialValue: task)
        _hasDue = State(initialValue: task.due != nil)
        _offsetsText = State(initialValue: task.alertOffsets.map { $0.map(String.init).joined(separator: ",") } ?? "")
        self.close = close
    }

    var body: some View {
        Form {
            TextField("Título", text: $task.title).font(.system(size: 15, weight: .semibold))
            TextField("Notas", text: $task.notes, axis: .vertical).lineLimit(2...5)
            Section("Quando") {
                Toggle("Tem data", isOn: $hasDue)
                if hasDue {
                    Toggle("Com horário", isOn: $task.hasTime)
                    DatePicker("Data", selection: Binding(get: { task.due ?? Date() }, set: { task.due = $0 }),
                               displayedComponents: task.hasTime ? [.date, .hourAndMinute] : [.date])
                    Picker("Repetir", selection: Binding(get: { RecurrenceChoice(task.recurrence) },
                                                         set: { task.recurrence = $0.value(for: task.due ?? Date()) })) {
                        ForEach(RecurrenceChoice.allCases, id: \.self) { Text($0.rawValue) }
                    }
                }
                TextField("Avisar antes (min, ex: 30,10,0 — vazio = padrão)", text: $offsetsText)
                Toggle("Lembrete insistente (repete até concluir)", isOn: $task.persistent)
            }
            Section("Detalhes") {
                Picker("Prioridade", selection: $task.priority) {
                    Text("Normal").tag(0); Text("Alta !").tag(1); Text("Crítica !!").tag(2)
                }
                TextField("Tags (separadas por espaço)", text: Binding(get: { task.tags.joined(separator: " ") },
                    set: { task.tags = $0.split(separator: " ").map { $0.replacingOccurrences(of: "#", with: "").lowercased() } }))
                Stepper("Estimativa: \(task.estimateMinutes.map(Fmt.dur) ?? "—")",
                        value: Binding(get: { task.estimateMinutes ?? 0 }, set: { task.estimateMinutes = $0 == 0 ? nil : $0 }),
                        in: 0...600, step: 15)
            }
            Section {
                ForEach($task.subtasks) { $s in
                    HStack {
                        Toggle("", isOn: $s.done).labelsHidden()
                        TextField("", text: $s.title)
                        Button { task.subtasks.removeAll { $0.id == s.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Nova etapa", text: $newSub).onSubmit(addSub)
                    Button("Adicionar", action: addSub)
                }
            } header: {
                HStack {
                    Text("Etapas")
                    Spacer()
                    Button(breaking ? "Pensando…" : (Breakdown.aiAvailable ? "✨ Quebrar com IA" : "✨ Sugerir etapas")) {
                        breaking = true
                        Task {
                            let s = await Breakdown.subtasks(for: task.title, notes: task.notes)
                            task.subtasks += s.map { Subtask(title: $0) }
                            breaking = false
                        }
                    }.disabled(breaking)
                }
            }
            Section("Anexos (arquivo, pasta ou link)") {
                ForEach(task.attachments, id: \.self) { a in
                    HStack {
                        Button(display(a)) { open(a) }.buttonStyle(.link)
                        Spacer()
                        Button { task.attachments.removeAll { $0 == a } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                    }
                }
                HStack {
                    Button("Escolher arquivo/pasta…") {
                        let p = NSOpenPanel(); p.canChooseDirectories = true; p.allowsMultipleSelection = true
                        if p.runModal() == .OK { task.attachments += p.urls.map(\.path) }
                    }
                    Button("Colar link") {
                        if let s = NSPasteboard.general.string(forType: .string), s.hasPrefix("http") { task.attachments.append(s) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 620)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar", action: close) }
            ToolbarItem(placement: .confirmationAction) { Button("Salvar", action: save).keyboardShortcut(.defaultAction) }
        }
    }

    func addSub() {
        let s = newSub.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        task.subtasks.append(Subtask(title: s)); newSub = ""
    }

    func save() {
        var t = task
        if !hasDue { t.due = nil; t.recurrence = nil }
        let offs = offsetsText.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        t.alertOffsets = offs.isEmpty ? nil : offs
        if t.alertOffsets != store.task(t.id)?.alertOffsets { t.firedAlerts = [] }
        store.update(t)
        close()
    }
}

enum RecurrenceChoice: String, CaseIterable {
    case none = "Não repete", daily = "Todo dia", weekdays = "Dias úteis", weekly = "Toda semana", monthly = "Todo mês"
    init(_ r: Recurrence?) {
        switch r {
        case nil: self = .none
        case .daily: self = .daily
        case .weekdays: self = .weekdays
        case .weekly: self = .weekly
        case .monthly: self = .monthly
        }
    }
    func value(for d: Date) -> Recurrence? {
        let c = Calendar.current
        switch self {
        case .none: return nil
        case .daily: return .daily
        case .weekdays: return .weekdays
        case .weekly: return .weekly(c.component(.weekday, from: d))
        case .monthly: return .monthly(c.component(.day, from: d))
        }
    }
}

// MARK: - Ajustes + Histórico

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("Geral", systemImage: "gearshape") }
            AlertSettings().tabItem { Label("Lembretes", systemImage: "bell") }
            ContextSettings().tabItem { Label("Apps", systemImage: "app.badge") }
            HistoryView().tabItem { Label("Histórico", systemImage: "chart.bar") }
        }
        .frame(width: 540, height: 460)
    }
}

struct GeneralSettings: View {
    @AppStorage(Prefs.Key.showNotch) var notch = true
    @AppStorage(Prefs.Key.showMenuBar) var menu = true
    @AppStorage(Prefs.Key.showOverlay) var overlay = false
    @AppStorage(Prefs.Key.hotkey) var hotkey = 0
    @AppStorage(Prefs.Key.notchHeight) var notchHeight = 280
    @AppStorage(Prefs.Key.deadlineHour) var deadline = 17
    @AppStorage(Prefs.Key.glass) var glass = true
    @AppStorage(Prefs.Key.islandStyle) var island = true
    @AppStorage(Prefs.Key.pomodoroWork) var work = 25
    @AppStorage(Prefs.Key.pomodoroBreak) var rest = 5
    @AppStorage(Prefs.Key.endOfDayHour) var endHour = 22
    @State private var login = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Onde aparece") {
                Toggle("Notch (ilha no topo)", isOn: $notch)
                Picker("Estilo", selection: $island) {
                    Text("Ilha dinâmica (flutuante)").tag(true)
                    Text("Notch (colado no topo)").tag(false)
                }
                Toggle("Notch aberto em Liquid Glass", isOn: $glass)
                Slider(value: Binding(get: { Double(notchHeight) }, set: { notchHeight = Int($0) }), in: 200...460, step: 20) {
                    Text("Altura do notch aberto: \(notchHeight) px")
                }
                Toggle("Barra de menu", isOn: $menu)
                Toggle("Overlay flutuante", isOn: $overlay)
            }
            Section("Captura rápida") {
                Stepper("Sem data/hora: hoje até as \(deadline)h", value: $deadline, in: 8...23)
                Picker("Atalho global", selection: $hotkey) {
                    ForEach(Hotkey.options.indices, id: \.self) { Text(Hotkey.options[$0].label).tag($0) }
                }
                Text("Também: arraste arquivo/link pro notch, ou selecione texto em qualquer app → Serviços → “Nova demanda no NotchCRTV”.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Foco") {
                Stepper("Pomodoro: \(work) min", value: $work, in: 5...90, step: 5)
                Stepper("Pausa: \(rest) min", value: $rest, in: 1...30)
                Stepper("Fim do expediente: \(endHour)h (aviso de sobrecarga)", value: $endHour, in: 12...24)
            }
            Section {
                Toggle("Abrir ao iniciar o Mac", isOn: $login).onChange(of: login) { _, on in
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch { login = SMAppService.mainApp.status == .enabled }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct AlertSettings: View {
    @AppStorage(Prefs.Key.offsets) var offsets = "15,5,0"
    @AppStorage(Prefs.Key.sound) var sound = "Glass"
    @AppStorage(Prefs.Key.nagMinutes) var nag = 2
    @AppStorage(Prefs.Key.morningSummary) var morning = true
    @AppStorage(Prefs.Key.morningHour) var morningHour = 8
    @AppStorage(Prefs.Key.eveningReview) var review = true
    @AppStorage(Prefs.Key.reviewHour) var reviewHour = 21

    var body: some View {
        Form {
            Section("Avisos") {
                TextField("Minutos antes (separados por vírgula)", text: $offsets)
                Picker("Som", selection: $sound) { ForEach(Prefs.sounds, id: \.self) { Text($0) } }
                    .onChange(of: sound) { _, s in Prefs.playSound(s) }
                Stepper("Insistente: repetir a cada \(nag) min", value: $nag, in: 1...30)
                Text("O som respeita o Foco do macOS (Não Perturbe). Na demanda, use !!! pra deixar insistente.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Rotina") {
                Toggle("Resumo da manhã", isOn: $morning)
                Stepper("às \(morningHour)h", value: $morningHour, in: 4...12).disabled(!morning)
                Toggle("Revisão do fim do dia", isOn: $review)
                Stepper("às \(reviewHour)h", value: $reviewHour, in: 16...23).disabled(!review)
                HStack {
                    Button("Testar resumo") { Notifier.shared.postSummary() }
                    Button("Abrir revisão") { AppDelegate.shared.showReview() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ContextSettings: View {
    @AppStorage(Prefs.Key.appTags) var appTags = ""
    @AppStorage(Prefs.Key.overlayHideApps) var hideApps = ""
    var body: some View {
        Form {
            Section("App em primeiro plano → tag") {
                TextField("App=tag; App=tag", text: $appTags, axis: .vertical).lineLimit(3...6)
                Text("Ex.: Adobe Premiere Pro=edição. Com o app na frente, o notch mostra só #edição e novas demandas ganham a tag.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Adicionar app da frente atual") {
                    if let n = AppDelegate.shared.lastOtherApp {
                        appTags += (appTags.isEmpty ? "" : ";") + "\(n)=" + n.lowercased().split(separator: " ").last!
                    }
                }
            }
            Section("Overlay some quando estes apps estão na frente") {
                TextField("App; App", text: $hideApps)
                Text("Também some com qualquer app em tela cheia.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct HistoryView: View {
    @EnvironmentObject var store: Store
    struct Day: Identifiable { let id: Date; let count: Int }

    var days: [Day] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -i, to: today)!
            return Day(id: d, count: store.history.filter { cal.isDate($0.date, inSameDayAs: d) }.count)
        }
    }

    var body: some View {
        let week = days
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(week.map(\.count).reduce(0, +))").font(.system(size: 34, weight: .bold, design: .rounded))
                Text("concluídas nos últimos 7 dias").foregroundStyle(.secondary)
            }
            Chart(week) { d in
                BarMark(x: .value("Dia", d.id, unit: .day), y: .value("Concluídas", d.count))
                    .foregroundStyle(Calendar.current.isDateInToday(d.id) ? Color.accentColor : Color.accentColor.opacity(0.5))
                    .cornerRadius(4)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated)) } }
            .frame(height: 140)
            let tagCounts = Dictionary(grouping: store.history.filter { $0.date > Date().addingTimeInterval(-7 * 86400) }.flatMap(\.tags), by: { $0 })
                .mapValues(\.count).sorted { $0.value > $1.value }
            if !tagCounts.isEmpty {
                HStack { ForEach(tagCounts.prefix(6), id: \.key) { Chip(text: "#\($0.key) \($0.value)", color: tagColor($0.key)) } }
            }
            List(store.history.suffix(50).reversed()) { r in
                HStack {
                    Text(r.title)
                    Spacer()
                    Text(r.date, format: .dateTime.day().month().hour().minute()).foregroundStyle(.secondary)
                }.font(.system(size: 12))
            }
        }
        .padding()
    }
}
