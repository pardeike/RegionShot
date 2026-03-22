import Darwin
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

@main
struct RegionShot {
    static func main() async {
        do {
            let behavior = try parse(arguments: Array(CommandLine.arguments.dropFirst()))

            switch behavior {
            case .showHelp:
                print(usageText)
            case .capture(let options):
                try await capture(using: options)
                print(options.outputURL.path)
            }
        } catch let error as RegionShotError {
            writeStandardError("error: \(error.localizedDescription)\n")
            writeStandardError("Run `RegionShot --help` for usage.\n")
            Darwin.exit(error.exitCode)
        } catch {
            writeStandardError("error: \(error.localizedDescription)\n")
            Darwin.exit(1)
        }
    }
}

private enum CommandBehavior: Sendable {
    case showHelp
    case capture(CommandLineOptions)
}

private struct CommandLineOptions: Sendable {
    let region: CaptureRegion
    let outputURL: URL
    let applicationSelector: ApplicationSelector?
}

private struct CaptureRegion: Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    var rectangleArgument: String {
        "\(x),\(y),\(width),\(height)"
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

private enum ApplicationSelector: Sendable {
    case processID(pid_t)
    case name(String)

    init(rawValue: String) {
        if let processID = Int32(rawValue) {
            self = .processID(processID)
        } else {
            self = .name(rawValue)
        }
    }

    var label: String {
        switch self {
        case .processID(let processID):
            return "pid \(processID)"
        case .name(let name):
            return name
        }
    }
}

private struct DisplayCapturePlan {
    let display: SCDisplay
    let intersectionRect: CGRect
    let pointPixelScale: CGFloat
}

private enum RegionShotError: LocalizedError {
    case invalidArguments(String)
    case invalidInteger(flag: String, value: String)
    case invalidRegion(String)
    case unsupportedFeature(String)
    case capturePermissionDenied
    case applicationNotFound(String)
    case ambiguousApplication(String)
    case captureFailed(String)
    case encodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return message
        case .invalidInteger(let flag, let value):
            return "Expected an integer for \(flag), got `\(value)`."
        case .invalidRegion(let message):
            return message
        case .unsupportedFeature(let message):
            return message
        case .capturePermissionDenied:
            return "Screen Recording permission is required for capture. Grant access and run the command again."
        case .applicationNotFound(let message):
            return message
        case .ambiguousApplication(let message):
            return message
        case .captureFailed(let message):
            return message
        case .encodeFailed(let message):
            return message
        }
    }

    var exitCode: Int32 {
        switch self {
        case .invalidArguments, .invalidInteger, .invalidRegion:
            return 64
        case .unsupportedFeature, .capturePermissionDenied, .applicationNotFound, .ambiguousApplication, .captureFailed, .encodeFailed:
            return 1
        }
    }
}

private let usageText = """
RegionShot captures a rectangular PNG from the screen.

Usage:
  RegionShot <x> <y> <width> <height> [--app <name-or-pid>] [--output /path/to/file.png]
  RegionShot --x <x> --y <y> --width <width> --height <height> [--app <name-or-pid>] [--output /path/to/file.png]
  RegionShot --help

Without `--app`, the tool uses macOS `screencapture -R`.
With `--app`, it captures only that app's windows within the rectangle, even if other apps are in front.
When `--output` is omitted, the tool writes a temporary PNG and prints the path.
"""

private func parse(arguments: [String]) throws -> CommandBehavior {
    guard !arguments.isEmpty else {
        return .showHelp
    }

    if arguments.contains("--help") || arguments.contains("-h") {
        return .showHelp
    }

    if let region = try parsePositionalRegion(arguments: arguments) {
        let values = try parseOptionalFlags(arguments: Array(arguments.dropFirst(4)))
        return .capture(
            CommandLineOptions(
                region: region,
                outputURL: try outputURL(from: values.outputPath),
                applicationSelector: values.applicationSelector
            )
        )
    }

    let values = try parseOptionalFlags(arguments: arguments, requireRectangleFlags: true)

    guard
        let x = values["--x"],
        let y = values["--y"],
        let width = values["--width"],
        let height = values["--height"]
    else {
        throw RegionShotError.invalidArguments("Expected --x, --y, --width, and --height.")
    }

    let region = try CaptureRegion(
        x: parseInteger(x, flag: "--x"),
        y: parseInteger(y, flag: "--y"),
        width: parseInteger(width, flag: "--width"),
        height: parseInteger(height, flag: "--height")
    )

    try validate(region: region)

    return .capture(
        CommandLineOptions(
            region: region,
            outputURL: try outputURL(from: values.outputPath),
            applicationSelector: values.applicationSelector
        )
    )
}

