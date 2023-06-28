import class AppKit.NSScreen
import class AppKit.NSEvent
import CoreGraphics
import Foundation

final class MouseMove {
    init() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [unowned self] _ in
            guard isIdle() else { return }
            circulate()
        }
    }

    private func move(to point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: CGEventType.mouseMoved, mouseCursorPosition: point, mouseButton: CGMouseButton.left)?.post(tap: CGEventTapLocation.cghidEventTap)
    }

    private func click(at point: CGPoint, mouseButton: CGMouseButton = CGMouseButton.left) {
        CGEvent(mouseEventSource: nil, mouseType: CGEventType.leftMouseDown, mouseCursorPosition: point, mouseButton: mouseButton)?.post(tap: CGEventTapLocation.cghidEventTap)
        usleep(useconds_t(Int.random(in: 400_010..<600_200)))
        CGEvent(mouseEventSource: nil, mouseType: CGEventType.leftMouseUp, mouseCursorPosition: point, mouseButton: mouseButton)?.post(tap: CGEventTapLocation.cghidEventTap)
    }

    private func easeMove(from point¹: CGPoint, to point²: CGPoint, easing: Float = 800.0) {
        let distance = point¹.distance(to: point²)
        let steps = Int(distance * CGFloat(easing) / 100) + 1;
        let xDiff = point².x - point¹.x
        let yDiff = point².y - point¹.y
        let stepSize = 1.0 / Double(steps)

        for i in 0...steps {
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
        return lastEvent > 30
    }

    func circulate() {
        guard let screenSize = NSScreen.main?.visibleFrame.size else { fatalError("Most run on a screen session") }
        let currentPoint = CGPoint(x: NSEvent.mouseLocation.x, y: screenSize.height - NSEvent.mouseLocation.y)
        var lastPoint = currentPoint

        let total = Double(1)
        var angle = Double.zero

        for number in stride(from: 0, to: total, by: 0.015) {
            let cosin = number > 0.8 ? -cos(angle) : cos(angle)

            let x = 50 * cosin + currentPoint.x
            let y = 50 * sin(angle) + currentPoint.y
            let destination = CGPoint(x: x, y: y)

            if number == .zero {
                easeMove(from: currentPoint, to: destination)
            } else {
                move(to: destination)
            }

            usleep(useconds_t(30_000))
            lastPoint = destination
            angle += number
        }

        easeMove(from: lastPoint, to: currentPoint)
    }
}
