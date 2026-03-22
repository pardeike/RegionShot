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
            case .capture(let command):
                try await capture(using: command)
                print(command.outputURL.path)
            case .listWindows(let command):
                let json = try await listWindows(using: command)
                print(json)
            }
        } catch let error as RegionShotError {
            writeStandardError("error: \(error.localizedDescription)\n")
            writeStandardError("Run `regionshot --help` for usage.\n")
            Darwin.exit(error.exitCode)
        } catch {
            writeStandardError("error: \(error.localizedDescription)\n")
            Darwin.exit(1)
        }
    }
}

private enum CommandBehavior: Sendable {
    case showHelp
    case capture(CaptureCommand)
    case listWindows(ListWindowsCommand)
}

private struct CaptureCommand: Sendable {
    let region: CaptureRegion?
    let outputURL: URL
    let applicationSelector: ApplicationSelector?
    let windowSelection: WindowSelection?
    let windowCrop: WindowCropRect?
}

private struct ListWindowsCommand: Sendable {
    let applicationSelector: ApplicationSelector
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

private struct WindowCropRect: Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

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

private enum WindowSelection: Sendable {
    case frontmost
    case index(Int)
    case name(String)
}

private struct ParsedArguments {
    let region: CaptureRegion?
    let values: [String: String]
    let flags: Set<String>
}

private struct DisplayCapturePlan {
    let display: SCDisplay
    let intersectionRect: CGRect
    let pointPixelScale: CGFloat
}

private struct AppWindowCatalog {
    let application: SCRunningApplication
    let windows: [CatalogWindow]
}

private struct CatalogWindow {
    let index: Int
    let windowID: CGWindowID
    let title: String?
    let frame: CGRect
    let layer: Int
    let isOnScreen: Bool
    let isActive: Bool
    let scWindow: SCWindow
}

private struct WindowSnapshot {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let title: String?
    let bounds: CGRect
    let layer: Int
}

private struct WindowListResponse: Encodable {
    let application: WindowListApplication
    let windows: [WindowListEntry]
}

private struct WindowListApplication: Encodable {
    let name: String
    let bundleIdentifier: String
    let processID: Int32
}

private struct WindowListEntry: Encodable {
    let index: Int
    let windowID: UInt32
    let title: String?
    let frame: JSONRect
    let layer: Int
    let isOnScreen: Bool
    let isActive: Bool
}

private struct JSONRect: Encodable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }
}

private enum RegionShotError: LocalizedError {
    case invalidArguments(String)
    case invalidInteger(flag: String, value: String)
    case invalidRegion(String)
    case unsupportedFeature(String)
    case capturePermissionDenied
    case applicationNotFound(String)
    case ambiguousApplication(String)
    case windowNotFound(String)
    case ambiguousWindow(String)
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
        case .windowNotFound(let message):
            return message
        case .ambiguousWindow(let message):
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
        case .unsupportedFeature, .capturePermissionDenied, .applicationNotFound, .ambiguousApplication, .windowNotFound, .ambiguousWindow, .captureFailed, .encodeFailed:
            return 1
        }
    }
}

private let usageText = """
regionshot = macOS screenshot wrapper around native `screencapture` and `ScreenCaptureKit`.

Output:
  capture mode -> writes a PNG file, then prints the final path to stdout
  inspect mode -> prints JSON to stdout
  errors -> stderr, non-zero exit

Forms:
  regionshot X Y WIDTH HEIGHT [--app APP] [--output FILE]
  regionshot --x X --y Y --width WIDTH --height HEIGHT [--app APP] [--output FILE]
  regionshot --app APP
  regionshot --app APP --frontmost-window [--window-crop X,Y,W,H] [--output FILE]
  regionshot --app APP --window-index N [--window-crop X,Y,W,H] [--output FILE]
  regionshot --app APP --window-name TITLE [--window-crop X,Y,W,H] [--output FILE]

Rules:
  `--app` accepts app name, bundle id, or pid
  `--app` alone == inspect mode == same as `--list-windows`
  window list JSON includes frontmost-first indices, titles, and bounds
  `--window-crop` is relative to the selected window's top-left in points
  rectangle mode without `--app` forwards to `screencapture -R`
  rectangle mode with `--app` includes only that app, even if covered by other windows
"""