private func parsePositionalRegion(arguments: [String]) throws -> CaptureRegion? {
    guard arguments.count >= 4 else {
        return nil
    }

    let positional = Array(arguments.prefix(4))
    guard positional.allSatisfy({ Int($0) != nil }) else {
        return nil
    }

    let region = try CaptureRegion(
        x: parseInteger(positional[0], flag: "<x>"),
        y: parseInteger(positional[1], flag: "<y>"),
        width: parseInteger(positional[2], flag: "<width>"),
        height: parseInteger(positional[3], flag: "<height>")
    )

    try validate(region: region)
    return region
}

private func parseOptionalFlags(arguments: [String], requireRectangleFlags: Bool = false) throws -> [String: String] {
    var values: [String: String] = [:]
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]

        switch argument {
        case "--help", "-h":
            return [:]
        case "--x", "--y", "--width", "--height", "--output", "--app":
            let valueIndex = index + 1
            guard valueIndex < arguments.count else {
                throw RegionShotError.invalidArguments("Missing value for \(argument).")
            }

            values[argument] = arguments[valueIndex]
            index += 2
        default:
            throw RegionShotError.invalidArguments("Unexpected argument `\(argument)`.")
        }
    }

    if requireRectangleFlags, values.isEmpty {
        throw RegionShotError.invalidArguments("Missing rectangle arguments.")
    }

    return values
}

private func outputURL(from path: String?) throws -> URL {
    guard let path, !path.isEmpty else {
        return temporaryOutputURL()
    }

    let expandedPath = (path as NSString).expandingTildeInPath
    let fileURL: URL

    if expandedPath.hasPrefix("/") {
        fileURL = URL(fileURLWithPath: expandedPath)
    } else {
        fileURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(expandedPath)
    }

    return fileURL.standardizedFileURL
}

private extension Dictionary where Key == String, Value == String {
    var outputPath: String? {
        self["--output"]
    }

    var applicationSelector: ApplicationSelector? {
        guard let rawValue = self["--app"], !rawValue.isEmpty else {
            return nil
        }

        return ApplicationSelector(rawValue: rawValue)
    }
}

private func temporaryOutputURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("regionshot-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString.lowercased())")
        .appendingPathExtension("png")
}

private func parseInteger(_ value: String, flag: String) throws -> Int {
    guard let integer = Int(value) else {
        throw RegionShotError.invalidInteger(flag: flag, value: value)
    }

    return integer
}

private func validate(region: CaptureRegion) throws {
    guard region.width > 0 else {
        throw RegionShotError.invalidRegion("Width must be greater than zero.")
    }

    guard region.height > 0 else {
        throw RegionShotError.invalidRegion("Height must be greater than zero.")
    }
}

private func capture(using options: CommandLineOptions) async throws {
    let directoryURL = options.outputURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    if let applicationSelector = options.applicationSelector {
        guard #available(macOS 14.0, *) else {
            throw RegionShotError.unsupportedFeature("`--app` requires macOS 14 or newer.")
        }

        try await captureApplicationRegion(
            selector: applicationSelector,
            region: options.region,
            outputURL: options.outputURL
        )
        return
    }

    try captureScreenRegion(region: options.region, outputURL: options.outputURL)
}

private func captureScreenRegion(region: CaptureRegion, outputURL: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = [
        "-x",
        "-t",
        "png",
        "-R\(region.rectangleArgument)",
        outputURL.path,
    ]

    let standardError = Pipe()
    process.standardError = standardError

    try process.run()
    process.waitUntilExit()

    let errorText = String(
        decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
        as: UTF8.self
    ).trimmingCharacters(in: .whitespacesAndNewlines)

    guard process.terminationStatus == 0 else {
        let message = errorText.isEmpty ? "screencapture exited with status \(process.terminationStatus)." : errorText
        throw RegionShotError.captureFailed(message)
    }

    guard FileManager.default.fileExists(atPath: outputURL.path) else {
        throw RegionShotError.captureFailed("Capture succeeded but no PNG was written to \(outputURL.path).")
    }
}

