import Foundation
@preconcurrency import CoreFoundation
import CoreGraphics
import class AppKit.NSScreen
import class AppKit.NSEvent
import Darwin

actor MouseMove {
    private var hasPhysicalInterruptOccurred: Bool = false
    private var isAnimating: Bool = false
    
    // Custom tag for our synthetic events
    private let syntheticEventSignatureTag: Int64 = 0xDEADBEEF

    init() {
        startListeningForPhysicalHumanIntervention()

        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
                guard self.hasSystemBeenIdle() else { continue }
                await self.beginInfiniteNaturalWandering()
            }
        }
    }

    func setPhysicalInterruptOccurred(_ didOccur: Bool) {
        hasPhysicalInterruptOccurred = didOccur
    }

    func checkIfPhysicalInterruptOccurred() -> Bool {
        return hasPhysicalInterruptOccurred
    }

    // eventTap is used to listen for real human movements
    private func postSyntheticMoveEvent(to point: CGPoint) async {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: syntheticEventSignatureTag)
        event.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 1_000_000) // 1ms naturally yielding sleep
    }

    // Check if system has been idle for more than 5 seconds
    nonisolated private func hasSystemBeenIdle() -> Bool {
        // Safe check using UInt32.max for any input source instead of unsafe ~0 cast
        let anyInputType = CGEventType(rawValue: UInt32.max)!
        let lastEvent: CFTimeInterval = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInputType)
        return lastEvent > 5
    }

    nonisolated private func startListeningForPhysicalHumanIntervention() {
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
            if event.getIntegerValueField(.eventSourceUserData) != me.syntheticEventSignatureTag {
                Task {
                    await me.setPhysicalInterruptOccurred(true)
                }
            }

            return Unmanaged.passUnretained(event)
        }, userInfo: ref) else {
            print("Failed to create event tap")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, createdTap, 0)

        // Run the event tap run-loop on a dedicated background thread to prevent blocking
        Thread.detachNewThread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: createdTap, enable: true)
            CFRunLoopRun()
        }
    }

    func beginInfiniteNaturalWandering() async {
        // ensure only one animation at a time
        if isAnimating { return }
        isAnimating = true
        defer { isAnimating = false }

        setPhysicalInterruptOccurred(false)

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

        print("iniciando movimento ad-infinitum...")

        while !checkIfPhysicalInterruptOccurred() {
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
                if checkIfPhysicalInterruptOccurred() { break }
                
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
                
                await postSyntheticMoveEvent(to: stepPoint)
                
                // Dynamic organic speed (slower at anchor ends, fast swoosh in middle vector)
                let speedMod = 1.0 - (sin(t * .pi) * 0.8)
                let baseSleep = Float.random(in: 1_500...4_000)
                try? await Task.sleep(nanoseconds: UInt64(baseSleep * Float(speedMod) * 1_000))
            }
            
            if checkIfPhysicalInterruptOccurred() { break }
            
            currentPoint = targetPoint
            try? await Task.sleep(nanoseconds: UInt64(Int.random(in: 200_000_000...1_500_000_000))) // Pause naturally before picking a new place to rest
        }
        
        print("intervenção humana detectada, controle retomado.")
    }
}