private func parse(arguments: [String]) throws -> CommandBehavior {
    guard !arguments.isEmpty else {
        return .showHelp
    }

    let parsed = try parseRawArguments(arguments)

    if parsed.flags.contains("--help") || parsed.flags.contains("-h") {
        return .showHelp
    }

    let applicationSelector = parsed.values["--app"].map(ApplicationSelector.init(rawValue:))
    let windowSelection = try parseWindowSelection(parsed)
    let windowCrop = try parseWindowCrop(parsed.values["--window-crop"])
    let wantsWindowList = parsed.flags.contains("--list-windows")
    let outputPath = parsed.values["--output"]

    if windowSelection != nil, applicationSelector == nil {
        throw RegionShotError.invalidArguments("Window selection requires `--app <name-or-pid>`.")
    }

    if windowCrop != nil, applicationSelector == nil {
        throw RegionShotError.invalidArguments("`--window-crop` requires `--app <name-or-pid>` and a specific window selection.")
    }

    if wantsWindowList, applicationSelector == nil {
        throw RegionShotError.invalidArguments("`--list-windows` requires `--app <name-or-pid>`.")
    }

    if wantsWindowList, windowSelection != nil {
        throw RegionShotError.invalidArguments("`--list-windows` cannot be combined with `--frontmost-window`, `--window-index`, or `--window-name`.")
    }

    if wantsWindowList, windowCrop != nil {
        throw RegionShotError.invalidArguments("`--list-windows` cannot be combined with `--window-crop`.")
    }

    if wantsWindowList, parsed.region != nil {
        throw RegionShotError.invalidArguments("`--list-windows` cannot be combined with rectangle coordinates.")
    }

    if wantsWindowList, outputPath != nil {
        throw RegionShotError.invalidArguments("`--list-windows` prints JSON to stdout and does not use `--output`.")
    }

    if parsed.region != nil, windowSelection != nil {
        throw RegionShotError.invalidArguments("Rectangle capture cannot be combined with specific window selection. Choose one capture mode.")
    }

    if parsed.region != nil, windowCrop != nil {
        throw RegionShotError.invalidArguments("Rectangle capture cannot be combined with `--window-crop`. `--window-crop` is relative to a selected app window.")
    }

    if windowCrop != nil, windowSelection == nil {
        throw RegionShotError.invalidArguments("`--window-crop` requires one of `--frontmost-window`, `--window-index`, or `--window-name`.")
    }

    if applicationSelector != nil, parsed.region == nil, windowSelection == nil, outputPath != nil {
        throw RegionShotError.invalidArguments("`--output` requires a capture mode. Use rectangle coordinates or one of `--frontmost-window`, `--window-index`, or `--window-name`. `--app` alone lists windows as JSON.")
    }

    if wantsWindowList || (applicationSelector != nil && parsed.region == nil && windowSelection == nil) {
        return .listWindows(
            ListWindowsCommand(
                applicationSelector: applicationSelector!
            )
        )
    }

    if parsed.region == nil, applicationSelector == nil {
        throw RegionShotError.invalidArguments("Missing rectangle arguments.")
    }

    let outputURL = try outputURL(from: outputPath)
    return .capture(
        CaptureCommand(
            region: parsed.region,
            outputURL: outputURL,
            applicationSelector: applicationSelector,
            windowSelection: windowSelection,
            windowCrop: windowCrop
        )
    )
}

