import AppKit
import SwiftUI
import NotchCore

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchState: ObservableObject {
    enum Tab: String, CaseIterable { case now = "Agora", today = "Hoje", list = "Lista" }
    /// lógico: painel aberto (janela grande, área de hover grande)
    @Published var expanded = false
    // fases visuais, animadas em sequência: largura → altura → conteúdo
    @Published var openW = false
    @Published var openH = false
    @Published var showContent = false
    var generation = 0
    @Published var pinned = false
    @Published var flashing = false
    @Published var dropping = false
    @Published var tab: Tab = .now
    @Published var filterContext = true
    var notchSize = CGSize(width: 190, height: 32)
    var hasNotch = true
    let earWidth: CGFloat = 74
    let glow: CGFloat = 16
    /// estilo Ilha dinâmica: pílula flutuante abaixo da barra de menu
    @Published var island = true
    var topGap: CGFloat { island ? notchSize.height + 6 : 0 }
    var islandHeight: CGFloat { 34 }
    func closedSize(ears: Bool) -> CGSize {
        island ? CGSize(width: ears ? 320 : 150, height: islandHeight)
               : CGSize(width: notchSize.width + (ears ? earWidth * 2 : 0), height: notchSize.height)
    }
    var contentTop: CGFloat { island ? 14 : notchSize.height + 2 }
    func shape(open: Bool) -> AnyShape {
        island ? AnyShape(RoundedRectangle(cornerRadius: open ? 28 : islandHeight / 2, style: .continuous))
               : AnyShape(NotchShape(bottomRadius: open ? 24 : 10, topRadius: open ? 10 : 6))
    }
    var expandedSize: CGSize {
        CGSize(width: 560, height: CGFloat(max(200, Prefs.d.integer(forKey: Prefs.Key.notchHeight))))
    }
}

/// Janela-ilha sobre o notch. Recolhida: só "orelhas" com status. Hover/clique: expande.
@MainActor
final class NotchController {
    static let shared = NotchController()
    let state = NotchState()
    private var panel: NotchPanel?
    private var collapseWork: DispatchWorkItem?
    private var clickMonitor: Any?
    private var hoverTimer: Timer?
    private var hoverSince: Date?
    private var outsideSince: Date?

    /// Área "quente": recolhido = notch + orelhas; expandido = painel inteiro com folga.
    private var hotRect: NSRect {
        let sc = screen
        if state.expanded {
            let s = state.expandedSize
            return NSRect(x: sc.frame.midX - s.width / 2, y: sc.frame.maxY - state.topGap - s.height, width: s.width, height: s.height + state.topGap)
                .insetBy(dx: -24, dy: -24)
        }
        let c = state.closedSize(ears: true)
        return NSRect(x: sc.frame.midX - c.width / 2, y: sc.frame.maxY - state.topGap - c.height - 4, width: c.width, height: c.height + state.topGap + 4)
    }

    func trackMouse() {
        guard visible else { return }
        let inside = hotRect.contains(NSEvent.mouseLocation)
        let now = Date()
        if state.expanded {
            if inside { outsideSince = nil; return }
            if outsideSince == nil { outsideSince = now }
            // não recolhe com menu de contexto aberto ou arrastando
            if now.timeIntervalSince(outsideSince!) > 0.6, NSEvent.pressedMouseButtons == 0, !state.dropping {
                outsideSince = nil
                collapse(after: 0)
            }
        } else {
            outsideSince = nil
            if inside {
                if hoverSince == nil { hoverSince = now }
                if now.timeIntervalSince(hoverSince!) > 0.1 { hoverSince = nil; expand(pinned: false) }
            } else { hoverSince = nil }
        }
    }

    var visible: Bool { panel?.isVisible ?? false }

