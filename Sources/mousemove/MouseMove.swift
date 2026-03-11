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
    
    private let visualizer: any MovementVisualizer
    private let pathGenerator = PathGenerator()

    // Stream como ponte thread-safe entre callback C e actor
    private let interruptStream: AsyncStream<Void>
    private let interruptContinuation: AsyncStream<Void>.Continuation

    init(visualizer: any MovementVisualizer) {
        self.visualizer = visualizer
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
        let padding = PathGenerator.Config.padding
        
        let safeBounds = displayBounds.insetBy(dx: padding, dy: padding)
        
        var currentPoint = CGEvent(source: nil)?.location ?? CGPoint(x: displayBounds.midX, y: displayBounds.midY)
        currentPoint.x = max(safeBounds.minX, min(safeBounds.maxX, currentPoint.x))
        currentPoint.y = max(safeBounds.minY, min(safeBounds.maxY, currentPoint.y))

        print("iniciando movimento ad-infinitum...")
        
        while !checkIfPhysicalInterruptOccurred() {
            let targetPoint = CGPoint(
                x: CGFloat.random(in: safeBounds.minX...safeBounds.maxX),
                y: CGFloat.random(in: safeBounds.minY...safeBounds.maxY)
            )
            
            let pathPoints = pathGenerator.generatePoints(from: currentPoint, to: targetPoint, screenBounds: displayBounds)
            
            for step in pathPoints {
                if checkIfPhysicalInterruptOccurred() { break }
                
                await postSyntheticMoveEvent(to: step.point)
                await visualizer.moveTo(step.point)
                
                let baseSleep = Float.random(in: 1_500...4_000)
                try? await Task.sleep(nanoseconds: UInt64(baseSleep * Float(step.speedModifier) * 1_000))
            }
            
            if checkIfPhysicalInterruptOccurred() { break }
            
            currentPoint = targetPoint
            try? await Task.sleep(nanoseconds: UInt64(Int.random(in: 200_000_000...1_500_000_000)))
        }
        
        await visualizer.explodeSupernova()
        print("intervenção humana detectada, controle retomado. SUPERNOVA!")
    }
}