private func parseRawArguments(_ arguments: [String]) throws -> ParsedArguments {
    var region: CaptureRegion?
    var trailingArguments = arguments

    if let positionalRegion = try parsePositionalRegion(arguments: arguments) {
        region = positionalRegion
        trailingArguments = Array(arguments.dropFirst(4))
    }

    let parsedOptions = try parseOptions(arguments: trailingArguments)
    if region != nil {
        return ParsedArguments(region: region, values: parsedOptions.values, flags: parsedOptions.flags)
    }

    let flaggedRegion = try parseFlaggedRegion(values: parsedOptions.values)
    return ParsedArguments(region: flaggedRegion, values: parsedOptions.values, flags: parsedOptions.flags)
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

private func parseOptions(arguments: [String]) throws -> (values: [String: String], flags: Set<String>) {
    var values: [String: String] = [:]
    var flags: Set<String> = []
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]

        switch argument {
        case "--help", "-h", "--list-windows", "--frontmost-window":
            flags.insert(argument)
            index += 1
        case "--x", "--y", "--width", "--height", "--output", "--app", "--window-index", "--window-name", "--window-crop":
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

    return (values, flags)
}

private func parseFlaggedRegion(values: [String: String]) throws -> CaptureRegion? {
    let rectangleKeys = ["--x", "--y", "--width", "--height"]
    let presentKeys = rectangleKeys.filter { values[$0] != nil }

    if presentKeys.isEmpty {
        return nil
    }

    guard presentKeys.count == rectangleKeys.count else {
        throw RegionShotError.invalidArguments("Expected all of `--x`, `--y`, `--width`, and `--height` when using flagged rectangle coordinates.")
    }

    let region = try CaptureRegion(
        x: parseInteger(values["--x"]!, flag: "--x"),
        y: parseInteger(values["--y"]!, flag: "--y"),
        width: parseInteger(values["--width"]!, flag: "--width"),
        height: parseInteger(values["--height"]!, flag: "--height")
    )

    try validate(region: region)
    return region
}

private func parseWindowSelection(_ parsed: ParsedArguments) throws -> WindowSelection? {
    var selections: [WindowSelection] = []

    if parsed.flags.contains("--frontmost-window") {
        selections.append(.frontmost)
    }

    if let rawIndex = parsed.values["--window-index"] {
        let index = try parseInteger(rawIndex, flag: "--window-index")
        guard index >= 0 else {
            throw RegionShotError.invalidArguments("`--window-index` must be zero or greater.")
        }
        selections.append(.index(index))
    }

    if let windowName = parsed.values["--window-name"] {
        let trimmed = windowName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RegionShotError.invalidArguments("`--window-name` requires a non-empty title.")
        }
        selections.append(.name(trimmed))
    }

    guard selections.count <= 1 else {
        throw RegionShotError.invalidArguments("Choose only one of `--frontmost-window`, `--window-index`, or `--window-name`.")
    }

    return selections.first
}

