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
    private let stateQueue = DispatchQueue(label: "mousemove.state")
    private var isAnimating: Bool = false
    
    // Custom tag for our synthetic events
    private let syntheticEventTag: Int64 = 0xDEADBEEF


    init(animation: AnimationType = .natural) {
        self.animationType = animation
        startEventTap()

        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard self.isIdle() else { return }
            self.animationQueue.async {
                self.circulate()
            }
        }
    }

    enum AnimationType: String {
        case circle
        case square
        case triangle
        case zigzag
        case sine
        case natural

        static func from(_ s: String) -> AnimationType {
            return AnimationType(rawValue: s.lowercased()) ?? .natural
        }
    }

    private var animationType: AnimationType

    private func pointsForCurrentAnimation(initialPoint: CGPoint, radius: Double = 50, steps: Int = 60) -> [CGPoint] {
        switch animationType {
        case .circle:
            let twoPi = Double.pi * 2
            let angleStep = twoPi / Double(steps)
            return (0...steps).map { i in
                let angle = Double(i) * angleStep
                return CGPoint(x: radius * cos(angle) + initialPoint.x,
                               y: radius * sin(angle) + initialPoint.y)
            }
        case .square:
            let side = radius * 2
            let perSide = max(1, steps / 4)
            var pts: [CGPoint] = []
            let half = side / 2
            let topLeft = CGPoint(x: initialPoint.x - CGFloat(half), y: initialPoint.y + CGFloat(half))
            let topRight = CGPoint(x: initialPoint.x + CGFloat(half), y: initialPoint.y + CGFloat(half))
            let bottomRight = CGPoint(x: initialPoint.x + CGFloat(half), y: initialPoint.y - CGFloat(half))
            let bottomLeft = CGPoint(x: initialPoint.x - CGFloat(half), y: initialPoint.y - CGFloat(half))
            let corners = [topLeft, topRight, bottomRight, bottomLeft, topLeft]
            for edge in 0..<(corners.count - 1) {
                let a = corners[edge]
                let b = corners[edge + 1]
                for i in 0...perSide {
                    let t = CGFloat(i) / CGFloat(perSide)
                    let x = a.x + (b.x - a.x) * t
                    let y = a.y + (b.y - a.y) * t
                    pts.append(CGPoint(x: x, y: y))
                }
            }
            return pts
        case .triangle:
            let twoPi = Double.pi * 2
            // vertices of equilateral triangle
            let angles = [ -Double.pi/2, -Double.pi/2 + (twoPi/3), -Double.pi/2 + (2*twoPi/3) ]
            let verts = angles.map { angle in
                CGPoint(x: initialPoint.x + CGFloat(radius * cos(angle)), y: initialPoint.y + CGFloat(radius * sin(angle)))
            }
            var pts: [CGPoint] = []
            let perSide = max(1, steps / 3)
            let corners = [verts[0], verts[1], verts[2], verts[0]]
            for edge in 0..<(corners.count - 1) {
                let a = corners[edge]
                let b = corners[edge + 1]
                for i in 0...perSide {
                    let t = CGFloat(i) / CGFloat(perSide)
                    pts.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                }
            }
            return pts
        case .zigzag:
            // create alternating corner points then interpolate between them
            var cornerPts: [CGPoint] = []
            let segments = max(2, steps / 6)
            let width = radius * 4
            let dx = width / Double(segments)
            for i in 0...segments {
                let x = initialPoint.x - CGFloat(width/2) + CGFloat(Double(i) * dx)
                let yOffset = (i % 2 == 0) ? radius : -radius
                let y = initialPoint.y + CGFloat(yOffset)
                cornerPts.append(CGPoint(x: x, y: y))
            }

            // interpolate each edge to create a continuous path
            var pts: [CGPoint] = []
            let perEdge = max(4, steps / max(1, segments))
            for edge in 0..<(cornerPts.count - 1) {
                let a = cornerPts[edge]
                let b = cornerPts[edge + 1]
                for j in 0...perEdge {
                    let t = CGFloat(j) / CGFloat(perEdge)
                    let x = a.x + (b.x - a.x) * t
                    let y = a.y + (b.y - a.y) * t
                    pts.append(CGPoint(x: x, y: y))
                }
            }
            return pts
        case .sine:
            var pts: [CGPoint] = []
            let length = radius * 6
            let samples = steps
            for i in 0...samples {
                let t = Double(i) / Double(samples)
                let x = initialPoint.x - CGFloat(length/2) + CGFloat(t * length)
                let y = initialPoint.y + CGFloat(sin(t * Double.pi * 2) * (radius / 1.5))
                pts.append(CGPoint(x: x, y: y))
            }
            return pts
        case .natural:
            var pts: [CGPoint] = []
            let timeFactor = Double.random(in: 1.0...2.0)
            let phaseX1 = Double.random(in: 0...(2 * .pi))
            let phaseX2 = Double.random(in: 0...(2 * .pi))
            let phaseY1 = Double.random(in: 0...(2 * .pi))
            let phaseY2 = Double.random(in: 0...(2 * .pi))
            
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let envelope = sin(t * .pi) // smooth start and end
                
                let dx = (sin(t * .pi * 2 * timeFactor + phaseX1) * radius + sin(t * .pi * 4 * timeFactor + phaseX2) * (radius * 0.4)) * envelope
                let dy = (cos(t * .pi * 2 * timeFactor + phaseY1) * radius + cos(t * .pi * 3 * timeFactor + phaseY2) * (radius * 0.4)) * envelope
                
                pts.append(CGPoint(x: initialPoint.x + CGFloat(dx),
                                   y: initialPoint.y + CGFloat(dy)))
            }
            return pts
        }
    }

    private func setHumanInterrupted(_ v: Bool) {
        humanFlagQueue.sync { humanInterrupted = v }
    }

    private func getHumanInterrupted() -> Bool {
        return humanFlagQueue.sync { humanInterrupted }
    }

    // eventTap is used to listen for real human movements
    
    private func move(to point: CGPoint) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
        event.post(tap: .cghidEventTap)
        usleep(1_000)
    }

    // Click function has been explicitly removed to prohibit synthetic mouse clicks per constraints.

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
        // Safe check using UInt32.max for any input source instead of unsafe ~0 cast
        let anyInputType = CGEventType(rawValue: UInt32.max)!
        let lastEvent: CFTimeInterval = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInputType)
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
            
            // If the event lacks our custom synthetic tag, it's a real human interaction.
            if event.getIntegerValueField(.eventSourceUserData) != me.syntheticEventTag {
                me.setHumanInterrupted(true)
            }

            return Unmanaged.passUnretained(event)
        }, userInfo: ref) else {
            print("Failed to create event tap")
            return
        }

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
        // Use Quartz/CoreGraphics coordinates directly which is native for CGEvent posting (top-left origin).
        let initialPoint = CGEvent(source: nil)?.location ?? .zero

        let radius: Double = (animationType == .natural) ? Double.random(in: 50...250) : 50
        let steps = (animationType == .natural) ? Int.random(in: 60...180) : 60

        let points = pointsForCurrentAnimation(initialPoint: initialPoint, radius: radius, steps: steps)
        var lastDestination = initialPoint

        for (i, destination) in points.enumerated() {
            if getHumanInterrupted() { print("Human interrupted animation — aborting") ; return }

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
