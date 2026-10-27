import SwiftUI
import NotchCore

/// Checkbox redondo. Botão simples, sem gestos concorrentes na linha (clique sempre chega).
struct CheckCircle: View {
    var checked: Bool
    var color: Color
    var size: CGFloat = 20
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(checked ? Color.green : color.opacity(hover ? 1 : 0.7), lineWidth: 1.8)
                    .background(Circle().fill(hover && !checked ? color.opacity(0.12) : .clear))
                Circle().fill(Color.green).scaleEffect(checked ? 1 : 0.001)
                Image(systemName: "checkmark").font(.system(size: size * 0.48, weight: .heavy)).foregroundStyle(.white)
                    .scaleEffect(checked ? 1 : 0.3).opacity(checked ? 1 : (hover ? 0.35 : 0))
                    .foregroundStyle(checked ? .white : color)
            }
            .frame(width: size, height: size)
            .contentShape(Circle().inset(by: -6))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(checked ? "Reabrir" : "Concluir")
    }
}

/// Linha de demanda: checkbox, título, metadados, etapas, ações no hover.
struct TaskRow: View {
    @EnvironmentObject var store: Store
    var task: TaskItem
    var compact = false
    @State private var checked = false
    @State private var expanded = false
    @State private var hover = false
    @State private var breaking = false

