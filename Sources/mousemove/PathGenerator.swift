import Foundation
import CoreGraphics

struct PathGenerator {
    struct Config {
        static let padding: CGFloat = 80.0
        static let minSteps: Int = 100
        static let distanceDivisor: CGFloat = 3.0
        static let maxExtraSteps: Int = 100
        static let controlPointOffset: CGFloat = 400.0
    }

    struct BezierPoint {
        let point: CGPoint
        let speedModifier: Double
    }

    func generatePoints(from start: CGPoint, to target: CGPoint, screenBounds: CGRect) -> [BezierPoint] {
        let safeBounds = screenBounds.insetBy(dx: Config.padding, dy: Config.padding)
        
        // Generate random control points for curvature
        let cp1 = CGPoint(
            x: start.x + CGFloat.random(in: -Config.controlPointOffset...Config.controlPointOffset),
            y: start.y + CGFloat.random(in: -Config.controlPointOffset...Config.controlPointOffset)
        )
        let cp2 = CGPoint(
            x: target.x + CGFloat.random(in: -Config.controlPointOffset...Config.controlPointOffset),
            y: target.y + CGFloat.random(in: -Config.controlPointOffset...Config.controlPointOffset)
        )

        let distance = start.distance(to: target)
        let baseSteps = Int(max(CGFloat(Config.minSteps), distance / Config.distanceDivisor))
        let steps = Int.random(in: baseSteps...(baseSteps + Config.maxExtraSteps))
        
        var points: [BezierPoint] = []
        
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            
            // Cubic Bezier interpolation
            let invT = 1.0 - t
            let term1 = invT * invT * invT
            let term2 = 3.0 * invT * invT * t
            let term3 = 3.0 * invT * t * t
            let term4 = t * t * t
            
            var stepPoint = CGPoint(
                x: term1 * start.x + term2 * cp1.x + term3 * cp2.x + term4 * target.x,
                y: term1 * start.y + term2 * cp1.y + term3 * cp2.y + term4 * target.y
            )
            
            // Clamp within safe bounds
            stepPoint.x = max(safeBounds.minX, min(safeBounds.maxX, stepPoint.x))
            stepPoint.y = max(safeBounds.minY, min(safeBounds.maxY, stepPoint.y))
            
            let speedMod = 1.0 - (sin(t * .pi) * 0.8)
            points.append(BezierPoint(point: stepPoint, speedModifier: Double(speedMod)))
        }
        
        return points
    }
}

extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        let dx = x - point.x
        let dy = y - point.y
        return sqrt(dx * dx + dy * dy)
    }
}
