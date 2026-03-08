@preconcurrency import CoreFoundation
import class AppKit.NSEvent
import class AppKit.NSScreen
import CoreGraphics
import Darwin
import Foundation

actor MouseMove {
    private var hasPhysicalInterruptOccurred = false
    private var activeWanderingTask: Task<Void, Never>?
    private var eventTap: CFMachPort?
    private let syntheticTag: Int64 = 0xDEADBEEF

    // Stream como ponte thread-safe entre callback C e actor
    private let interruptStream: AsyncStream<Void>
    private let interruptContinuation: AsyncStream<Void>.Continuation

    init() {
        (interruptStream, interruptContinuation) = AsyncStream<Void>.makeStream()
        
        // Iniciar escuta e loop principal como tasks estruturadas
        Task { await self.listenForInterrupts() }
        Task { await self.mainLoop() }
        
        installEventTap()
    }

    deinit {
        activeWanderingTask?.cancel()
        interruptContinuation.finish()
    }

    private func listenForInterrupts() async {
        for await _ in interruptStream {
            hasPhysicalInterruptOccurred = true
        }
    }

    private func mainLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            guard hasSystemBeenIdle() else { continue }
            beginWandering()
        }
    }

    private func beginWandering() {
        guard activeWanderingTask == nil else { return }
        activeWanderingTask = Task {
            defer {
                Task { [weak self] in await self?.clearWanderingTask() }
            }
            await self.beginInfiniteNaturalWandering()
        }
    }

    private func clearWanderingTask() {
        activeWanderingTask = nil
    }

    private func setPhysicalInterruptOccurred(_ didOccur: Bool) {
        hasPhysicalInterruptOccurred = didOccur
    }

    private func checkIfPhysicalInterruptOccurred() -> Bool {
        return hasPhysicalInterruptOccurred
    }

    // eventTap is used to listen for real human movements
    private func postSyntheticMoveEvent(to point: CGPoint) async {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
        event.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 1_000_000) // 1ms naturally yielding sleep
    }

    // Check if system has been idle for more than 5 seconds
    nonisolated private func hasSystemBeenIdle() -> Bool {
        guard let anyInputType = CGEventType(rawValue: UInt32.max) else { return false }
        let lastEvent: CFTimeInterval = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInputType)
        return lastEvent > 5
    }

    nonisolated private func installEventTap() {
        let mask = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
        // passRetained para garantir lifetime correto
        let ref = Unmanaged.passRetained(self).toOpaque()
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard type == .mouseMoved, let refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let me = Unmanaged<MouseMove>.fromOpaque(refcon).takeUnretainedValue()
                if event.getIntegerValueField(.eventSourceUserData) != me.syntheticTag {
                    me.interruptContinuation.yield()  // thread-safe, sem Task overhead
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: ref
        ) else {
            print("Failed to create event tap")
            return
        }

        Task { await self.setEventTap(tap) }
        
        // Pass the pointer safely to the Sendable closure by wrapping it via an integer cast
        let refInt = Int(bitPattern: ref)
        
        Thread.detachNewThread {
            let safeRef = UnsafeMutableRawPointer(bitPattern: refInt)
            
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
            
            // Ao sair do RunLoop, liberar a retenção (safeRef garante a ponte Sendable)
            if let safeRef = safeRef {
                Unmanaged<MouseMove>.fromOpaque(safeRef).release()
            }
        }
    }
    
    private func setEventTap(_ tap: CFMachPort) {
        self.eventTap = tap
    }

    private func beginInfiniteNaturalWandering() async {

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
        
        await ParticleOverlay.shared.resetTrail()

        while !checkIfPhysicalInterruptOccurred() {
            await ParticleOverlay.shared.setEmitting(true)
            
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
                await ParticleOverlay.shared.moveTo(stepPoint)
                
                // Dynamic organic speed (slower at anchor ends, fast swoosh in middle vector)
                let speedMod = 1.0 - (sin(t * .pi) * 0.8)
                let baseSleep = Float.random(in: 1_500...4_000)
                try? await Task.sleep(nanoseconds: UInt64(baseSleep * Float(speedMod) * 1_000))
            }
            
            if checkIfPhysicalInterruptOccurred() { break }
            
            currentPoint = targetPoint
            await ParticleOverlay.shared.resetTrail()
            try? await Task.sleep(nanoseconds: UInt64(Int.random(in: 200_000_000...1_500_000_000))) // Pause naturally before picking a new place to rest
        }
        
        await ParticleOverlay.shared.resetTrail()
        print("intervenção humana detectada, controle retomado.")
    }
}

private extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        let distanceX = x - point.x
        let distanceY = y - point.y
        return sqrt(distanceX * distanceX + distanceY * distanceY)
    }
}
