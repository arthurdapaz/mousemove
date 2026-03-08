import CoreGraphics

extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        let distanceX = x - point.x
        let distanceY = y - point.y
        return sqrt(distanceX * distanceX + distanceY * distanceY)
    }
}
