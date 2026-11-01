import XCTest

/// Await an observable UI result without assuming how quickly a loaded runner services timers.
@MainActor
func waitForUI(_ condition: @autoclosure () -> Bool, timeout: TimeInterval = 2,
               file: StaticString = #filePath, line: UInt = #line) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    XCTAssertTrue(condition(), "Timed out waiting for the expected UI state", file: file, line: line)
}