    func show() {
        if panel == nil { build() }
        layout()
        panel?.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    private func build() {
        let p = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar + 1
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.isMovable = false
        p.hidesOnDeactivate = false
        let root = NotchView().environmentObject(Store.shared).environmentObject(state).environmentObject(Focus.shared)
            .environment(\.colorScheme, .dark)
        // container com autoresizing evita loop de constraints do NSHostingView ao redimensionar o painel
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 60))
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = true
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        p.contentView = container
        panel = p
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NotchController.shared.layout() }
        }
        // Hover por posição do mouse (onHover do SwiftUI perde o rastreio quando o painel muda de tamanho).
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            MainActor.assumeIsolated { NotchController.shared.trackMouse() }
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated {
                let s = NotchController.shared.state
                if s.expanded { s.pinned = false; NotchController.shared.collapse(after: 0) }
            }
        }
    }

    var screen: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    func layout() {
        guard let panel else { return }
        let sc = screen
        if sc.safeAreaInsets.top > 0, let l = sc.auxiliaryTopLeftArea, let r = sc.auxiliaryTopRightArea {
            state.hasNotch = true
            state.notchSize = CGSize(width: sc.frame.width - l.width - r.width, height: sc.safeAreaInsets.top)
        } else {
            state.hasNotch = false
            state.notchSize = CGSize(width: 160, height: max(24, NSStatusBar.system.thickness))
        }
        state.island = Prefs.d.bool(forKey: Prefs.Key.islandStyle)
        let body = state.expanded ? state.expandedSize : state.closedSize(ears: true)
        let size = CGSize(width: body.width + state.glow * 2, height: state.topGap + body.height + state.glow * (state.island ? 2 : 1))
        let frame = NSRect(x: sc.frame.midX - size.width / 2, y: sc.frame.maxY - size.height, width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
    }

    func expand(pinned: Bool) {
        collapseWork?.cancel()
        if pinned { state.pinned = true }
        guard !state.expanded else { return }
        if !visible { show() }
        state.generation += 1
        state.expanded = true
        layout() // janela já no tamanho cheio antes de animar
        let s = state
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { s.openW = true }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.66).delay(0.05)) { s.openH = true }
            withAnimation(.easeOut(duration: 0.24).delay(0.14)) { s.showContent = true }
        }
    }

    func collapse(after delay: TimeInterval) {
        collapseWork?.cancel()
        let w = DispatchWorkItem {
            MainActor.assumeIsolated {
                let s = NotchController.shared.state
                guard s.expanded, s.openH, !s.pinned else { return }
                s.generation += 1
                let gen = s.generation
                withAnimation(.easeIn(duration: 0.1)) { s.showContent = false }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9).delay(0.06)) { s.openH = false }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.92).delay(0.12)) { s.openW = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
                    MainActor.assumeIsolated {
                        guard s.generation == gen else { return } // reaberto no meio
                        s.expanded = false
                        NotchController.shared.layout()
                    }
                }
            }
        }
        collapseWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    func toggle() { state.expanded ? { state.pinned = false; collapse(after: 0) }() : expand(pinned: true) }

    func flash() {
        state.flashing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { MainActor.assumeIsolated { NotchController.shared.state.flashing = false } }
    }
}

struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var topRadius: CGFloat = 6
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(bottomRadius, topRadius) }
        set { bottomRadius = newValue.first; topRadius = newValue.second }
    }
    func path(in r: CGRect) -> Path {
        var p = Path()
        let t = topRadius, b = bottomRadius
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + t, y: r.minY + t), control: CGPoint(x: r.minX + t, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + t, y: r.maxY - b))
        p.addQuadCurve(to: CGPoint(x: r.minX + t + b, y: r.maxY), control: CGPoint(x: r.minX + t, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t - b, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - t, y: r.maxY - b), control: CGPoint(x: r.maxX - t, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t, y: r.minY + t))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - t, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct NotchView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var state: NotchState
    @EnvironmentObject var focus: Focus
    @State private var pulse = false

    var showEars: Bool { !store.pending.isEmpty || focus.active || state.flashing || state.dropping }
    var alerting: Bool { state.flashing || store.urgency != .calm }

    var size: CGSize {
        let closed = state.closedSize(ears: showEars)
        return CGSize(width: state.openW ? state.expandedSize.width : closed.width,
                      height: state.openH ? state.expandedSize.height : closed.height)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                background
                    .shadow(color: .black.opacity(state.island ? 0.35 : 0), radius: 10, y: 4)
                    .shadow(color: glowColor.opacity(alerting ? (pulse ? 0.95 : 0.35) : 0), radius: pulse ? 9 : 4)
                if state.expanded {
                    ExpandedNotch().padding(.top, state.contentTop).padding(.horizontal, 18).padding(.bottom, 12)
                        .frame(width: state.expandedSize.width, height: state.expandedSize.height, alignment: .top)
                        .opacity(state.showContent ? 1 : 0)
                        .blur(radius: state.showContent ? 0 : 6)
                        .offset(y: state.showContent ? 0 : -10)
                        .allowsHitTesting(state.showContent)
                        // recorta só o conteúdo (o brilho de alerta fica fora do recorte)
                        .frame(width: size.width, height: size.height, alignment: .top)
                        .clipShape(state.shape(open: state.openH))
                }
                collapsed
                    .opacity(state.openW ? 0 : 1)
                    .scaleEffect(x: state.openW ? 0.55 : 1, y: 1)
                    .allowsHitTesting(!state.openW)
                if state.dropping {
                    state.shape(open: state.openH).stroke(Color.accentColor, lineWidth: 2)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture { if !state.expanded { NotchController.shared.expand(pinned: true) } }
            .onDrop(of: [.fileURL, .url, .plainText], isTargeted: $state.dropping, perform: drop)
            .padding(.top, state.topGap)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: showEars)
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true } }
    }

    /// Recolhido: preto (se funde com o notch físico). Aberto: Liquid Glass escuro, com o recorte da câmera preto.
    @ViewBuilder var background: some View {
        let shape = state.shape(open: state.openH)
        if glass {
            // vidro sempre presente; o preto por cima some durante a abertura (sem troca brusca)
            ZStack(alignment: .top) {
                shape.fill(Color.clear)
                    .glassEffect(.regular.tint(.black.opacity(0.35)), in: shape)
                shape.fill(Color.black).opacity(state.openH ? 0 : 1)
                if state.hasNotch && !state.island {
                    UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                        .fill(Color.black)
                        .frame(width: state.notchSize.width, height: state.notchSize.height)
                }
            }
        } else {
            shape.fill(Color.black)
        }
    }

    @AppStorage(Prefs.Key.glass) private var glass = true

    var glowColor: Color { state.flashing && store.urgency == .calm ? .accentColor : store.urgency.color }

    @ViewBuilder var collapsed: some View {
        if state.island { islandCollapsed } else { notchCollapsed }
    }

    /// Ilha recolhida: status · próxima demanda · tempo, tudo dentro da pílula.
    var islandCollapsed: some View {
        HStack(spacing: 9) {
            Circle().fill(store.urgency.color).frame(width: 8, height: 8)
                .scaleEffect(alerting && pulse ? 1.35 : 1)
            if showEars {
                if focus.active, let t = focus.task {
                    Text(t.title).lineLimit(1)
                } else if let n = store.next {
                    Text(n.title).lineLimit(1)
                }
                Spacer(minLength: 4)
                rightEar
                Text("\(store.pending.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.white.opacity(0.15), in: Capsule())
            } else {
                Text("Tudo em dia").foregroundStyle(.white.opacity(0.8))
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: state.islandHeight)
    }

    var notchCollapsed: some View {
        HStack(spacing: 0) {
            if showEars {
                HStack(spacing: 6) {
                    Circle().fill(store.urgency.color).frame(width: 7, height: 7)
                        .scaleEffect(alerting && pulse ? 1.35 : 1)
                    Text("\(store.pending.count)").font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white)
                }
                .frame(width: state.earWidth, alignment: .center)
            }
            Spacer(minLength: state.notchSize.width)
            if showEars {
                rightEar.frame(width: state.earWidth, alignment: .center)
            }
        }
        .frame(height: state.notchSize.height)
    }

    @ViewBuilder var rightEar: some View {
        if focus.active {
            HStack(spacing: 5) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.2), lineWidth: 2.2)
                    Circle().trim(from: 0, to: focus.progress).stroke(focus.phase == .work ? Color.orange : Color.mint, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }.frame(width: 12, height: 12)
                Text(Fmt.clock(focus.remaining)).font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.white)
            }
        } else if let n = store.next, let d = n.effectiveDue, n.hasTime {
            Text(Fmt.relative(d, now: store.now))
                .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(store.isOverdue(n) ? .red : .white.opacity(0.9))
                .lineLimit(1).minimumScaleFactor(0.7)
        } else if state.dropping {
            Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
        }
    }

    func drop(_ providers: [NSItemProvider]) -> Bool {
        var paths: [String] = []
        var text: String?
        let group = DispatchGroup()
        for p in providers {
            if p.hasItemConformingToTypeIdentifier("public.file-url") {
                group.enter()
                _ = p.loadObject(ofClass: URL.self) { u, _ in if let u { paths.append(u.isFileURL ? u.path : u.absoluteString) }; group.leave() }
            } else if p.hasItemConformingToTypeIdentifier("public.url") {
                group.enter()
                _ = p.loadObject(ofClass: URL.self) { u, _ in if let u { paths.append(u.absoluteString) }; group.leave() }
            } else if p.canLoadObject(ofClass: String.self) {
                group.enter()
                _ = p.loadObject(ofClass: String.self) { s, _ in text = s; group.leave() }
            }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated {
                let title = text ?? paths.first.map(display) ?? ""
                AppDelegate.shared.capture(prefill: title, attachments: paths)
            }
        }
        return true
    }
}

struct ExpandedNotch: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var state: NotchState
    @EnvironmentObject var focus: Focus

    var filter: String? { state.filterContext ? store.contextTag : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Group {
                switch state.tab {
                case .now: NowPane(filter: filter)
                case .today: TodayPane()
                case .list: TaskListView(compact: true, filterTag: filter)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .foregroundStyle(.white)
    }

    var header: some View {
        HStack(spacing: 8) {
            Picker("", selection: $state.tab) {
                ForEach(NotchState.Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 190)
            if let app = store.contextApp, let tag = store.contextTag {
                Button { state.filterContext.toggle() } label: {
                    Chip(text: "\(app) · #\(tag)", color: state.filterContext ? tagColor(tag) : .gray, icon: "app.badge")
                }
                .buttonStyle(.plain)
                .help(state.filterContext ? "Mostrando só #\(tag) — clique pra ver tudo" : "Filtrar por #\(tag)")
            }
            Spacer()
            iconButton("plus", "Nova demanda") { AppDelegate.shared.capture() }
            iconButton("macwindow", "Abrir app") { AppDelegate.shared.showMain() }
            iconButton(state.pinned ? "pin.fill" : "pin", "Fixar aberto") { state.pinned.toggle() }
            iconButton("gearshape", "Ajustes") { AppDelegate.shared.showSettings() }
        }
    }

    func iconButton(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 22).background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain).help(help)
    }
}

