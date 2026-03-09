import XCTest
@testable import mousemove

final class PathGeneratorTests: XCTestCase {
    var sut: PathGenerator!
    
    override func setUp() {
        super.setUp()
        sut = PathGenerator()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    func testGeneratePoints_ReturnsNonEmptyArray() {
        let start = CGPoint(x: 100, y: 100)
        let target = CGPoint(x: 500, y: 500)
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        
        let points = sut.generatePoints(from: start, to: target, screenBounds: bounds)
        
        XCTAssertFalse(points.isEmpty)
        XCTAssertGreaterThanOrEqual(points.count, PathGenerator.Config.minSteps)
    }
    
    func testGeneratePoints_PointsAreWithinSafeBounds() {
        let start = CGPoint(x: 100, y: 100)
        let target = CGPoint(x: 900, y: 900)
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let padding = PathGenerator.Config.padding
        let safeBounds = bounds.insetBy(dx: padding, dy: padding)
        
        let points = sut.generatePoints(from: start, to: target, screenBounds: bounds)
        
        for p in points {
            XCTAssertTrue(safeBounds.contains(p.point), "Point \(p.point) is outside safe bounds \(safeBounds)")
        }
    }
    
    func testGeneratePoints_SpeedModifiersAreWithinExpectedRange() {
        let start = CGPoint(x: 100, y: 100)
        let target = CGPoint(x: 500, y: 500)
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        
        let points = sut.generatePoints(from: start, to: target, screenBounds: bounds)
        
        for p in points {
            // speedMod = 1.0 - (sin(t * .pi) * 0.8)
            // min is 1.0 - 0.8 = 0.2
            // max is 1.0 - 0.0 = 1.0
            XCTAssertGreaterThanOrEqual(p.speedModifier, 0.19)
            XCTAssertLessThanOrEqual(p.speedModifier, 1.01)
        }
    }
}
