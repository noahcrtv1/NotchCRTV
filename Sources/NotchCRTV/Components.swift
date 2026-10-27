import SwiftUI
import NotchCore

extension Urgency {
    var color: Color {
        switch self {
        case .calm: return .green
        case .soon: return .yellow
        case .overdue: return .red
        }
    }
}

struct Chip: View {
    var text: String
    var color: Color = .secondary
    var icon: String?
    var body: some View {
        HStack(spacing: 3) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .semibold)) }
            Text(text).lineLimit(1)
        }
        .font(.system(size: 10, weight: .medium))
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.16), in: Capsule())
        .foregroundStyle(color)
    }
}

func tagColor(_ tag: String) -> Color {
    let palette: [Color] = [.pink, .orange, .mint, .cyan, .purple, .yellow, .green, .blue]
    let h = tag.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff }
    return palette[h % palette.count]
}

func open(_ attachment: String) {
    if attachment.hasPrefix("http"), let u = URL(string: attachment) { NSWorkspace.shared.open(u) }
    else { NSWorkspace.shared.open(URL(fileURLWithPath: attachment)) }
}

func display(_ attachment: String) -> String {
    attachment.hasPrefix("http") ? (URL(string: attachment)?.host ?? attachment) : URL(fileURLWithPath: attachment).lastPathComponent
}

/// Seções: Atrasadas / Hoje / Próximas / Sem horário / Concluídas.
struct TaskListView: View {
    @EnvironmentObject var store: Store
    var compact = false
    var filterTag: String?
    @State private var showDone = false

    func f(_ l: [TaskItem]) -> [TaskItem] { filterTag.map { tag in l.filter { $0.tags.contains(tag) } } ?? l }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                section("Atrasadas", f(store.overdue), color: .red, icon: "exclamationmark.circle.fill")
                if let o = store.overload, filterTag == nil {
                    Label("\(Fmt.dur(o.planned)) de demandas e só \(Fmt.dur(o.available)) até as \(Prefs.endOfDayHour)h",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.orange)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.vertical, 4)
                }
                section("Hoje", f(store.today), color: .accentColor, icon: "sun.max.fill")
                section("Próximas", f(store.upcoming), color: .blue, icon: "calendar")
                section("Sem horário", f(store.undated), color: .secondary, icon: "tray.fill")
                let done = f(store.completed)
                if !done.isEmpty {
                    Button { withAnimation(.snappy) { showDone.toggle() } } label: {
                        HStack {
                            Label("Concluídas (\(done.count))", systemImage: "checkmark.circle.fill")
                            Spacer()
                            Image(systemName: showDone ? "chevron.up" : "chevron.down")
                        }
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.top, 10).padding(.horizontal, 8)
                    }.buttonStyle(.plain)
                    if showDone {
                        ForEach(done.prefix(30)) { TaskRow(task: $0, compact: true) }
                        Button("Limpar concluídas") { store.clearCompleted() }.buttonStyle(.link).font(.system(size: 11)).padding(8)
                    }
                }
                if store.pending.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 28)).foregroundStyle(.green)
                        Text("Tudo em dia").font(.system(size: 13, weight: .semibold))
                        Text("Atalho \(Hotkey.options[Prefs.d.integer(forKey: Prefs.Key.hotkey)].label) pra adicionar")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 24)
                }
            }
            .padding(.horizontal, 6).padding(.bottom, 8)
        }
    }

    @ViewBuilder func section(_ title: String, _ items: [TaskItem], color: Color, icon: String) -> some View {
        if !items.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: icon).foregroundStyle(color)
                Text(title.uppercased()).foregroundStyle(.secondary)
                Text("\(items.count)").foregroundStyle(.tertiary)
                if title == "Hoje" {
                    let mins = items.compactMap(\.estimateMinutes).reduce(0, +)
                    if mins > 0 { Spacer(); Text("≈ \(Fmt.dur(mins))").foregroundStyle(.tertiary) }
                }
            }
            .font(.system(size: 10.5, weight: .bold))
            .padding(.top, 10).padding(.bottom, 2).padding(.horizontal, 8)
            ForEach(items) { TaskRow(task: $0, compact: compact) }
        }
    }
}

/// Linha do tempo horizontal do dia (6h–24h) com as demandas marcadas e o "agora".
struct DayTimeline: View {
    @EnvironmentObject var store: Store
    var startHour = 6
    var endHour = 24

    var body: some View {
        let cal = Calendar.current
        let day = cal.startOfDay(for: store.now)
        let start = day.addingTimeInterval(TimeInterval(startHour * 3600))
        let span = TimeInterval((endHour - startHour) * 3600)
        let items = (store.overdue + store.today).filter(\.hasTime)
        GeometryReader { g in
            let w = g.size.width
            let x: (Date) -> CGFloat = { d in CGFloat(min(max(d.timeIntervalSince(start) / span, 0), 1)) * w }
            ZStack(alignment: .topLeading) {
                Capsule().fill(Color.white.opacity(0.10)).frame(height: 4).offset(y: 14)
                Capsule().fill(Color.white.opacity(0.35)).frame(width: x(store.now), height: 4).offset(y: 14)
                ForEach(Array(stride(from: startHour, through: endHour, by: 3)), id: \.self) { h in
                    Text("\(h % 24)h").font(.system(size: 8.5, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                        .position(x: CGFloat(h - startHour) / CGFloat(endHour - startHour) * w, y: 30)
                }
                ForEach(items) { t in
                    let d = t.effectiveDue!
                    let est = t.estimateMinutes.map { CGFloat(TimeInterval($0 * 60) / span) * w } ?? 0
                    ZStack(alignment: .leading) {
                        if est > 0 { Capsule().fill(color(t).opacity(0.35)).frame(width: max(est, 8), height: 8) }
                        Circle().fill(color(t)).frame(width: 9, height: 9)
                    }
                    .help("\(Fmt.time(d)) · \(t.title)")
                    .offset(x: x(d) - 4.5, y: 11.5)
                }
                Rectangle().fill(Color.white).frame(width: 2, height: 16).offset(x: x(store.now) - 1, y: 8)
            }
        }
        .frame(height: 38)
    }

    func color(_ t: TaskItem) -> Color {
        if store.isOverdue(t) { return .red }
        if let d = t.effectiveDue, d.timeIntervalSince(store.now) < 15 * 60 { return .yellow }
        return t.tags.first.map(tagColor) ?? .green
    }
}