/// Aba "Agora": foco ativo ou a próxima demanda com ações rápidas.
struct NowPane: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var focus: Focus
    var filter: String?

    var body: some View {
        if focus.active, let t = focus.task {
            focusView(t)
        } else if let t = nextTask {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    card(t)
                    let rest = Array(laterTasks.prefix(10))
                    if !rest.isEmpty {
                        Text("DEPOIS").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).padding(.leading, 8)
                        ForEach(rest) { TaskRow(task: $0, compact: true) }
                    }
                }
            }
            .scrollIndicators(.never)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 34)).foregroundStyle(.green)
                Text(filter.map { "Nada em #\($0)" } ?? "Tudo em dia").font(.system(size: 14, weight: .semibold))
                Button("Nova demanda") { AppDelegate.shared.capture() }.buttonStyle(.borderedProminent)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    var base: [TaskItem] { filter.map { tag in store.pending.filter { $0.tags.contains(tag) } } ?? store.pending }
    var nextTask: TaskItem? { store.sorted(base).first }
    var laterTasks: [TaskItem] { Array(store.sorted(base).dropFirst()) }

    func card(_ t: TaskItem) -> some View {
        let overdue = store.isOverdue(t)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(overdue ? "ATRASADA" : "PRÓXIMA").font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(overdue ? .red : store.urgency == .soon ? .yellow : .green)
                Spacer()
                if let d = t.effectiveDue {
                    Text(t.hasTime ? Fmt.relative(d, now: store.now) : Fmt.when(t))
                        .font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(overdue ? .red : .white)
                }
            }
            TaskRow(task: t)
            HStack(spacing: 6) {
                action("play.fill", "Começar", .orange) { Focus.shared.start(t.id) }
                action("checkmark", "Concluir", .green) { withAnimation { store.complete(t.id) } }
                action("zzz", "+5 min", .purple) { store.snooze(t.id, minutes: 5) }
                action("clock.arrow.circlepath", "+1h", .purple) { store.snooze(t.id, minutes: 60) }
                action("sunrise", "Amanhã", .blue) { store.snoozeToTomorrow(t.id) }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    func action(_ icon: String, _ label: String, _ color: Color, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            Label(label, systemImage: icon).font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(color.opacity(0.22), in: Capsule()).foregroundStyle(color)
        }.buttonStyle(.plain)
    }

    func focusView(_ t: TaskItem) -> some View {
        VStack(spacing: 12) {
            Text(focus.phase == .work ? "FOCO · ciclo \(focus.cycles + 1)" : "PAUSA")
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(focus.phase == .work ? .orange : .mint)
            HStack(spacing: 22) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 8)
                    Circle().trim(from: 0, to: focus.progress)
                        .stroke(focus.phase == .work ? Color.orange : Color.mint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: focus.progress)
                    Text(Fmt.clock(focus.remaining)).font(.system(size: 21, weight: .bold, design: .rounded)).monospacedDigit()
                }
                .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 8) {
                    Text(t.title).font(.system(size: 17, weight: .bold)).lineLimit(3)
                    ForEach(t.subtasks.prefix(5)) { s in
                        Button { store.toggleSubtask(t.id, s.id) } label: {
                            Label(s.title, systemImage: s.done ? "checkmark.square.fill" : "square")
                                .font(.system(size: 12)).foregroundStyle(s.done ? .secondary : .primary)
                        }.buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 6) {
                action(focus.paused == nil ? "pause.fill" : "play.fill", focus.paused == nil ? "Pausar" : "Retomar", .white) { focus.togglePause() }
                action("forward.end.fill", focus.phase == .work ? "Pular pra pausa" : "Voltar ao foco", .mint) { focus.skip() }
                action("checkmark", "Concluir", .green) { withAnimation { store.complete(t.id) } }
                action("stop.fill", "Parar", .red) { focus.stop() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TodayPane: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DayTimeline().padding(.horizontal, 6)
            let list = store.overdue + store.today
            if list.isEmpty {
                Text("Nada pra hoje 🎉").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 30)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) { ForEach(list) { TaskRow(task: $0, compact: true) } }
                }
            }
        }
    }
}
