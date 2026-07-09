import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var mouseMove: MouseMove?
    private let idleSleepPreventer = IdleSleepPreventer(reason: "mousemove active")

    func applicationDidFinishLaunching(_ notification: Notification) {
        idleSleepPreventer.start()

        let visualizer = ParticleOverlay.shared
        visualizer.install()
        let mouseMove = MouseMove(visualizer: visualizer)
        self.mouseMove = mouseMove

        Task { @concurrent in
            await mouseMove.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        idleSleepPreventer.stop()
    }
}

@main
struct GhostMouse {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // sem ícone no Dock
        
        let delegate = AppDelegate()
        app.delegate = delegate
        
        app.run() // run loop do AppKit rodando limpidamente na thread principal C-based
    }
}
