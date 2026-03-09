import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var mouseMove: MouseMove?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let visualizer = ParticleOverlay.shared
        visualizer.install()
        mouseMove = MouseMove(visualizer: visualizer)
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
