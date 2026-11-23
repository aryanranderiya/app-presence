import AppKit
import SwiftUI

final class SettingsWindowController {
    private var window: NSWindow?
    private var model: SettingsModel?

    func show(onChange: @escaping () -> Void) {
        if let model {
            model.onChange = onChange
        } else {
            let model = SettingsModel()
            model.onChange = onChange
            let controller = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: controller)
            window.title = "AppPresence"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.collectionBehavior = [.moveToActiveSpace]
            self.model = model
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        placeWindow()
    }

    private func placeWindow() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.screens.first { $0.frame.origin == .zero }
            ?? NSScreen.main

        guard let screen else {
            window.center()
            return
        }

        let visible = screen.visibleFrame
        let size = window.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        window.makeKey()
        log("settings frame \(Int(origin.x)),\(Int(origin.y)) on \(Int(screen.frame.width))x\(Int(screen.frame.height))")
    }
}
