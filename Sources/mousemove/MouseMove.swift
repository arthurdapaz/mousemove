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

    // eventTap is used to listen for real human movements
    
    private func move(to point: CGPoint) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
        event.post(tap: .cghidEventTap)
        usleep(1_000)
    }

    // Click function has been explicitly removed to prohibit synthetic mouse clicks per constraints.



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
        // ensure only one animation at a time
        if stateQueue.sync(execute: { isAnimating }) { return }
        stateQueue.sync { isAnimating = true }
        defer { stateQueue.sync { isAnimating = false } }

        setHumanInterrupted(false)

        let displayBounds = CGDisplayBounds(CGMainDisplayID())
        let padding: CGFloat = 80.0
        
        // Define safe area bounds
        let safeMinX = displayBounds.minX + padding
        let safeMaxX = displayBounds.maxX - padding
        let safeMinY = displayBounds.minY + padding
        let safeMaxY = displayBounds.maxY - padding
        
        var currentPoint = CGEvent(source: nil)?.location ?? CGPoint(x: safeMaxX / 2, y: safeMaxY / 2)
        // Clamp bounds securely
        currentPoint.x = max(safeMinX, min(safeMaxX, currentPoint.x))
        currentPoint.y = max(safeMinY, min(safeMaxY, currentPoint.y))

        while !getHumanInterrupted() {
            // Pick a random target within safe bounds
            let targetX = CGFloat.random(in: safeMinX...safeMaxX)
            let targetY = CGFloat.random(in: safeMinY...safeMaxY)
            let targetPoint = CGPoint(x: targetX, y: targetY)
            
            // Generate some random bezier control points to add sweeping human curvature
            let controlPoint1 = CGPoint(
                x: currentPoint.x + CGFloat.random(in: -400...400),
                y: currentPoint.y + CGFloat.random(in: -400...400)
            )
            let controlPoint2 = CGPoint(
                x: targetPoint.x + CGFloat.random(in: -400...400),
                y: targetPoint.y + CGFloat.random(in: -400...400)
            )

            let distance = currentPoint.distance(to: targetPoint)
            let baseSteps = Int(max(100, distance / 3)) // Variable resolution scaling
            let steps = Int.random(in: baseSteps...(baseSteps + 100))
            
            for i in 0...steps {
                if getHumanInterrupted() { print("Human interrupted animation — aborting"); return }
                
                let t = CGFloat(i) / CGFloat(steps)
                
                // Cubic Bezier interpolation mathematical model
                let invT = 1.0 - t
                let term1 = invT * invT * invT
                let term2 = 3.0 * invT * invT * t
                let term3 = 3.0 * invT * t * t
                let term4 = t * t * t
                
                var stepPoint = CGPoint(
                    x: term1 * currentPoint.x + term2 * controlPoint1.x + term3 * controlPoint2.x + term4 * targetPoint.x,
                    y: term1 * currentPoint.y + term2 * controlPoint1.y + term3 * controlPoint2.y + term4 * targetPoint.y
                )
                
                // Hard-clamp the calculation within bounds to satisfy the 80px rule
                stepPoint.x = max(safeMinX, min(safeMaxX, stepPoint.x))
                stepPoint.y = max(safeMinY, min(safeMaxY, stepPoint.y))
                
                move(to: stepPoint)
                
                // Dynamic organic speed (slower at anchor ends, fast swoosh in middle vector)
                let speedMod = 1.0 - (sin(t * .pi) * 0.8)
                let baseSleep = Float.random(in: 1_500...4_000)
                usleep(useconds_t(baseSleep * Float(speedMod)))
            }
            
            currentPoint = targetPoint
            usleep(useconds_t(Int.random(in: 200_000...1_500_000))) // Pause naturally before picking a new place to rest
        }
    }
}
