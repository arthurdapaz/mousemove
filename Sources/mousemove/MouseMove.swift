import Foundation
import CoreGraphics
import class AppKit.NSScreen
import class AppKit.NSEvent
import Darwin

final class MouseMove {
    private let pid = getpid()
    private let animationQueue = DispatchQueue(label: "mousemove.animation", qos: .userInteractive)
    private let humanFlagQueue = DispatchQueue(label: "mousemove.humanFlag")
    private var humanInterrupted: Bool = false
    private let programmaticFlagQueue = DispatchQueue(label: "mousemove.programmaticFlag")
    private var programmaticPosting: Bool = false
    private var eventTap: CFMachPort?
    private let stateQueue = DispatchQueue(label: "mousemove.state")
    private var isAnimating: Bool = false

    init() {
        startEventTap()

        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard self.isIdle() else { return }
            self.animationQueue.async {
                self.circulate()
            }
        }
    }

    private func setHumanInterrupted(_ v: Bool) {
        humanFlagQueue.sync { humanInterrupted = v }
    }

    private func getHumanInterrupted() -> Bool {
        return humanFlagQueue.sync { humanInterrupted }
    }

    // eventTap is used to temporarily disable our listener while posting events

    private func move(to point: CGPoint) {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        CGEvent(mouseEventSource: nil, mouseType: CGEventType.mouseMoved, mouseCursorPosition: point, mouseButton: CGMouseButton.left)?.post(tap: CGEventTapLocation.cghidEventTap)
        usleep(1_000)
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func click(at point: CGPoint, mouseButton: CGMouseButton = CGMouseButton.left) {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        CGEvent(mouseEventSource: nil, mouseType: CGEventType.leftMouseDown, mouseCursorPosition: point, mouseButton: mouseButton)?.post(tap: CGEventTapLocation.cghidEventTap)
        usleep(useconds_t(Int.random(in: 400_010..<600_200)))
        CGEvent(mouseEventSource: nil, mouseType: CGEventType.leftMouseUp, mouseCursorPosition: point, mouseButton: mouseButton)?.post(tap: CGEventTapLocation.cghidEventTap)
        usleep(1_000)
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func easeMove(from point¹: CGPoint, to point²: CGPoint, easing: Float = 800.0) {
        let distance = point¹.distance(to: point²)
        let steps = Int(distance * CGFloat(easing) / 100) + 1;
        let xDiff = point².x - point¹.x
        let yDiff = point².y - point¹.y
        let stepSize = 1.0 / Double(steps)

        for i in 0...steps {
            if getHumanInterrupted() { return }
            let factor = (CGFloat(stepSize) * CGFloat(i)).cubicEaseOut
            let stepPoint = CGPoint(
                x: point¹.x + (factor * xDiff),
                y: point¹.y + (factor * yDiff)
            )
            move(to: stepPoint)
            usleep(useconds_t(Int.random(in: 200..<300)))
        }
    }

    private func isIdle() -> Bool {
        let null = CGEventType(rawValue: ~0)!
        let lastEvent: CFTimeInterval = CGEventSource.secondsSinceLastEventType(CGEventSourceStateID.hidSystemState, eventType: null)
        print("Idle for", lastEvent)
        return lastEvent > 5
    }

    private func startEventTap() {
        let mask = CGEventMask(UInt64(1) << UInt64(CGEventType.mouseMoved.rawValue))

        let ref = Unmanaged.passUnretained(self).toOpaque()

        guard let createdTap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                                 place: .headInsertEventTap,
                                                 options: .listenOnly,
                                                 eventsOfInterest: mask,
                                                 callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
            guard type == .mouseMoved else { return Unmanaged.passUnretained(event) }
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }

            let me = Unmanaged<MouseMove>.fromOpaque(refcon).takeUnretainedValue()
            // If this callback is reached, it's a real (non-disabled) mouse move — treat as human
            me.setHumanInterrupted(true)

            return Unmanaged.passUnretained(event)
        }, userInfo: ref) else {
            print("Failed to create event tap")
            return
        }
        self.eventTap = createdTap

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, createdTap, 0)

        DispatchQueue.global(qos: .background).async {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: createdTap, enable: true)
            CFRunLoopRun()
        }
    }

    func circulate() {
        // ensure only one animation at a time (use separate state queue to avoid deadlock)
        if stateQueue.sync(execute: { isAnimating }) { return }
        stateQueue.sync { isAnimating = true }
        defer { stateQueue.sync { isAnimating = false } }

        setHumanInterrupted(false)

        guard NSScreen.main != nil else { fatalError("Most run on a screen session") }
        // Usa a posição do mouse em coordenadas de tela (origem canto inferior esquerdo)
        let initialPoint = NSEvent.mouseLocation

        let radius: Double = 50
        let steps = 60
        let twoPi = Double.pi * 2
        let angleStep = twoPi / Double(steps)

        var lastDestination: CGPoint = initialPoint

        for i in 0...steps {
            if getHumanInterrupted() { print("Human interrupted animation — aborting") ; return }

            let angle = Double(i) * angleStep
            let x = radius * cos(angle) + initialPoint.x
            let y = radius * sin(angle) + initialPoint.y
            let destination = CGPoint(x: x, y: y)

            if i == 0 {
                easeMove(from: initialPoint, to: destination)
            } else {
                move(to: destination)
            }

            usleep(useconds_t(30_000))
            lastDestination = destination
        }

        if getHumanInterrupted() { print("Human interrupted before return-to-origin") ; return }

        // Garante que o mouse retorna exatamente ao ponto inicial
        easeMove(from: lastDestination, to: initialPoint)
    }
}
