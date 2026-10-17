import XCTest
@testable import OpenComputerUseKit

final class AppResolveNoLaunchTests: XCTestCase {
    // Reading an app back after an action resolves it without launching: an
    // app that isn't running is appNotFound at once, rather than opened (or
    // waited for, as a launch is).
    func testResolveWithoutLaunchReportsAMissingAppAtOnce() {
        let started = Date()
        XCTAssertThrowsError(try AppDiscovery.resolve("No Such App 7c1f", launch: false)) { error in
            guard case ComputerUseError.appNotFound(let name) = error else {
                return XCTFail("expected appNotFound, got \(error)")
            }
            XCTAssertEqual(name, "No Such App 7c1f")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0)
    }
}
