import Cocoa
import WebKit
import UniformTypeIdentifiers

/// Transparent layer over the web view. In finger-tracking mode it catches the trackpad's
/// raw touches (absolute finger positions) and swallows clicks so taps don't hit the toolbar.
final class TouchOverlay: NSView {
    var enabled = false {
        didSet { allowedTouchTypes = enabled ? [.indirect] : [] }
    }
    var onBegin: ((CGPoint, CGFloat) -> Void)?
    var onMove: ((CGPoint) -> Void)?
    var onEnd: (() -> Void)?
    var onCancel: (() -> Void)?
    var onScroll: ((CGFloat, CGFloat) -> Void)?
    var onMagnify: ((CGFloat) -> Void)?
    private var activeID: (NSCopying & NSObjectProtocol)?
    private var multi = false   // two or more fingers down: scrolling/pinching, not writing

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsRestingTouches = false   // ignore a resting thumb or palm
        allowedTouchTypes = []
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { enabled ? super.hitTest(point) : nil }
    override var acceptsFirstResponder: Bool { false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {
        guard enabled else { return }
        let k: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        onScroll?(-event.scrollingDeltaX * k, -event.scrollingDeltaY * k)
    }
    override func magnify(with event: NSEvent) {
        guard enabled else { return }
        onMagnify?(event.magnification)
    }
    override func smartMagnify(with event: NSEvent) {}

    private func find(_ phase: NSTouch.Phase, _ event: NSEvent) -> NSTouch? {
        guard let id = activeID else { return nil }
        return event.touches(matching: phase, in: self).first { $0.identity.isEqual(id) }
    }

    private func clearMultiIfLifted(_ event: NSEvent) {
        if event.touches(matching: .touching, in: self).isEmpty { multi = false }
    }

    override func touchesBegan(with event: NSEvent) {
        guard enabled else { return }
        if event.touches(matching: .touching, in: self).count > 1 {
            multi = true
            if activeID != nil { activeID = nil; onCancel?() }
            return
        }
        guard !multi, activeID == nil,
              let t = event.touches(matching: .began, in: self).first else { return }
        activeID = t.identity
        let size = t.deviceSize
        onBegin?(t.normalizedPosition, size.height > 0 ? size.width / size.height : 1.6)
    }
    override func touchesMoved(with event: NSEvent) {
        guard enabled, let t = find(.moved, event) else { return }
        onMove?(t.normalizedPosition)
    }
    override func touchesEnded(with event: NSEvent) {
        defer { clearMultiIfLifted(event) }
        guard find(.ended, event) != nil else { return }
        activeID = nil
        onEnd?()
    }
    override func touchesCancelled(with event: NSEvent) {
        defer { clearMultiIfLifted(event) }
        guard find(.cancelled, event) != nil else { return }
        activeID = nil
        onEnd?()
    }
    func reset() { multi = false; if activeID != nil { activeID = nil; onEnd?() } }
}

/// Web view that turns trackpad pinches into board zoom instead of page zoom.
final class BoardWebView: WKWebView {
    var onMagnify: ((CGFloat, NSPoint) -> Void)?
    override func magnify(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        onMagnify?(event.magnification, NSPoint(x: p.x, y: isFlipped ? p.y : bounds.height - p.y))
    }
    override func smartMagnify(with event: NSEvent) {}
}

/// Window that stays silent when a key press isn't handled by anything (no system beep).
final class QuietWindow: NSWindow {
    override func noResponder(for eventSelector: Selector) {
        if eventSelector == #selector(NSResponder.keyDown(with:)) { return }
        super.noResponder(for: eventSelector)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate, WKNavigationDelegate, WKDownloadDelegate, WKScriptMessageHandler {
    var window: NSWindow!
    var webView: WKWebView!
    var overlay: TouchOverlay!
    var cursorHidden = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()   // keeps the saved drawing between launches
        config.userContentController.add(self, name: "tablet")

        let board = BoardWebView(frame: .zero, configuration: config)
        board.onMagnify = { [weak self] m, p in
            self?.js(String(format: "__view.zoomAt(%.5f,%.1f,%.1f)", 1 + m, p.x, p.y))
        }
        webView = board
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]

        overlay = TouchOverlay(frame: .zero)
        overlay.autoresizingMask = [.width, .height]
        overlay.onBegin = { [weak self] p, aspect in
            self?.js(String(format: "__tablet.begin(%.5f,%.5f,%.4f)", p.x, p.y, aspect))
        }
        overlay.onMove = { [weak self] p in
            self?.js(String(format: "__tablet.move(%.5f,%.5f)", p.x, p.y))
        }
        overlay.onEnd = { [weak self] in self?.js("__tablet.end()") }
        overlay.onCancel = { [weak self] in self?.js("__tablet.cancel()") }
        overlay.onScroll = { [weak self] dx, dy in
            self?.js(String(format: "__view.panBy(%.2f,%.2f)", dx, dy))
        }
        overlay.onMagnify = { [weak self] m in
            self?.js(String(format: "__view.zoomAt(%.5f,-1,-1)", 1 + m))
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.setTablet(false)
        }

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: screen.width * 0.85, height: screen.height * 0.85)
        window = QuietWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Whiteboard"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 640, height: 420)
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        webView.frame = container.bounds
        overlay.frame = container.bounds
        container.addSubview(webView)
        container.addSubview(overlay)
        window.contentView = container
        window.makeFirstResponder(webView)
        window.center()
        window.setFrameAutosaveName("WhiteboardMain")
        window.makeKeyAndOrderFront(nil)

        if let html = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { setTablet(false) }

    // MARK: Finger tracking
    func js(_ code: String) { webView.evaluateJavaScript(code, completionHandler: nil) }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "tablet", let on = message.body as? Bool { setTablet(on) }
    }

    func setTablet(_ on: Bool) {
        guard overlay != nil, overlay.enabled != on else { return }
        if on {
            // Park the pointer in the middle of the window and freeze it, so sliding a finger
            // no longer moves it. Touches then go to the overlay.
            let f = window.frame
            let primaryH = NSScreen.screens.first?.frame.height ?? f.maxY
            CGWarpMouseCursorPosition(CGPoint(x: f.midX, y: primaryH - f.midY))
            CGAssociateMouseAndMouseCursorPosition(0)
            if !cursorHidden { NSCursor.hide(); cursorHidden = true }
            overlay.enabled = true
        } else {
            overlay.reset()
            overlay.enabled = false
            CGAssociateMouseAndMouseCursorPosition(1)
            if cursorHidden { NSCursor.unhide(); cursorHidden = false }
        }
        window.makeFirstResponder(webView)
        js("window.__tablet && __tablet.setMode(\(on))")
    }

    // MARK: Menu (gives ⌘Q, ⌘W, full screen, etc.)
    func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Whiteboard", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Whiteboard", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Whiteboard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let winItem = NSMenuItem(); main.addItem(winItem)
        let winMenu = NSMenu(title: "Window")
        winMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fs = winMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fs.keyEquivalentModifierMask = [.command, .control]
        winItem.submenu = winMenu
        NSApp.windowsMenu = winMenu

        NSApp.mainMenu = main
    }

    // MARK: JavaScript dialogs (used by "Clear the whole board?")
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }

    // MARK: Downloads (Save as PNG)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename
        panel.allowedContentTypes = [.png]
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.beginSheetModal(for: window) { result in
            guard result == .OK, let url = panel.url else { return completionHandler(nil) }
            try? FileManager.default.removeItem(at: url)
            completionHandler(url)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
