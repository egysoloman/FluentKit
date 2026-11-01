import XCTest
@testable import FluentKit

@MainActor
final class ChevronMotionPolicyTests: XCTestCase {
    private let frame = CGRect(x: 0, y: 0, width: 12, height: 12)
    private let key = "fluent.chevron.press"

    func testExplicitMotionPolicyChangesOnTheRetainedChevron() throws {
        let chevron = FluentChevronPrimitiveLayer()
        chevron.update(frame: frame, color: .black, state: .normal, direction: .down,
                       reduceMotion: true, animated: true)
        XCTAssertNil(chevron.animation(forKey: key))

        chevron.update(frame: frame, color: .black, state: .normal, direction: .up,
                       reduceMotion: false, animated: true)
        let animation = try XCTUnwrap(chevron.animation(forKey: key))
        let target = chevron.transform
        chevron.update(frame: frame, color: .black, state: .normal, direction: .up,
                       preservingUnchangedAnimations: true, reduceMotion: false, animated: false)
        XCTAssertEqual(chevron.animation(forKey: key)?.beginTime, animation.beginTime)

        chevron.update(frame: frame, color: .black, state: .normal, direction: .up,
                       reduceMotion: true, animated: true)
        XCTAssertNil(chevron.animation(forKey: key))
        XCTAssertTrue(CATransform3DEqualToTransform(chevron.transform, target))
        chevron.update(frame: frame, color: .black, state: .normal, direction: .up,
                       preservingUnchangedAnimations: true, reduceMotion: false, animated: true)
        XCTAssertNil(chevron.animation(forKey: key), "Changing policy does not replay a settled target")
        chevron.update(frame: frame, color: .black, state: .normal, direction: .down,
                       reduceMotion: false, animated: true)
        XCTAssertNotNil(chevron.animation(forKey: key), "The next real transition uses the current policy")
    }

    func testOmittingAnOverrideRestoresTheSystemMotionPolicy() {
        let systemReducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let chevron = FluentChevronPrimitiveLayer()
        chevron.update(frame: frame, color: .black, state: .normal, direction: .up,
                       reduceMotion: !systemReducesMotion, animated: true)
        XCTAssertEqual(chevron.animation(forKey: key) != nil, systemReducesMotion)
        chevron.update(frame: frame, color: .black, state: .normal, direction: .down, animated: true)
        XCTAssertEqual(chevron.animation(forKey: key) == nil, systemReducesMotion,
                       "Default callers retain the system accessibility policy")
    }
}
