import CoreGraphics

extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        let distanceX = x - point.x
        let distanceY = y - point.y
        return sqrt(distanceX * distanceX + distanceY * distanceY)
    }
}

extension CGFloat {
    var cubicEaseOut: CGFloat {
        if self < 0.5 {
            return 4 * pow(self, 3)
        } else {
            let function = (2 * self) - 2
            return 0.5 * pow(function, 3) + 1
        }
    }
}