@available(macOS 14.0, *)
private func captureApplicationRegion(
    selector: ApplicationSelector,
    region: CaptureRegion,
    outputURL: URL
) async throws {
    try ensureScreenCaptureAccess()

    let shareableContent = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
    let application = try resolveApplication(selector: selector, in: shareableContent.applications)
    let visibleWindows = shareableContent.windows.filter {
        $0.owningApplication?.processID == application.processID && ($0.isOnScreen || $0.isActive)
    }

    guard !visibleWindows.isEmpty else {
        throw RegionShotError.captureFailed("No shareable windows are currently visible for `\(application.applicationName)`.")
    }

    let regionRect = region.rect
    let plans = planDisplayCaptures(
        displays: shareableContent.displays,
        visibleWindows: visibleWindows,
        regionRect: regionRect
    )

    guard !plans.isEmpty else {
        throw RegionShotError.captureFailed("No visible content from `\(application.applicationName)` intersects the requested rectangle.")
    }

    let canvasScale = max(1, plans.map(\.pointPixelScale).max() ?? 1)
    let canvasSize = CGSize(
        width: max(1, ceil(regionRect.width * canvasScale)),
        height: max(1, ceil(regionRect.height * canvasScale))
    )

    guard
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil,
            width: Int(canvasSize.width),
            height: Int(canvasSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        throw RegionShotError.captureFailed("Failed to allocate an image buffer for the app-filtered capture.")
    }

    context.translateBy(x: 0, y: canvasSize.height)
    context.scaleBy(x: 1, y: -1)

    for plan in plans {
        let filter = SCContentFilter(display: plan.display, including: [application], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(ceil(plan.intersectionRect.width * plan.pointPixelScale))
        configuration.height = Int(ceil(plan.intersectionRect.height * plan.pointPixelScale))
        configuration.sourceRect = CGRect(
            x: plan.intersectionRect.minX - plan.display.frame.minX,
            y: plan.intersectionRect.minY - plan.display.frame.minY,
            width: plan.intersectionRect.width,
            height: plan.intersectionRect.height
        )
        let clearBackgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)

        configuration.scalesToFit = true
        configuration.showsCursor = false
        configuration.backgroundColor = clearBackgroundColor
        configuration.ignoreShadowsDisplay = true

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let destinationRect = CGRect(
            x: (plan.intersectionRect.minX - regionRect.minX) * canvasScale,
            y: (plan.intersectionRect.minY - regionRect.minY) * canvasScale,
            width: plan.intersectionRect.width * canvasScale,
            height: plan.intersectionRect.height * canvasScale
        )

        context.draw(image, in: destinationRect)
    }

    guard let image = context.makeImage() else {
        throw RegionShotError.captureFailed("ScreenCaptureKit returned no image data for the filtered capture.")
    }

    try writePNG(image: image, to: outputURL)
}

@available(macOS 14.0, *)
private func resolveApplication(
    selector: ApplicationSelector,
    in applications: [SCRunningApplication]
) throws -> SCRunningApplication {
    switch selector {
    case .processID(let processID):
        guard let application = applications.first(where: { $0.processID == processID }) else {
            throw RegionShotError.applicationNotFound("No shareable running application matches pid \(processID).")
        }

        return application
    case .name(let query):
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            throw RegionShotError.invalidArguments("`--app` requires a non-empty name or process id.")
        }

        let exactMatches = applications.filter {
            $0.applicationName.lowercased() == normalizedQuery || $0.bundleIdentifier.lowercased() == normalizedQuery
        }

        if exactMatches.count == 1, let match = exactMatches.first {
            return match
        }

        let partialMatches = applications.filter {
            $0.applicationName.lowercased().contains(normalizedQuery) || $0.bundleIdentifier.lowercased().contains(normalizedQuery)
        }

        let matches = exactMatches.isEmpty ? partialMatches : exactMatches

        guard !matches.isEmpty else {
            throw RegionShotError.applicationNotFound("No shareable running application matches `\(query)`.")
        }

        guard matches.count == 1, let match = matches.first else {
            let suggestions = matches
                .prefix(5)
                .map { "\($0.applicationName) (pid \($0.processID), \($0.bundleIdentifier))" }
                .joined(separator: ", ")
            throw RegionShotError.ambiguousApplication("More than one running application matches `\(query)`: \(suggestions)")
        }

        return match
    }
}

@available(macOS 14.0, *)
private func planDisplayCaptures(
    displays: [SCDisplay],
    visibleWindows: [SCWindow],
    regionRect: CGRect
) -> [DisplayCapturePlan] {
    displays.compactMap { display in
        let intersectionRect = display.frame.intersection(regionRect)
        guard !intersectionRect.isNull, !intersectionRect.isEmpty else {
            return nil
        }

        let hasWindowContent = visibleWindows.contains { window in
            !window.frame.intersection(intersectionRect).isNull
        }

        guard hasWindowContent else {
            return nil
        }

        return DisplayCapturePlan(
            display: display,
            intersectionRect: intersectionRect,
            pointPixelScale: pointPixelScale(for: display)
        )
    }
}

private func pointPixelScale(for display: SCDisplay) -> CGFloat {
    guard
        display.width > 0,
        let mode = CGDisplayCopyDisplayMode(display.displayID)
    else {
        return 1
    }

    return max(1, CGFloat(mode.pixelWidth) / CGFloat(display.width))
}

private func ensureScreenCaptureAccess() throws {
    if CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() {
        return
    }

    throw RegionShotError.capturePermissionDenied
}

private func writePNG(image: CGImage, to outputURL: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw RegionShotError.encodeFailed("Failed to create a PNG destination for \(outputURL.path).")
    }

    CGImageDestinationAddImage(destination, image, nil)

    guard CGImageDestinationFinalize(destination) else {
        throw RegionShotError.encodeFailed("Failed to write PNG data to \(outputURL.path).")
    }
}

private func writeStandardError(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}
