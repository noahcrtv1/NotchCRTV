import AppKit
import SwiftUI
import NotchCore

@main
struct NotchCRTVApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @AppStorage(Prefs.Key.showMenuBar) var showMenuBar = true

    init() { Prefs.registerDefaults() }

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarContent().environmentObject(Store.shared).environmentObject(Focus.shared)
        } label: {
            MenuBarLabel().environmentObject(Store.shared).environmentObject(Focus.shared)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!
    private var windows: [String: NSWindow] = [:]
    private(set) var lastOtherApp: String?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        _ = Store.shared
        Notifier.shared.start()

        Hotkey.shared.action = { MainActor.assumeIsolated { AppDelegate.shared.toggleCapture() } }
        applyPrefs()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppDelegate.shared.applyPrefs() }
        }

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { AppDelegate.shared.frontAppChanged(app) }
        }
        frontAppChanged(NSWorkspace.shared.frontmostApplication)
        showMain()

        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    private var lastHotkey = -1
    private var lastNotch: Bool?
    private var lastOverlay: Bool?

    func applyPrefs() {
        let d = Prefs.d
        TaskParser.defaultHour = Prefs.deadlineHour
        let hk = d.integer(forKey: Prefs.Key.hotkey)
        if hk != lastHotkey { lastHotkey = hk; Hotkey.shared.register(index: hk) }
        let notch = d.bool(forKey: Prefs.Key.showNotch)
        if notch != lastNotch { lastNotch = notch; notch ? NotchController.shared.show() : NotchController.shared.hide() }
        let overlay = d.bool(forKey: Prefs.Key.showOverlay)
        NotchController.shared.layout()
        if overlay != lastOverlay { lastOverlay = overlay; OverlayController.shared.setEnabled(overlay) }
    }

    /// App em primeiro plano define a tag de contexto (ex.: Premiere → #edição).
    func frontAppChanged(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let name = app.localizedName ?? ""
        lastOtherApp = name
        let tag = Prefs.appTags.first { name.localizedCaseInsensitiveContains($0.key) }?.value
        Store.shared.contextTag = tag
        Store.shared.contextApp = tag == nil ? nil : name
        OverlayController.shared.refresh()
    }

    // MARK: - Janelas

    func toggleCapture() { capture() }

    func capture(prefill: String = "", attachments: [String] = []) {
        CaptureController.shared.show(prefill: prefill, attachments: attachments)
    }

    func edit(_ id: UUID) {
        guard let t = Store.shared.task(id) else { return }
        let key = "edit-\(id)"
        let close: () -> Void = { [weak self] in self?.windows[key]?.close() }
        present(key, title: "Editar demanda", EditorView(task: t, close: close))
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMain(); return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func showMain() {
        if let w = windows["main"] {
            NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil); return
        }
        let host = NSHostingController(rootView: MainView().environmentObject(Store.shared).environmentObject(Focus.shared))
        let w = NSWindow(contentViewController: host)
        w.title = "NotchCRTV"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        w.toolbarStyle = .unified
        w.isReleasedWhenClosed = false
        w.setContentSize(NSSize(width: 980, height: 640))
        w.setFrameAutosaveName("NotchCRTVMain")
        if !w.setFrameUsingName("NotchCRTVMain") { w.center() }
        windows["main"] = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func showSettings() { present("settings", title: "Ajustes do NotchCRTV", SettingsView()) }
    func showReview() { present("review", title: "Revisão do dia", ReviewView()) }

    private func present<V: View>(_ key: String, title: String, _ view: V) {
        if let w = windows[key], w.isVisible {
            NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil); return
        }
        let host = NSHostingController(rootView: view.environmentObject(Store.shared).environmentObject(Focus.shared))
        let w = NSWindow(contentViewController: host)
        w.title = title
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.center()
        windows[key] = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    // MARK: - Serviços (texto selecionado em qualquer app)

    @objc func createTask(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = (pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: false]) as? [URL]) ?? []
        let text = pboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = urls.map { $0.isFileURL ? $0.path : $0.absoluteString }
        let prefill = text.map { String($0.prefix(140)).replacingOccurrences(of: "\n", with: " ") } ?? attachments.first.map(display) ?? ""
        capture(prefill: prefill, attachments: text?.hasPrefix("http") == true ? [text!] : attachments)
    }
}