private func parseWindowCrop(_ rawValue: String?) throws -> WindowCropRect? {
    guard let rawValue else {
        return nil
    }

    let components = rawValue
        .split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    guard components.count == 4 else {
        throw RegionShotError.invalidArguments("`--window-crop` must use `x,y,width,height`.")
    }

    let crop = try WindowCropRect(
        x: parseInteger(components[0], flag: "--window-crop"),
        y: parseInteger(components[1], flag: "--window-crop"),
        width: parseInteger(components[2], flag: "--window-crop"),
        height: parseInteger(components[3], flag: "--window-crop")
    )

    guard crop.x >= 0, crop.y >= 0 else {
        throw RegionShotError.invalidArguments("`--window-crop` requires non-negative x and y coordinates.")
    }

    guard crop.width > 0, crop.height > 0 else {
        throw RegionShotError.invalidArguments("`--window-crop` width and height must be greater than zero.")
    }

    return crop
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

private func capture(using command: CaptureCommand) async throws {
    let directoryURL = command.outputURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    if let applicationSelector = command.applicationSelector {
        guard #available(macOS 14.0, *) else {
            throw RegionShotError.unsupportedFeature("App-filtered capture requires macOS 14 or newer.")
        }

        let shareableContent = try await loadShareableContent()
        let catalog = try buildWindowCatalog(selector: applicationSelector, in: shareableContent)

        if let windowSelection = command.windowSelection {
            let window = try selectWindow(from: catalog, using: windowSelection)
            try await captureWindow(window, crop: command.windowCrop, outputURL: command.outputURL)
            return
        }

        guard let region = command.region else {
            throw RegionShotError.invalidArguments("App-filtered rectangle capture requires rectangle coordinates.")
        }

        try await captureApplicationRegion(
            application: catalog.application,
            windows: catalog.windows.map(\.scWindow),
            displays: shareableContent.displays,
            region: region,
            outputURL: command.outputURL
        )
        return
    }

    guard let region = command.region else {
        throw RegionShotError.invalidArguments("Rectangle capture requires coordinates when no app is specified.")
    }

    try captureScreenRegion(region: region, outputURL: command.outputURL)
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

private func listWindows(using command: ListWindowsCommand) async throws -> String {
    guard #available(macOS 14.0, *) else {
        throw RegionShotError.unsupportedFeature("Window inspection requires macOS 14 or newer.")
    }

    let shareableContent = try await loadShareableContent()
    let catalog = try buildWindowCatalog(selector: command.applicationSelector, in: shareableContent)

    let response = WindowListResponse(
        application: WindowListApplication(
            name: catalog.application.applicationName,
            bundleIdentifier: catalog.application.bundleIdentifier,
            processID: catalog.application.processID
        ),
        windows: catalog.windows.map {
            WindowListEntry(
                index: $0.index,
                windowID: $0.windowID,
                title: normalizedTitle($0.title),
                frame: JSONRect($0.frame),
                layer: $0.layer,
                isOnScreen: $0.isOnScreen,
                isActive: $0.isActive
            )
        }
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(response)

    guard let json = String(data: data, encoding: .utf8) else {
        throw RegionShotError.encodeFailed("Failed to encode the window list as UTF-8 JSON.")
    }

    return json
}

@available(macOS 14.0, *)
private func loadShareableContent() async throws -> SCShareableContent {
    try ensureScreenCaptureAccess()
    return try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
}

@available(macOS 14.0, *)
private func buildWindowCatalog(selector: ApplicationSelector, in shareableContent: SCShareableContent) throws -> AppWindowCatalog {
    let application = try resolveApplication(selector: selector, in: shareableContent.applications)
    let eligibleWindows = shareableContent.windows.filter {
        $0.owningApplication?.processID == application.processID &&
        !$0.frame.isEmpty &&
        ($0.isOnScreen || $0.isActive)
    }

    guard !eligibleWindows.isEmpty else {
        throw RegionShotError.windowNotFound("No capturable windows are currently available for `\(application.applicationName)`.")
    }

    let windowsByID = Dictionary(uniqueKeysWithValues: eligibleWindows.map { ($0.windowID, $0) })
    let orderedSnapshots = currentWindowSnapshots().filter { $0.ownerPID == application.processID }

    var orderedWindows: [CatalogWindow] = []
    var seenWindowIDs: Set<CGWindowID> = []

    for snapshot in orderedSnapshots {
        guard let scWindow = windowsByID[snapshot.windowID] else {
            continue
        }

        let catalogWindow = CatalogWindow(
            index: orderedWindows.count,
            windowID: scWindow.windowID,
            title: normalizedTitle(scWindow.title) ?? normalizedTitle(snapshot.title),
            frame: scWindow.frame,
            layer: scWindow.windowLayer,
            isOnScreen: scWindow.isOnScreen,
            isActive: scWindow.isActive,
            scWindow: scWindow
        )

        orderedWindows.append(catalogWindow)
        seenWindowIDs.insert(scWindow.windowID)
    }

    let fallbackWindows = eligibleWindows
        .filter { !seenWindowIDs.contains($0.windowID) }
        .sorted {
            let leftTitle = normalizedTitle($0.title) ?? ""
            let rightTitle = normalizedTitle($1.title) ?? ""

            if leftTitle != rightTitle {
                return leftTitle.localizedCaseInsensitiveCompare(rightTitle) == .orderedAscending
            }

            return $0.windowID < $1.windowID
        }

    for scWindow in fallbackWindows {
        orderedWindows.append(
            CatalogWindow(
                index: orderedWindows.count,
                windowID: scWindow.windowID,
                title: normalizedTitle(scWindow.title),
                frame: scWindow.frame,
                layer: scWindow.windowLayer,
                isOnScreen: scWindow.isOnScreen,
                isActive: scWindow.isActive,
                scWindow: scWindow
            )
        )
    }

    return AppWindowCatalog(application: application, windows: orderedWindows)
}

private func currentWindowSnapshots() -> [WindowSnapshot] {
    let rawWindowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

    return rawWindowInfo.compactMap { entry -> WindowSnapshot? in
        guard
            let windowNumber = entry[kCGWindowNumber as String] as? NSNumber,
            let ownerPID = entry[kCGWindowOwnerPID as String] as? NSNumber,
            let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
            let layer = entry[kCGWindowLayer as String] as? NSNumber
        else {
            return nil
        }

        guard let bounds = CGRect(dictionaryRepresentation: boundsDictionary), !bounds.isEmpty else {
            return nil
        }

        return WindowSnapshot(
            windowID: CGWindowID(truncating: windowNumber),
            ownerPID: pid_t(truncating: ownerPID),
            title: normalizedTitle(entry[kCGWindowName as String] as? String),
            bounds: bounds,
            layer: layer.intValue
        )
    }
}

@available(macOS 14.0, *)
private func resolveApplication(selector: ApplicationSelector, in applications: [SCRunningApplication]) throws -> SCRunningApplication {
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
private func selectWindow(from catalog: AppWindowCatalog, using selection: WindowSelection) throws -> CatalogWindow {
    switch selection {
    case .frontmost:
        guard let window = catalog.windows.first else {
            throw RegionShotError.windowNotFound("`\(catalog.application.applicationName)` has no capturable windows.")
        }
        return window
    case .index(let index):
        guard let window = catalog.windows.first(where: { $0.index == index }) else {
            throw RegionShotError.windowNotFound("No window at index \(index) for `\(catalog.application.applicationName)`. Run `regionshot --app \"\(catalog.application.applicationName)\" --list-windows` to inspect available windows.")
        }
        return window
    case .name(let query):
        let normalizedQuery = query.lowercased()
        let exactMatches = catalog.windows.filter { ($0.title ?? "").lowercased() == normalizedQuery }

        if exactMatches.count == 1, let match = exactMatches.first {
            return match
        }

        let partialMatches = catalog.windows.filter { ($0.title ?? "").lowercased().contains(normalizedQuery) }
        let matches = exactMatches.isEmpty ? partialMatches : exactMatches

        guard !matches.isEmpty else {
            throw RegionShotError.windowNotFound("No window named `\(query)` was found for `\(catalog.application.applicationName)`. Run `regionshot --app \"\(catalog.application.applicationName)\" --list-windows` to inspect available windows.")
        }

        guard matches.count == 1, let match = matches.first else {
            let suggestions = matches
                .prefix(5)
                .map { "[\($0.index)] \(displayTitle($0.title))" }
                .joined(separator: ", ")
            throw RegionShotError.ambiguousWindow("More than one window matches `\(query)`: \(suggestions)")
        }

        return match
    }
}

@available(macOS 14.0, *)
private func captureWindow(_ window: CatalogWindow, crop: WindowCropRect?, outputURL: URL) async throws {
    let filter = SCContentFilter(desktopIndependentWindow: window.scWindow)
    let info = SCShareableContent.info(for: filter)
    let clearBackgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
    let configuration = SCStreamConfiguration()

    configuration.width = max(1, Int(ceil(info.contentRect.width * CGFloat(info.pointPixelScale))))
    configuration.height = max(1, Int(ceil(info.contentRect.height * CGFloat(info.pointPixelScale))))
    configuration.showsCursor = false
    configuration.scalesToFit = false
    configuration.backgroundColor = clearBackgroundColor
    configuration.ignoreShadowsSingleWindow = true
    configuration.ignoreGlobalClipSingleWindow = true

    let capturedImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)

    let finalImage: CGImage
    if let crop {
        try validate(windowCrop: crop, within: info.contentRect, windowTitle: displayTitle(window.title))
        finalImage = try cropWindowImage(capturedImage, using: crop, pointPixelScale: CGFloat(info.pointPixelScale))
    } else {
        finalImage = capturedImage
    }

    try writePNG(image: finalImage, to: outputURL)
}

@available(macOS 14.0, *)
private func captureApplicationRegion(
    application: SCRunningApplication,
    windows: [SCWindow],
    displays: [SCDisplay],
    region: CaptureRegion,
    outputURL: URL
) async throws {
    let regionRect = region.rect
    let plans = planDisplayCaptures(
        displays: displays,
        windows: windows,
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
        let clearBackgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
        let configuration = SCStreamConfiguration()

        configuration.width = max(1, Int(ceil(plan.intersectionRect.width * plan.pointPixelScale)))
        configuration.height = max(1, Int(ceil(plan.intersectionRect.height * plan.pointPixelScale)))
        configuration.sourceRect = CGRect(
            x: plan.intersectionRect.minX - plan.display.frame.minX,
            y: plan.intersectionRect.minY - plan.display.frame.minY,
            width: plan.intersectionRect.width,
            height: plan.intersectionRect.height
        )
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
private func planDisplayCaptures(
    displays: [SCDisplay],
    windows: [SCWindow],
    regionRect: CGRect
) -> [DisplayCapturePlan] {
    displays.compactMap { display in
        let intersectionRect = display.frame.intersection(regionRect)
        guard !intersectionRect.isNull, !intersectionRect.isEmpty else {
            return nil
        }

        let hasWindowContent = windows.contains { window in
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

private func validate(windowCrop: WindowCropRect, within contentRect: CGRect, windowTitle: String) throws {
    let cropRect = windowCrop.rect
    let windowRect = CGRect(origin: .zero, size: contentRect.size)

    guard cropRect.maxX <= windowRect.maxX, cropRect.maxY <= windowRect.maxY else {
        let windowWidth = Int(windowRect.width.rounded(.down))
        let windowHeight = Int(windowRect.height.rounded(.down))
        throw RegionShotError.invalidArguments("`--window-crop` \(windowCrop.x),\(windowCrop.y),\(windowCrop.width),\(windowCrop.height) falls outside the selected window \(windowTitle) sized \(windowWidth)x\(windowHeight) points.")
    }
}

private func cropWindowImage(_ image: CGImage, using crop: WindowCropRect, pointPixelScale: CGFloat) throws -> CGImage {
    let scale = max(1, pointPixelScale)
    let minX = max(0, Int(floor(CGFloat(crop.x) * scale)))
    let minY = max(0, Int(floor(CGFloat(crop.y) * scale)))
    let maxX = min(image.width, Int(ceil(CGFloat(crop.x + crop.width) * scale)))
    let maxY = min(image.height, Int(ceil(CGFloat(crop.y + crop.height) * scale)))
    let croppedWidth = maxX - minX
    let croppedHeight = maxY - minY

    guard croppedWidth > 0, croppedHeight > 0 else {
        throw RegionShotError.captureFailed("`--window-crop` resolved to an empty image.")
    }

    let cropRect = CGRect(x: minX, y: minY, width: croppedWidth, height: croppedHeight)
    guard let croppedImage = image.cropping(to: cropRect) else {
        throw RegionShotError.captureFailed("Failed to crop the selected window image.")
    }

    return croppedImage
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

private func normalizedTitle(_ title: String?) -> String? {
    guard let title else {
        return nil
    }

    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func displayTitle(_ title: String?) -> String {
    normalizedTitle(title) ?? "<untitled>"
}

private func writeStandardError(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}
