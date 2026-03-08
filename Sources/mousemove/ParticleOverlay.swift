import AppKit
import QuartzCore

@MainActor
final class ParticleOverlay {
    static let shared = ParticleOverlay()
    private var window: NSWindow!
    private var emitter: CAEmitterLayer!
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
        
        setupEmitter()
        
        window.makeKeyAndOrderFront(nil)
    }
    
    private func setupEmitter() {
        emitter = CAEmitterLayer()
        emitter.emitterShape = .point
        emitter.renderMode = .additive
        
        let spark = CAEmitterCell()
        spark.name = "spark"
        spark.birthRate = 0
        spark.lifetime = 0.8
        spark.velocity = 150.0
        spark.velocityRange = 80.0
        spark.yAcceleration = -350.0     // Gravidade puxando pra baixo (eixo Y NSView)
        spark.xAcceleration = 0.0
        spark.emissionRange = 30.0 * (.pi / 180.0) // Cone estreito de 30 graus
        spark.scale = 0.4
        spark.scaleSpeed = -0.4          // Vai afinando até sumir
        spark.alphaSpeed = -1.2          // Esmaece
        spark.color = CGColor(red: 1.0, green: 0.8, blue: 0.5, alpha: 1.0)
        
        // Rasteriza uma faísca suave e esfumaçada (radial gradient) para ser elegante e limpa
        let size = CGSize(width: 8, height: 8)
        let image = NSImage(size: size)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            let colors = [CGColor(gray: 1.0, alpha: 1.0), CGColor(gray: 1.0, alpha: 0.0)] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0.0, 1.0]) {
                ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: 4, y: 4), startRadius: 0, endCenter: CGPoint(x: 4, y: 4), endRadius: 4, options: [])
            }
        }
        image.unlockFocus()
        
        var rect = NSRect(origin: .zero, size: size)
        if let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            spark.contents = cgImage
        }
        
        emitter.emitterCells = [spark]
        emitter.emitterPosition = CGPoint(x: -1000, y: -1000)
        contentView.layer?.addSublayer(emitter)
    }
    
    func moveTo(_ point: CGPoint) {
        let mainHeight = NSScreen.main?.frame.height ?? 1080
        let screenRect = window.frame
        
        // Converte do eixo CG (Top-Left) para eixo NS (Bottom-Left)
        let nsY = mainHeight - point.y
        let nsX = point.x
        
        // Alinha os pontos localmente dentro da view da window fullscreen (suporte a dual-monitor offsets)
        let localPoint = CGPoint(x: nsX - screenRect.minX, y: nsY - screenRect.minY)
        
        emitter.emitterPosition = localPoint
        
        if let last = lastPoint {
            // Calcula o campo vetorial (direção real do movimento para trás)
            let dx = localPoint.x - last.x
            let dy = localPoint.y - last.y
            let dist = sqrt(dx * dx + dy * dy)
            let angle = atan2(dy, dx)
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // Atira as faíscas dinamicamente para TRÁS (+ π radianos) da direção em que o mouse viaja
            emitter.setValue(angle + .pi, forKeyPath: "emitterCells.spark.emissionLongitude")
            // Velocidade das faíscas reage com a velocidade do movimento
            emitter.setValue(min(400.0, 100.0 + dist * 10.0), forKeyPath: "emitterCells.spark.velocity")
            CATransaction.commit()
            
            drawLaserTrail(from: last, to: localPoint)
        }
        lastPoint = localPoint
    }
    
    func resetTrail() {
        lastPoint = nil
        setEmitting(false)
    }
    
    func setEmitting(_ emitting: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        emitter.setValue(emitting ? 500.0 : 0.0, forKeyPath: "emitterCells.spark.birthRate")
        CATransaction.commit()
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