    var overdue: Bool { store.isOverdue(task) }
    var isChecked: Bool { checked || task.done }
    var accent: Color {
        if overdue { return .red }
        if task.priority >= 2 { return .orange }
        if task.priority == 1 { return .yellow }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 11) {
                CheckCircle(checked: isChecked, color: accent, size: compact ? 17 : 20, action: toggle)
                    .padding(.top, compact ? 0 : 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.system(size: compact ? 12.5 : 14, weight: .medium))
                        .strikethrough(isChecked, color: .secondary)
                        .foregroundStyle(isChecked ? .secondary : .primary)
                        .lineLimit(expanded ? nil : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    meta
                }
                if hover && !compact && !task.done { quickActions.transition(.opacity) }
                if hasDetails {
                    Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                            .rotationEffect(.degrees(expanded ? 90 : 0)).foregroundStyle(.secondary)
                            .frame(width: 22, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help(expanded ? "Recolher" : "Ver etapas e anexos")
                }
            }
            if expanded { details.padding(.leading, compact ? 28 : 31).transition(.opacity) }
        }
        .padding(.vertical, compact ? 5 : 9)
        .padding(.horizontal, compact ? 8 : 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(Focus.shared.taskID == task.id ? 0.09 : (hover ? 0.05 : 0)))
        )
        .overlay(alignment: .leading) {
            if task.priority > 0 && !task.done {
                Capsule().fill(accent).frame(width: 3).padding(.vertical, 8).offset(x: 1)
            }
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .contextMenu { menu }
        .opacity(checked && !task.done && task.recurrence == nil ? 0.55 : 1)
    }

    var hasDetails: Bool { !task.subtasks.isEmpty || !task.notes.isEmpty || !task.attachments.isEmpty }

    var meta: some View {
        HStack(spacing: 5) {
            if task.done, let d = task.doneAt {
                Chip(text: "feita \(Fmt.when(TaskItem.at(d)))", color: .green, icon: "checkmark")
            } else if task.effectiveDue != nil {
                Chip(text: Fmt.when(task), color: overdue ? .red : (task.snoozedUntil != nil ? .purple : .secondary),
                     icon: task.snoozedUntil != nil ? "zzz" : "clock")
            }
            if let r = task.recurrence { Chip(text: r.label, color: .teal, icon: "repeat") }
            if let e = task.estimateMinutes { Chip(text: Fmt.dur(e), color: .indigo, icon: "hourglass") }
            if !task.subtasks.isEmpty {
                Chip(text: "\(task.subtasks.filter(\.done).count)/\(task.subtasks.count)", color: .blue, icon: "checklist")
            }
            if !task.attachments.isEmpty { Chip(text: "\(task.attachments.count)", color: .brown, icon: "paperclip") }
            if task.persistent { Chip(text: "insistente", color: .red, icon: "bell.badge") }
            ForEach(task.tags, id: \.self) { Chip(text: "#" + $0, color: tagColor($0)) }
        }
        // sem ScrollView horizontal: ele engolia a rolagem vertical
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    var quickActions: some View {
        HStack(spacing: 2) {
            iconAction("play.fill", "Começar foco") { Focus.shared.start(task.id) }
            Menu {
                Button("+15 min") { store.snooze(task.id, minutes: 15) }
                Button("+1 hora") { store.snooze(task.id, minutes: 60) }
                Button("+3 horas") { store.snooze(task.id, minutes: 180) }
                Button("Amanhã") { store.snoozeToTomorrow(task.id) }
            } label: { Image(systemName: "clock.arrow.circlepath") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 26).help("Adiar")
            iconAction("pencil", "Editar") { AppDelegate.shared.edit(task.id) }
        }
        .foregroundStyle(.secondary)
    }

    func iconAction(_ icon: String, _ help: String, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
    }

    @ViewBuilder var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !task.notes.isEmpty { Text(task.notes).font(.system(size: 12)).foregroundStyle(.secondary) }
            ForEach(task.subtasks) { s in
                Button { store.toggleSubtask(task.id, s.id) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: s.done ? "checkmark.circle.fill" : "circle").foregroundStyle(s.done ? .green : .secondary)
                        Text(s.title).strikethrough(s.done).foregroundStyle(s.done ? .secondary : .primary)
                    }
                    .font(.system(size: 12.5)).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            ForEach(task.attachments, id: \.self) { a in
                Button { open(a) } label: {
                    Label(display(a), systemImage: a.hasPrefix("http") ? "link" : "doc").font(.system(size: 12)).lineLimit(1)
                }.buttonStyle(.link)
            }
        }
    }

    @ViewBuilder var menu: some View {
        if task.done {
            Button("Reabrir") { store.reopen(task.id) }
        } else {
            Button("Concluir") { toggle() }
            Button("Começar foco (Pomodoro)") { Focus.shared.start(task.id) }
            Divider()
            Button("Adiar 15 min") { store.snooze(task.id, minutes: 15) }
            Button("Adiar 1 hora") { store.snooze(task.id, minutes: 60) }
            Button("Pra amanhã") { store.snoozeToTomorrow(task.id) }
        }
        Divider()
        Button("Editar…") { AppDelegate.shared.edit(task.id) }
        Button(breaking ? "Quebrando…" : "Quebrar em etapas (IA)") { breakDown() }.disabled(breaking)
        if !task.attachments.isEmpty { Button("Abrir anexos") { task.attachments.forEach(open) } }
        Divider()
        Button("Excluir", role: .destructive) { withAnimation { store.delete(task.id) } }
    }

    func toggle() {
        if task.done { withAnimation(.snappy) { store.reopen(task.id) }; return }
        guard !checked else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        Prefs.playSound("Pop")
        withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) { checked = true }
        let id = task.id, s = store
        // curto atraso só pra ver o check; a conclusão acontece no Store mesmo se a linha sumir antes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.snappy) { s.complete(id) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { checked = false }
    }

    func breakDown() {
        breaking = true
        let t = task, s = store
        Task {
            let steps = await Breakdown.subtasks(for: t.title, notes: t.notes)
            s.mutate(t.id) { $0.subtasks += steps.map { Subtask(title: $0) } }
            breaking = false
            withAnimation { expanded = true }
        }
    }
}

extension TaskItem {
    /// Tarefa-fantasma só pra formatar uma data com Fmt.when.
    static func at(_ d: Date) -> TaskItem { var t = TaskItem(title: ""); t.due = d; return t }
}

/// Cartão com título e linhas (usado no Início e nas seções).
struct TaskGroupCard: View {
    var title: String
    var icon: String
    var color: Color
    var tasks: [TaskItem]
    var trailing: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.system(size: 13, weight: .bold))
                Text("\(tasks.count)").font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                if let trailing { Text(trailing).font(.system(size: 11.5)).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
            ForEach(tasks) { TaskRow(task: $0) }
        }
        .padding(.bottom, 6)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}
