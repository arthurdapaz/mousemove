import AppKit
import QuartzCore

@MainActor
final class ParticleOverlay {
    static let shared = ParticleOverlay()
    private var window: NSWindow!
    private var contentView: NSView!
    
    private var lastPoint: CGPoint?
    
    func install() {
        // Envolve todos os monitores para movimentação fluida através de múltiplos displays
        let screenRect = NSScreen.screens.map { $0.frame }.reduce(NSRect.zero) { $0.union($1) }
        
        window = NSWindow(
            contentRect: screenRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        
        contentView = NSView(frame: screenRect)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = contentView
        
        window.makeKeyAndOrderFront(nil)
    }
    
    func moveTo(_ point: CGPoint) {
        let mainHeight = NSScreen.main?.frame.height ?? 1080
        let screenRect = window.frame
        
        // Converte do eixo CG (Top-Left) para eixo NS (Bottom-Left)
        let nsY = mainHeight - point.y
        let nsX = point.x
        
        // Alinha os pontos localmente dentro da view da window fullscreen (suporte a dual-monitor offsets)
        let localPoint = CGPoint(x: nsX - screenRect.minX, y: nsY - screenRect.minY)
        
        if let last = lastPoint {
            drawLaserTrail(from: last, to: localPoint)
        }
        lastPoint = localPoint
    }
    
    func resetTrail() {
        lastPoint = nil
    }
    
    private func drawLaserTrail(from: CGPoint, to: CGPoint) {
        let path = CGMutablePath()
        path.move(to: from)
        path.addLine(to: to)
        
        // Camada 1: Glow Outer (Aura azul difusa)
        let glowLayer = CAShapeLayer()
        glowLayer.path = path
        glowLayer.strokeColor = CGColor(red: 0.1, green: 0.6, blue: 1.0, alpha: 0.6)
        glowLayer.lineWidth = 6.0
        glowLayer.lineCap = .round
        glowLayer.fillColor = nil
        glowLayer.opacity = 1.0
        
        // Efeito Neon Flowing (Outer)
        glowLayer.shadowColor = glowLayer.strokeColor
        glowLayer.shadowRadius = 5.0
        glowLayer.shadowOpacity = 1.0
        glowLayer.shadowOffset = .zero
        
        // Camada 2: Core Inner (Feixe brilhante puro)
        let coreLayer = CAShapeLayer()
        coreLayer.path = path
        coreLayer.strokeColor = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        coreLayer.lineWidth = 1.5
        coreLayer.lineCap = .round
        coreLayer.fillColor = nil
        coreLayer.opacity = 1.0
        
        contentView.layer?.addSublayer(glowLayer)
        contentView.layer?.addSublayer(coreLayer)
        
        // Fade elétrico curtíssimo
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        fade.duration = 0.35
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        
        glowLayer.add(fade, forKey: "fade")
        coreLayer.add(fade, forKey: "fade")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            glowLayer.removeFromSuperlayer()
            coreLayer.removeFromSuperlayer()
        }
    }
}
