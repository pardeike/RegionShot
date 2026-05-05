import CoreGraphics
import XCTest
@testable import RegionShot

final class RegionShotTests: XCTestCase {
    func testFindAppParsing() throws {
        let behavior = try parse(arguments: ["--find-app", "RimWorld"])

        guard case .findApps(let command) = behavior else {
            return XCTFail("Expected find-app behavior.")
        }

        XCTAssertEqual(command.query, "RimWorld")
    }

    func testVisibleWindowCaptureParsing() throws {
        let behavior = try parse(arguments: [
            "--app", "RimWorld",
            "--visible-window",
            "--output", "/tmp/rimworld.png",
        ])

        guard case .captureVisibleWindow(let command) = behavior else {
            return XCTFail("Expected visible-window capture behavior.")
        }

        guard case .name(let name) = command.applicationSelector else {
            return XCTFail("Expected name application selector.")
        }

        XCTAssertEqual(name, "RimWorld")
        XCTAssertNil(command.windowSelection)
        XCTAssertEqual(command.outputURL.path, "/tmp/rimworld.png")
    }

    func testScreenCaptureTimeoutParsing() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--timeout", "0.25",
        ])

        guard case .listWindows(let command) = behavior else {
            return XCTFail("Expected list-windows behavior.")
        }

        XCTAssertEqual(command.screenCaptureTimeout, 0.25, accuracy: 0.001)
    }

    func testFindAppRejectsMixedModes() {
        XCTAssertThrowsError(
            try parse(arguments: ["--find-app", "RimWorld", "--app", "Terminal"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--find-app"))
        }
    }

    func testVisibleWindowCatalogFiltersToNormalVisibleWindows() {
        let snapshots = [
            WindowSnapshot(
                windowID: 10,
                ownerPID: 100,
                title: "Menu",
                bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
                layer: 20,
                alpha: 1
            ),
            WindowSnapshot(
                windowID: 11,
                ownerPID: 100,
                title: "Front",
                bounds: CGRect(x: 10, y: 20, width: 300, height: 200),
                layer: 0,
                alpha: 1
            ),
            WindowSnapshot(
                windowID: 12,
                ownerPID: 100,
                title: "Transparent",
                bounds: CGRect(x: 20, y: 30, width: 300, height: 200),
                layer: 0,
                alpha: 0
            ),
            WindowSnapshot(
                windowID: 13,
                ownerPID: 200,
                title: "Other",
                bounds: CGRect(x: 30, y: 40, width: 300, height: 200),
                layer: 0,
                alpha: 1
            ),
        ]

        let windows = visibleWindows(for: 100, snapshots: snapshots)

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].index, 0)
        XCTAssertEqual(windows[0].windowID, 11)
        XCTAssertEqual(windows[0].title, "Front")
    }

    func testTimeoutReturnsFailureWithoutWaitingForOperation() async throws {
        let start = Date()

        do {
            let _: Int = try await withTimeout(
                seconds: 0.05,
                timeoutMessage: { "timed out" },
                operation: {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    return 1
                }
            )
            XCTFail("Expected timeout.")
        } catch RegionShotError.operationTimedOut(let message) {
            XCTAssertEqual(message, "timed out")
            XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        }
    }

    func testTimeoutReturnsSuccessfulOperation() async throws {
        let value: Int = try await withTimeout(
            seconds: 1,
            timeoutMessage: { "timed out" },
            operation: { 42 }
        )

        XCTAssertEqual(value, 42)
    }
}
