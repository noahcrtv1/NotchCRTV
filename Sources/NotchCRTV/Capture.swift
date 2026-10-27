import AppKit
import SwiftUI
import NotchCore

/// Campo estilo Spotlight. Enter cria, ⌘Enter cria e mantém aberto, Esc fecha.
@MainActor
final class CaptureController {
    static let shared = CaptureController()
    private var panel: NotchPanel?
    let model = CaptureModel()

    func show(prefill: String = "", attachments: [String] = []) {
        if panel == nil { build() }
        model.text = prefill
        model.attachments = attachments
        // abre na tela onde está o mouse
        let mouse = NSEvent.mouseLocation
        guard let panel, let sc = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let size = CGSize(width: 660, height: 168)
        panel.setFrame(NSRect(x: sc.frame.midX - size.width / 2, y: sc.frame.maxY - sc.frame.height * 0.28 - size.height,
                              width: size.width, height: size.height), display: true)
        // não ativa o app (senão o macOS sai do Space em tela cheia): painel não-ativador vira key sozinho, estilo Spotlight
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        // foco no campo só depois que o painel virou key (senão o texto digitado se perde)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.model.focusToken += 1 }
    }

    func close() {
        model.voice.stop()
        panel?.orderOut(nil)
    }

    private func build() {
        let p = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        p.level = .statusBar + 2
        p.isFloatingPanel = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        p.becomesKeyOnlyIfNeeded = false
        p.hidesOnDeactivate = false
        p.contentView = NSHostingView(rootView: CaptureView(model: model).environmentObject(Store.shared))
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: p, queue: .main) { _ in
            MainActor.assumeIsolated { CaptureController.shared.close() }
        }
        panel = p
    }
}

@MainActor
final class CaptureModel: ObservableObject {
    @Published var text = ""
    @Published var attachments: [String] = []
    @Published var focusToken = 0
    @Published var added: String?
    let voice = Voice()
}

struct CaptureView: View {
    @ObservedObject var model: CaptureModel
    @ObservedObject var voice: Voice
    @EnvironmentObject var store: Store
    @FocusState private var focused: Bool

    init(model: CaptureModel) { self.model = model; self.voice = model.voice }

    var parsed: ParsedTask { TaskParser.parse(model.text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(Color.accentColor)
                TextField("Nova demanda… ex: editar vídeo amanhã 15h #crtv !", text: $model.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .medium))
                    .focused($focused)
                    .onSubmit { submit(keepOpen: NSEvent.modifierFlags.contains(.command)) }
                Button { voice.toggle() } label: {
                    Image(systemName: voice.listening ? "waveform.circle.fill" : "mic.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(voice.listening ? .red : .secondary)
                        .symbolEffect(.pulse, isActive: voice.listening)
                }
                .buttonStyle(.plain).help("Ditar (PT-BR)")
            }
            preview
            Spacer(minLength: 0)
            Divider().opacity(0.5)
            HStack {
                if let e = voice.error { Text(e).foregroundStyle(.red) }
                else if let a = model.added { Label("Adicionada: \(a)", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                else { Text("amanhã · sexta · 15h · em 30 min · 15/11 · toda segunda · #tag · ! · ~1h").foregroundStyle(.secondary) }
                Spacer()
                Text("↩ criar · ⌘↩ continuar · esc").foregroundStyle(.secondary)
            }
            .font(.system(size: 11)).lineLimit(1)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .onExitCommand { CaptureController.shared.close() }
        .onChange(of: model.focusToken) { focused = true; model.added = nil }
        .onAppear {
            focused = true
            model.voice.onText = { [weak model] t in model?.text = t }
        }
    }

    @ViewBuilder var preview: some View {
        let p = parsed
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if model.text.isEmpty && model.attachments.isEmpty {
                    Chip(text: "digite ou fale", color: .secondary, icon: "sparkles")
                } else {
                    Chip(text: p.title.isEmpty ? "sem título" : p.title, color: .primary, icon: "text.cursor")
                    if p.due != nil {
                        Chip(text: Fmt.when(p.makeTask()),color: .accentColor, icon: p.hasTime ? "clock" : "calendar")
                    } else {
                        Chip(text: "sem horário", color: .secondary, icon: "tray")
                    }
                    if let r = p.recurrence { Chip(text: r.label, color: .teal, icon: "repeat") }
                    if p.priority > 0 { Chip(text: p.priority == 1 ? "alta" : "crítica", color: .orange, icon: "exclamationmark") }
                    if p.persistent { Chip(text: "insistente", color: .red, icon: "bell.badge") }
                    if let e = p.estimateMinutes { Chip(text: Fmt.dur(e), color: .indigo, icon: "hourglass") }
                    ForEach(p.tags, id: \.self) { Chip(text: "#" + $0, color: tagColor($0)) }
                    if p.tags.isEmpty, let ctx = store.contextTag { Chip(text: "#\(ctx) (app atual)", color: tagColor(ctx).opacity(0.7)) }
                    ForEach(model.attachments, id: \.self) { Chip(text: display($0), color: .brown, icon: "paperclip") }
                }
            }
        }
    }

    func submit(keepOpen: Bool) {
        voice.stop()
        guard let t = store.quickAdd(model.text, attachments: model.attachments) else { return }
        Prefs.playSound("Pop")
        NotchController.shared.flash()
        model.text = ""; model.attachments = []
        if keepOpen { model.added = t.title } else { CaptureController.shared.close() }
    }
}
