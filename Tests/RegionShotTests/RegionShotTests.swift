import CoreGraphics
import Foundation
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

    func testAsciiArtParsing() throws {
        let behavior = try parse(arguments: [
            "--ascii", "/tmp/screenshot.png",
            "--ascii-width", "100",
            "--ascii-max-height", "40",
            "--ascii-invert",
            "--ascii-no-ocr",
        ])

        guard case .asciiArt(let command) = behavior else {
            return XCTFail("Expected ascii-art behavior.")
        }

        XCTAssertEqual(command.imageURL.path, "/tmp/screenshot.png")
        XCTAssertEqual(command.style, .layout)
        XCTAssertEqual(command.width, 100)
        XCTAssertEqual(command.maxHeight, 40)
        XCTAssertTrue(command.invert)
        XCTAssertFalse(command.includeOCR)
    }

    func testAsciiArtParsingUsesDefaults() throws {
        let behavior = try parse(arguments: ["--ascii", "/tmp/screenshot.png"])

        guard case .asciiArt(let command) = behavior else {
            return XCTFail("Expected ascii-art behavior.")
        }

        XCTAssertEqual(command.style, .layout)
        XCTAssertEqual(command.width, 160)
        XCTAssertEqual(command.maxHeight, 100)
        XCTAssertFalse(command.invert)
        XCTAssertTrue(command.includeOCR)
    }

    func testAsciiArtParsingSupportsToneStyleDefaults() throws {
        let behavior = try parse(arguments: ["--ascii", "/tmp/screenshot.png", "--ascii-style", "tone"])

        guard case .asciiArt(let command) = behavior else {
            return XCTFail("Expected ascii-art behavior.")
        }

        XCTAssertEqual(command.style, .tone)
        XCTAssertEqual(command.width, 120)
        XCTAssertEqual(command.maxHeight, 80)
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

    func testAccessibilityWindowListParsing() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--list-accessibility-windows",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .name(let name) = command.applicationSelector else {
            return XCTFail("Expected name application selector.")
        }

        guard case .listWindows = command.mode else {
            return XCTFail("Expected accessibility window list mode.")
        }

        XCTAssertEqual(name, "Terminal")
        XCTAssertNil(command.windowSelection)
    }

    func testAccessibilityWindowListAliasParsing() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--list-ax-windows",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .listWindows = command.mode else {
            return XCTFail("Expected accessibility window list mode.")
        }
    }

    func testRaiseWindowParsingWithIndex() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--window-index", "2",
            "--raise-window",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .index(let index) = command.windowSelection else {
            return XCTFail("Expected window index selection.")
        }

        guard case .raiseWindow = command.mode else {
            return XCTFail("Expected raise-window mode.")
        }

        XCTAssertEqual(index, 2)
    }

    func testRaiseWindowAliasParsingWithName() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--window-name", "server logs",
            "--raise",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .name(let name) = command.windowSelection else {
            return XCTFail("Expected window-name selection.")
        }

        guard case .raiseWindow = command.mode else {
            return XCTFail("Expected raise-window mode.")
        }

        XCTAssertEqual(name, "server logs")
    }

    func testAsciiArtRejectsMixedModes() {
        XCTAssertThrowsError(
            try parse(arguments: ["--ascii", "/tmp/screenshot.png", "--app", "Terminal"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--ascii"))
        }
    }

    func testAsciiArtRejectsInvalidDimensions() {
        XCTAssertThrowsError(
            try parse(arguments: ["--ascii", "/tmp/screenshot.png", "--ascii-width", "15"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--ascii-width"))
        }

        XCTAssertThrowsError(
            try parse(arguments: ["--ascii", "/tmp/screenshot.png", "--ascii-max-height", "7"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--ascii-max-height"))
        }
    }

    func testAsciiArtRejectsInvalidStyle() {
        XCTAssertThrowsError(
            try parse(arguments: ["--ascii", "/tmp/screenshot.png", "--ascii-style", "photo"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--ascii-style"))
        }
    }

    func testAsciiArtOptionsRequireAsciiMode() {
        XCTAssertThrowsError(
            try parse(arguments: ["--ascii-width", "100"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--ascii"))
        }
    }

    func testPressMenuItemParsing() throws {
        let behavior = try parse(arguments: [
            "--app", "Drafty",
            "--menu-bar-index", "0",
            "--press-menu-item", "Quick Tasks",
        ])

        guard case .menuBar(let command) = behavior else {
            return XCTFail("Expected menu-bar behavior.")
        }

        guard case .name(let name) = command.applicationSelector else {
            return XCTFail("Expected name application selector.")
        }

        guard case .index(let index) = command.selection else {
            return XCTFail("Expected menu-bar index selection.")
        }

        guard case .pressMenuItem(let selection) = command.mode else {
            return XCTFail("Expected child menu item press mode.")
        }

        XCTAssertEqual(name, "Drafty")
        XCTAssertEqual(index, 0)
        XCTAssertEqual(selection.query, "Quick Tasks")
        XCTAssertNil(command.outputURL)
    }

    func testPressMenuItemRejectsOutput() {
        XCTAssertThrowsError(
            try parse(arguments: [
                "--app", "Drafty",
                "--menu-bar-index", "0",
                "--press-menu-item", "Quick Tasks",
                "--output", "/tmp/menu.png",
            ])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--press-menu-item"))
        }
    }

    func testAccessibilityWindowListRejectsWindowSelection() {
        XCTAssertThrowsError(
            try parse(arguments: [
                "--app", "Terminal",
                "--window-index", "0",
                "--list-accessibility-windows",
            ])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--list-accessibility-windows"))
        }
    }

    func testRaiseWindowRejectsOutput() {
        XCTAssertThrowsError(
            try parse(arguments: [
                "--app", "Terminal",
                "--window-index", "0",
                "--raise-window",
                "--output", "/tmp/window.png",
            ])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("Accessibility inspection and actions"))
        }
    }

    func testFindAppRejectsMixedModes() {
        XCTAssertThrowsError(
            try parse(arguments: ["--find-app", "RimWorld", "--app", "Terminal"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--find-app"))
        }
    }

    func testScreenRegionCapturePreflightsBeforeLaunchingScreencapture() throws {
        let outputURL = URL(fileURLWithPath: "/tmp/regionshot-unit-test.png")
        var events: [String] = []

        try captureScreenRegion(
            region: CaptureRegion(x: 1, y: 2, width: 3, height: 4),
            outputURL: outputURL,
            ensureAccess: {
                events.append("preflight")
            },
            runCapture: { region, url in
                events.append("capture")
                XCTAssertEqual(region.rectangleArgument, "1,2,3,4")
                XCTAssertEqual(url, outputURL)
                return ScreenCaptureProcessResult(terminationStatus: 0, standardError: "")
            },
            fileExists: { path in
                events.append("file-exists")
                XCTAssertEqual(path, outputURL.path)
                return true
            }
        )

        XCTAssertEqual(events, ["preflight", "capture", "file-exists"])
    }

    func testScreenRegionCaptureDoesNotLaunchScreencaptureWhenPreflightFails() {
        let outputURL = URL(fileURLWithPath: "/tmp/regionshot-unit-test.png")
        var events: [String] = []

        XCTAssertThrowsError(
            try captureScreenRegion(
                region: CaptureRegion(x: 1, y: 2, width: 3, height: 4),
                outputURL: outputURL,
                ensureAccess: {
                    events.append("preflight")
                    throw RegionShotError.capturePermissionDenied
                },
                runCapture: { _, _ in
                    XCTFail("screencapture should not run after preflight failure.")
                    return ScreenCaptureProcessResult(terminationStatus: 0, standardError: "")
                },
                fileExists: { _ in
                    XCTFail("capture output should not be checked after preflight failure.")
                    return false
                }
            )
        ) { error in
            guard case RegionShotError.capturePermissionDenied = error else {
                return XCTFail("Expected capturePermissionDenied, got \(error).")
            }
        }

        XCTAssertEqual(events, ["preflight"])
    }

    func testEncodeJSONUsesCompactSortedKeys() throws {
        let json = try encodeJSON(
            JSONFixture(
                z: "last",
                a: "first",
                nested: JSONNestedFixture(b: 2, a: 1)
            )
        )

        XCTAssertEqual(json, #"{"a":"first","nested":{"a":1,"b":2},"z":"last"}"#)
        XCTAssertFalse(json.contains("\n"))
    }

    func testRegionShotErrorExitCodesDistinguishActionableFailureFamilies() {
        let expectations: [(RegionShotError, Int32)] = [
            (.invalidArguments("bad flag"), 64),
            (.invalidInteger(flag: "--width", value: "wide"), 64),
            (.invalidRegion("bad rectangle"), 64),
            (.ambiguousApplication("two apps"), 65),
            (.ambiguousWindow("two windows"), 65),
            (.applicationNotFound("missing app"), 66),
            (.windowNotFound("missing window"), 66),
            (.unsupportedFeature("not available"), 69),
            (.capturePermissionDenied, 69),
            (.accessibilityPermissionDenied, 69),
            (.captureFailed("capture failed"), 70),
            (.accessibilityQueryFailed("query failed"), 70),
            (.encodeFailed("encoding failed"), 70),
            (.operationTimedOut("too slow"), 75),
        ]

        for (error, expectedExitCode) in expectations {
            XCTAssertEqual(error.exitCode, expectedExitCode, String(describing: error))
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
                windowID: 14,
                ownerPID: 100,
                title: "Floating Panel",
                bounds: CGRect(x: 12, y: 24, width: 300, height: 120),
                layer: 3,
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

        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].index, 0)
        XCTAssertEqual(windows[0].windowID, 11)
        XCTAssertEqual(windows[0].title, "Front")
        XCTAssertEqual(windows[1].index, 1)
        XCTAssertEqual(windows[1].windowID, 14)
        XCTAssertEqual(windows[1].title, "Floating Panel")
    }

    func testAsciiRendererPreservesTopToBottomOrientation() throws {
        let image = try makeGrayscaleImage(
            width: 2,
            height: 4,
            pixels: [
                0, 0,
                0, 0,
                255, 255,
                255, 255,
            ]
        )

        let rendered = try renderAsciiArt(
            from: image,
            options: AsciiArtOptions(width: 2, maxHeight: 2, invert: false)
        )
        let lines = rendered.text.components(separatedBy: "\n")

        XCTAssertEqual(rendered.width, 2)
        XCTAssertEqual(rendered.height, 2)
        XCTAssertEqual(lines, ["@@", "  "])
    }

    func testAsciiRendererCanInvertLightness() throws {
        let image = try makeGrayscaleImage(
            width: 2,
            height: 4,
            pixels: [
                0, 0,
                0, 0,
                255, 255,
                255, 255,
            ]
        )

        let rendered = try renderAsciiArt(
            from: image,
            options: AsciiArtOptions(width: 2, maxHeight: 2, invert: true)
        )

        XCTAssertEqual(rendered.text.components(separatedBy: "\n"), ["  ", "@@"])
    }

    func testAsciiLayoutOverlaysOCRText() throws {
        let image = try makeGrayscaleImage(width: 80, height: 40, pixels: Array(repeating: 255, count: 80 * 40))
        let rendered = try renderAsciiLayout(
            from: image,
            options: AsciiLayoutOptions(width: 40, maxHeight: 10),
            textBlocks: [
                OCRTextBlock(
                    text: "Finder Window",
                    confidence: 0.9,
                    bounds: CGRect(x: 10, y: 8, width: 32, height: 8)
                ),
            ]
        )

        XCTAssertTrue(rendered.text.contains("Finder Window"))
    }

    func testAsciiLayoutWrapsLongOCRText() throws {
        let image = try makeGrayscaleImage(width: 80, height: 40, pixels: Array(repeating: 255, count: 80 * 40))
        let rendered = try renderAsciiLayout(
            from: image,
            options: AsciiLayoutOptions(width: 24, maxHeight: 10),
            textBlocks: [
                OCRTextBlock(
                    text: "This is a very long Finder row",
                    confidence: 0.9,
                    bounds: CGRect(x: 48, y: 10, width: 16, height: 8)
                ),
            ]
        )

        XCTAssertTrue(rendered.text.contains("This is"))
        XCTAssertTrue(rendered.text.contains("Finder row"))
    }

    func testAsciiLayoutDrawsSparseEdges() throws {
        let image = try makeGrayscaleImage(
            width: 20,
            height: 20,
            pixels: borderedPixels(width: 20, height: 20)
        )
        let rendered = try renderAsciiLayout(
            from: image,
            options: AsciiLayoutOptions(width: 20, maxHeight: 10),
            textBlocks: []
        )

        XCTAssertTrue(rendered.text.contains("-") || rendered.text.contains("|") || rendered.text.contains("+"))
    }

    func testOCRFormattingSortsBlocksForReadingOrder() {
        let formatted = formatOCRTextBlocks([
            OCRTextBlock(
                text: "Bottom",
                confidence: 0.8,
                bounds: CGRect(x: 10, y: 100, width: 60, height: 14)
            ),
            OCRTextBlock(
                text: "Top \"Menu\"",
                confidence: 0.93,
                bounds: CGRect(x: 5, y: 10, width: 40, height: 8)
            ),
        ])

        XCTAssertEqual(
            formatted.components(separatedBy: "\n"),
            [
                "ocr:",
                "- [x=5 y=10 w=40 h=8 confidence=0.93] \"Top \\\"Menu\\\"\"",
                "- [x=10 y=100 w=60 h=14 confidence=0.80] \"Bottom\"",
            ]
        )
    }

    func testAsciiReportFormatsDisabledOCR() {
        let report = formatAsciiArtReport(
            imagePath: "/tmp/screenshot.png",
            imageWidth: 200,
            imageHeight: 100,
            style: .layout,
            rendered: RenderedAsciiArt(width: 4, height: 1, text: "@@  "),
            ocrStatus: .disabled
        )

        let expected = [
            "image: /tmp/screenshot.png",
            "size: 200x100 px",
            "layout: 4x1 chars",
            "@@  ",
            "",
            "ocr: disabled",
        ].joined(separator: "\n")

        XCTAssertEqual(report, expected)
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

private func makeGrayscaleImage(width: Int, height: Int, pixels: [UInt8]) throws -> CGImage {
    XCTAssertEqual(pixels.count, width * height)

    var rgba: [UInt8] = []
    rgba.reserveCapacity(width * height * 4)

    for pixel in pixels {
        rgba.append(pixel)
        rgba.append(pixel)
        rgba.append(pixel)
        rgba.append(255)
    }

    guard
        let data = CFDataCreate(nil, rgba, rgba.count),
        let provider = CGDataProvider(data: data),
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    else {
        throw RegionShotError.captureFailed("Failed to create test image.")
    }

    return image
}

private func borderedPixels(width: Int, height: Int) -> [UInt8] {
    (0..<height).flatMap { row in
        (0..<width).map { column in
            row == 0 || row == height - 1 || column == 0 || column == width - 1 ? UInt8(0) : UInt8(255)
        }
    }
}

private struct JSONFixture: Encodable {
    let z: String
    let a: String
    let nested: JSONNestedFixture
}

private struct JSONNestedFixture: Encodable {
    let b: Int
    let a: Int
}
