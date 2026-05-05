import Darwin
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

@main
struct RegionShot {
    static func main() async {
        synchronizeCodexIntegrationIfAvailable()

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
            case .inspectAccessibility(let command):
                let json = try await inspectAccessibility(using: command)
                print(json)
            case .menuBar(let command):
                let result = try await handleMenuBar(using: command)
                print(result)
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
    case inspectAccessibility(AccessibilityCommand)
    case menuBar(MenuBarCommand)
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

private struct AccessibilityCommand: Sendable {
    let applicationSelector: ApplicationSelector
    let windowSelection: WindowSelection?
    let mode: AccessibilityMode
}

private struct MenuBarCommand: Sendable {
    let applicationSelector: ApplicationSelector
    let selection: MenuBarSelection?
    let mode: MenuBarMode
    let outputURL: URL?
}

private struct AccessibilitySelector: Sendable {
    let role: String?
    let subrole: String?
    let title: String?
    let identifier: String?
    let elementDescription: String?

    var isEmpty: Bool {
        role == nil &&
        subrole == nil &&
        title == nil &&
        identifier == nil &&
        elementDescription == nil
    }
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

private struct WindowPoint: Sendable {
    let x: Int
    let y: Int

    var point: CGPoint {
        CGPoint(x: x, y: y)
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

private enum AccessibilityMode: Sendable {
    case listElements
    case elementAt(WindowPoint)
    case pressAt(WindowPoint)
    case pressElement(AccessibilitySelector)
}

private enum MenuBarMode: Sendable {
    case listItems
    case pressItem
    case captureMenu
}

private enum MenuBarSelection: Sendable {
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

private struct AutomationApplication {
    let name: String
    let bundleIdentifier: String
    let processID: pid_t
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

private struct AccessibilityWindowCatalog {
    let application: AutomationApplication
    let windows: [AccessibilityCatalogWindow]
}

private struct MenuBarItemCatalog {
    let application: AutomationApplication
    let items: [MenuBarCatalogItem]
}

private struct AccessibilityCatalogWindow {
    let index: Int
    let title: String?
    let frame: CGRect
    let isFocused: Bool
    let isMain: Bool
    let element: AXUIElement
}

private struct MenuBarCatalogItem {
    let index: Int
    let source: String
    let role: String?
    let subrole: String?
    let title: String?
    let description: String?
    let identifier: String?
    let frame: CGRect?
    let actions: [String]
    let childCount: Int
    let element: AXUIElement
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

private struct JSONPoint: Encodable {
    let x: Double
    let y: Double

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }
}

private struct AccessibilityTreeResponse: Encodable {
    let application: WindowListApplication
    let window: AccessibilityWindowEntry
    let tree: AccessibilityElementResponse
}

private struct AccessibilityHitResponse: Encodable {
    let application: WindowListApplication
    let window: AccessibilityWindowEntry
    let point: JSONPoint
    let screenPoint: JSONPoint
    let hit: AccessibilityElementResponse
    let ancestors: [AccessibilityElementResponse]
}

private struct AccessibilitySelectorResponse: Encodable {
    let role: String?
    let subrole: String?
    let title: String?
    let identifier: String?
    let description: String?
}

private struct AccessibilityPressResponse: Encodable {
    let application: WindowListApplication
    let window: AccessibilityWindowEntry
    let mode: String
    let action: String
    let selector: AccessibilitySelectorResponse?
    let point: JSONPoint?
    let screenPoint: JSONPoint?
    let matched: AccessibilityElementResponse
    let pressed: AccessibilityElementResponse
    let ancestors: [AccessibilityElementResponse]
}

private struct AccessibilityWindowEntry: Encodable {
    let index: Int
    let title: String?
    let frame: JSONRect
    let isFocused: Bool
    let isMain: Bool
}

private struct AccessibilityElementResponse: Encodable {
    let role: String?
    let subrole: String?
    let title: String?
    let description: String?
    let identifier: String?
    let frame: JSONRect?
    let actions: [String]
    let childCount: Int?
    let truncated: Bool?
    let children: [AccessibilityElementResponse]?
}

private struct MenuBarListResponse: Encodable {
    let application: WindowListApplication
    let items: [MenuBarItemEntry]
}

private struct MenuBarPressResponse: Encodable {
    let application: WindowListApplication
    let item: MenuBarItemEntry
    let action: String
    let menu: AccessibilityElementResponse?
}

private struct MenuBarItemEntry: Encodable {
    let index: Int
    let source: String
    let role: String?
    let subrole: String?
    let title: String?
    let description: String?
    let identifier: String?
    let frame: JSONRect?
    let actions: [String]
    let childCount: Int
}

private enum MenuBarSurface {
    case menu(AXUIElement)
    case window(CGRect)

    var frame: CGRect? {
        switch self {
        case .menu(let element):
            return copyAXFrame(from: element)
        case .window(let rect):
            return rect
        }
    }
}

private struct AccessibilityElementCandidate {
    let element: AXUIElement
    let depth: Int
    let role: String?
    let subrole: String?
    let title: String?
    let description: String?
    let identifier: String?
    let frame: CGRect?
    let actions: [String]
}

private enum RegionShotError: LocalizedError {
    case invalidArguments(String)
    case invalidInteger(flag: String, value: String)
    case invalidRegion(String)
    case unsupportedFeature(String)
    case capturePermissionDenied
    case accessibilityPermissionDenied
    case applicationNotFound(String)
    case ambiguousApplication(String)
    case windowNotFound(String)
    case ambiguousWindow(String)
    case captureFailed(String)
    case accessibilityQueryFailed(String)
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
            return "Screen Recording permission is required for app/window inspection and capture. Grant access and run the command again."
        case .accessibilityPermissionDenied:
            return "Accessibility permission is required for accessibility inspection and actions. Grant access and run the command again."
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
        case .accessibilityQueryFailed(let message):
            return message
        case .encodeFailed(let message):
            return message
        }
    }

    var exitCode: Int32 {
        switch self {
        case .invalidArguments, .invalidInteger, .invalidRegion:
            return 64
        case .unsupportedFeature, .capturePermissionDenied, .accessibilityPermissionDenied, .applicationNotFound, .ambiguousApplication, .windowNotFound, .ambiguousWindow, .captureFailed, .accessibilityQueryFailed, .encodeFailed:
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
  regionshot --app APP --list-menu-bar-items
  regionshot --app APP --capture-menu [--output FILE]
  regionshot --app APP --menu-bar-index N --press
  regionshot --app APP --menu-bar-index N --capture-menu [--output FILE]
  regionshot --app APP --menu-bar-item TEXT --press
  regionshot --app APP --menu-bar-item TEXT --capture-menu [--output FILE]
  regionshot --app APP --list-elements
  regionshot --app APP --press --role ROLE [--subrole SUBROLE] [--title TITLE] [--identifier ID] [--description TEXT]
  regionshot --app APP --press-at X,Y
  regionshot --app APP --element-at X,Y
  regionshot --app APP --frontmost-window --list-elements
  regionshot --app APP --window-index N --list-elements
  regionshot --app APP --window-name TITLE --list-elements
  regionshot --app APP --frontmost-window --press --role ROLE [--subrole SUBROLE] [--title TITLE] [--identifier ID] [--description TEXT]
  regionshot --app APP --window-index N --press --role ROLE [--subrole SUBROLE] [--title TITLE] [--identifier ID] [--description TEXT]
  regionshot --app APP --window-name TITLE --press --role ROLE [--subrole SUBROLE] [--title TITLE] [--identifier ID] [--description TEXT]
  regionshot --app APP --frontmost-window --press-at X,Y
  regionshot --app APP --window-index N --press-at X,Y
  regionshot --app APP --window-name TITLE --press-at X,Y
  regionshot --app APP --frontmost-window --element-at X,Y
  regionshot --app APP --window-index N --element-at X,Y
  regionshot --app APP --window-name TITLE --element-at X,Y

Rules:
  `--app` accepts app name, bundle id, or pid
  `--app` alone == inspect mode == same as `--list-windows`
  window list JSON includes frontmost-first indices, titles, and bounds
  menu-bar item list JSON includes status-item/app-menu indices, roles, actions, and bounds
  `--capture-menu` opens the selected menu-bar item, captures the visible menu or popover, and closes it
  `--window-crop` is relative to the selected window's top-left in points
  prefer selector-based `--press` (alias: `--press-element`); use `--press-at` as fallback
  accessibility modes default to the app's focused window, then main window, then first window
  `--frontmost-window`, `--window-index`, or `--window-name` can override that default for accessibility modes
  `--element-at` and `--press-at` use window-relative x,y coordinates in points
  selector fields: `--role`, `--subrole`, `--title`, `--identifier`, `--description`
  `--title`, `--identifier`, and `--description` prefer exact matches, then fall back to case-insensitive contains
  capture and ScreenCaptureKit window listing require Screen Recording permission
  accessibility inspection and actions require Accessibility permission
  rectangle mode without `--app` forwards to `screencapture -R`
  rectangle mode with `--app` includes only that app, even if covered by other windows
  app/window modes target app windows; use menu-bar modes for status-item UI from accessory/background apps
"""

private let codexSkillName = "regionshot"
private let codexManagedAgentsStartMarker = "<!-- regionshot-managed:start -->"
private let codexManagedAgentsEndMarker = "<!-- regionshot-managed:end -->"

private func synchronizeCodexIntegrationIfAvailable() {
    do {
        try installOrUpdateCodexIntegrationIfAvailable()
    } catch {
        if ProcessInfo.processInfo.environment["REGIONSHOT_DEBUG_CODEX_SYNC"] == "1" {
            writeStandardError("warning: failed to sync Codex support files: \(error.localizedDescription)\n")
        }
    }
}

private func installOrUpdateCodexIntegrationIfAvailable() throws {
    guard let codexSourceDirectory = findCodexSupportDirectory() else {
        return
    }

    let skillSourceDirectory = codexSourceDirectory
        .appendingPathComponent("skills", isDirectory: true)
        .appendingPathComponent(codexSkillName, isDirectory: true)
    let pointerSourceURL = codexSourceDirectory.appendingPathComponent("AGENTS.pointer.md")

    let fileManager = FileManager.default
    guard
        fileManager.fileExists(atPath: skillSourceDirectory.appendingPathComponent("SKILL.md").path),
        fileManager.fileExists(atPath: pointerSourceURL.path)
    else {
        return
    }

    let codexHomeDirectory = fileManager.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex", isDirectory: true)
    let skillDestinationDirectory = codexHomeDirectory
        .appendingPathComponent("skills", isDirectory: true)
        .appendingPathComponent(codexSkillName, isDirectory: true)
    let agentsDestinationURL = codexHomeDirectory.appendingPathComponent("AGENTS.md")

    try syncDirectoryIfNeeded(from: skillSourceDirectory, to: skillDestinationDirectory)

    let pointerBody = try String(contentsOf: pointerSourceURL, encoding: .utf8)
    try upsertManagedAgentsPointer(pointerBody, at: agentsDestinationURL)
}

private func findCodexSupportDirectory() -> URL? {
    let fileManager = FileManager.default

    for candidate in codexSupportCandidates() {
        let standardizedCandidate = candidate.standardizedFileURL
        guard fileManager.fileExists(atPath: standardizedCandidate.path) else {
            continue
        }

        let skillDirectory = standardizedCandidate
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent(codexSkillName, isDirectory: true)
        let skillFileURL = skillDirectory.appendingPathComponent("SKILL.md")
        let pointerFileURL = standardizedCandidate.appendingPathComponent("AGENTS.pointer.md")

        if fileManager.fileExists(atPath: skillFileURL.path), fileManager.fileExists(atPath: pointerFileURL.path) {
            return standardizedCandidate
        }
    }

    return nil
}

private func codexSupportCandidates() -> [URL] {
    var candidates: [URL] = []

    if let executableDirectory = currentExecutableURL()?.deletingLastPathComponent() {
        candidates.append(
            executableDirectory
                .appendingPathComponent(".regionshot-support", isDirectory: true)
                .appendingPathComponent("Codex", isDirectory: true)
        )
        appendAncestorCodexDirectories(startingAt: executableDirectory, to: &candidates)
    }

    let currentDirectory = URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath,
        isDirectory: true
    )
    appendAncestorCodexDirectories(startingAt: currentDirectory, to: &candidates)

    var deduplicated: [URL] = []
    var seenPaths: Set<String> = []
    for candidate in candidates {
        let path = candidate.standardizedFileURL.path
        if seenPaths.insert(path).inserted {
            deduplicated.append(candidate.standardizedFileURL)
        }
    }

    return deduplicated
}

private func appendAncestorCodexDirectories(startingAt directory: URL, to candidates: inout [URL]) {
    var currentPath = directory.standardizedFileURL.path

    while true {
        let currentDirectoryURL = URL(fileURLWithPath: currentPath, isDirectory: true)
        candidates.append(currentDirectoryURL.appendingPathComponent("Codex", isDirectory: true))

        let parentPath = (currentPath as NSString).deletingLastPathComponent
        if parentPath.isEmpty || parentPath == currentPath {
            break
        }

        currentPath = parentPath
    }
}

private func currentExecutableURL() -> URL? {
    var size: UInt32 = 0
    _ = _NSGetExecutablePath(nil, &size)

    var buffer = [CChar](repeating: 0, count: Int(size))
    guard _NSGetExecutablePath(&buffer, &size) == 0 else {
        return nil
    }

    let executablePathBytes = buffer
        .prefix { $0 != 0 }
        .map { UInt8(bitPattern: $0) }
    let executablePath = String(decoding: executablePathBytes, as: UTF8.self)

    return URL(fileURLWithPath: executablePath)
        .resolvingSymlinksInPath()
        .standardizedFileURL
}

private func syncDirectoryIfNeeded(from sourceDirectory: URL, to destinationDirectory: URL) throws {
    let fileManager = FileManager.default

    if try directoriesMatch(sourceDirectory, destinationDirectory) {
        return
    }

    try fileManager.createDirectory(
        at: destinationDirectory.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    if fileManager.fileExists(atPath: destinationDirectory.path) {
        try fileManager.removeItem(at: destinationDirectory)
    }

    try fileManager.copyItem(at: sourceDirectory, to: destinationDirectory)
}

private func directoriesMatch(_ sourceDirectory: URL, _ destinationDirectory: URL) throws -> Bool {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false

    guard fileManager.fileExists(atPath: destinationDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        return false
    }

    let sourceFiles = try regularFiles(in: sourceDirectory)
    let destinationFiles = try regularFiles(in: destinationDirectory)
    guard sourceFiles == destinationFiles else {
        return false
    }

    for relativePath in sourceFiles {
        let sourceFileURL = sourceDirectory.appendingPathComponent(relativePath)
        let destinationFileURL = destinationDirectory.appendingPathComponent(relativePath)

        if !fileManager.contentsEqual(atPath: sourceFileURL.path, andPath: destinationFileURL.path) {
            return false
        }
    }

    return true
}

private func regularFiles(in directory: URL) throws -> [String] {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    let directoryPathPrefix = directory.standardizedFileURL.path + "/"
    var files: [String] = []

    for case let fileURL as URL in enumerator {
        let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
        guard resourceValues.isRegularFile == true else {
            continue
        }

        let filePath = fileURL.standardizedFileURL.path
        if filePath.hasPrefix(directoryPathPrefix) {
            files.append(String(filePath.dropFirst(directoryPathPrefix.count)))
        }
    }

    return files.sorted()
}

private func upsertManagedAgentsPointer(_ pointerBody: String, at agentsURL: URL) throws {
    let trimmedPointerBody = pointerBody.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPointerBody.isEmpty else {
        return
    }

    let managedBlock = """
    \(codexManagedAgentsStartMarker)
    \(trimmedPointerBody)
    \(codexManagedAgentsEndMarker)
    """

    let fileManager = FileManager.default
    let existingContents = (try? String(contentsOf: agentsURL, encoding: .utf8)) ?? ""
    let updatedContents = updatedAgentsContents(
        from: existingContents,
        managedBlock: managedBlock,
        legacyPointerBody: trimmedPointerBody
    )

    guard updatedContents != existingContents else {
        return
    }

    try fileManager.createDirectory(
        at: agentsURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try updatedContents.write(to: agentsURL, atomically: true, encoding: .utf8)
}

private func updatedAgentsContents(
    from existingContents: String,
    managedBlock: String,
    legacyPointerBody: String
) -> String {
    let normalizedExistingContents = normalizeManagedText(existingContents)
    let legacyStandaloneContents = normalizeManagedText("""
    # User Environment Notes

    \(legacyPointerBody)
    """)

    if normalizedExistingContents.isEmpty || normalizedExistingContents == legacyStandaloneContents {
        return """
        # User Environment Notes

        \(managedBlock)
        """
    }

    if let managedRange = managedAgentsRange(in: existingContents) {
        var updatedContents = existingContents
        updatedContents.replaceSubrange(managedRange, with: managedBlock)
        return ensureTrailingNewline(in: updatedContents)
    }

    return ensureTrailingNewline(in: existingContents) + "\n\(managedBlock)\n"
}

private func managedAgentsRange(in contents: String) -> Range<String.Index>? {
    guard let startRange = contents.range(of: codexManagedAgentsStartMarker) else {
        return nil
    }

    guard let endRange = contents.range(of: codexManagedAgentsEndMarker, range: startRange.upperBound..<contents.endIndex) else {
        return nil
    }

    return startRange.lowerBound..<endRange.upperBound
}

private func normalizeManagedText(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\r\n", with: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func ensureTrailingNewline(in value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "" : trimmed + "\n"
}

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
    let wantsMenuBarList = parsed.flags.contains("--list-menu-bar-items")
    let wantsCaptureMenu = parsed.flags.contains("--capture-menu")
    let menuBarSelection = try parseMenuBarSelection(parsed)
    let wantsElementList = parsed.flags.contains("--list-elements")
    let wantsPress = parsed.flags.contains("--press") || parsed.flags.contains("--press-element")
    let wantsMenuBarPress = wantsPress && menuBarSelection != nil
    let wantsAccessibilityPress = wantsPress && !wantsMenuBarPress
    let elementPoint = try parseWindowPoint(parsed.values["--element-at"], flag: "--element-at")
    let pressPoint = try parseWindowPoint(parsed.values["--press-at"], flag: "--press-at")
    let selector = parseAccessibilitySelector(from: parsed.values)
    let outputPath = parsed.values["--output"]

    let accessibilityModeCount = [
        wantsElementList ? 1 : 0,
        elementPoint != nil ? 1 : 0,
        wantsAccessibilityPress ? 1 : 0,
        pressPoint != nil ? 1 : 0,
    ].reduce(0, +)

    if accessibilityModeCount > 1 {
        throw RegionShotError.invalidArguments("Choose only one of `--list-elements`, `--element-at`, `--press`/`--press-element`, or `--press-at`.")
    }

    let menuBarModeCount = [
        wantsMenuBarList ? 1 : 0,
        wantsMenuBarPress ? 1 : 0,
        wantsCaptureMenu ? 1 : 0,
    ].reduce(0, +)

    if menuBarModeCount > 1 {
        throw RegionShotError.invalidArguments("Choose only one of `--list-menu-bar-items`, menu-bar `--press`, or `--capture-menu`.")
    }

    let accessibilityMode: AccessibilityMode?
    if wantsElementList {
        accessibilityMode = .listElements
    } else if let elementPoint {
        accessibilityMode = .elementAt(elementPoint)
    } else if wantsAccessibilityPress {
        accessibilityMode = .pressElement(selector)
    } else if let pressPoint {
        accessibilityMode = .pressAt(pressPoint)
    } else {
        accessibilityMode = nil
    }

    let menuBarMode: MenuBarMode?
    if wantsMenuBarList {
        menuBarMode = .listItems
    } else if wantsMenuBarPress {
        menuBarMode = .pressItem
    } else if wantsCaptureMenu {
        menuBarMode = .captureMenu
    } else {
        menuBarMode = nil
    }

    if windowSelection != nil, applicationSelector == nil {
        throw RegionShotError.invalidArguments("Window selection requires `--app <name-or-pid>`.")
    }

    if windowCrop != nil, applicationSelector == nil {
        throw RegionShotError.invalidArguments("`--window-crop` requires `--app <name-or-pid>` and a specific window selection.")
    }

    if wantsWindowList, applicationSelector == nil {
        throw RegionShotError.invalidArguments("`--list-windows` requires `--app <name-or-pid>`.")
    }

    if menuBarMode != nil, applicationSelector == nil {
        throw RegionShotError.invalidArguments("Menu-bar inspection and actions require `--app <name-or-pid>`.")
    }

    if accessibilityMode != nil, applicationSelector == nil {
        throw RegionShotError.invalidArguments("Accessibility inspection and actions require `--app <name-or-pid>`.")
    }

    if wantsWindowList, windowSelection != nil {
        throw RegionShotError.invalidArguments("`--list-windows` cannot be combined with `--frontmost-window`, `--window-index`, or `--window-name`.")
    }

    if wantsWindowList, accessibilityMode != nil {
        throw RegionShotError.invalidArguments("`--list-windows` cannot be combined with accessibility inspection or action flags.")
    }

    if wantsWindowList, menuBarMode != nil {
        throw RegionShotError.invalidArguments("`--list-windows` cannot be combined with menu-bar inspection or action flags.")
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

    if menuBarMode != nil, parsed.region != nil {
        throw RegionShotError.invalidArguments("Menu-bar inspection and actions cannot be combined with rectangle coordinates.")
    }

    if menuBarMode != nil, windowSelection != nil {
        throw RegionShotError.invalidArguments("Menu-bar inspection and actions cannot be combined with `--frontmost-window`, `--window-index`, or `--window-name`.")
    }

    if menuBarMode != nil, windowCrop != nil {
        throw RegionShotError.invalidArguments("Menu-bar inspection and actions cannot be combined with `--window-crop`.")
    }

    if menuBarMode != nil, accessibilityMode != nil {
        throw RegionShotError.invalidArguments("Menu-bar inspection and actions cannot be combined with window Accessibility inspection or action flags.")
    }

    if wantsMenuBarList, menuBarSelection != nil {
        throw RegionShotError.invalidArguments("`--list-menu-bar-items` cannot be combined with `--menu-bar-index` or `--menu-bar-item`.")
    }

    if wantsMenuBarList, outputPath != nil {
        throw RegionShotError.invalidArguments("`--list-menu-bar-items` prints JSON to stdout and does not use `--output`.")
    }

    if wantsMenuBarPress, outputPath != nil {
        throw RegionShotError.invalidArguments("Menu-bar `--press` prints JSON to stdout and does not use `--output`.")
    }

    if wantsMenuBarPress, !selector.isEmpty {
        throw RegionShotError.invalidArguments("Menu-bar `--press` cannot be combined with selector fields. Use `--menu-bar-index` or `--menu-bar-item` to select a menu-bar item.")
    }

    if menuBarSelection != nil, menuBarMode == nil {
        throw RegionShotError.invalidArguments("`--menu-bar-index` and `--menu-bar-item` require menu-bar `--press` or `--capture-menu`.")
    }

    if accessibilityMode != nil, parsed.region != nil {
        throw RegionShotError.invalidArguments("Accessibility inspection and actions cannot be combined with rectangle coordinates.")
    }

    if accessibilityMode != nil, windowCrop != nil {
        throw RegionShotError.invalidArguments("Accessibility inspection and actions cannot be combined with `--window-crop`.")
    }

    if accessibilityMode != nil, outputPath != nil {
        throw RegionShotError.invalidArguments("Accessibility inspection and actions print JSON to stdout and do not use `--output`.")
    }

    if wantsAccessibilityPress, selector.isEmpty {
        throw RegionShotError.invalidArguments("`--press` (alias: `--press-element`) requires at least one selector field: `--role`, `--subrole`, `--title`, `--identifier`, or `--description`.")
    }

    if !wantsAccessibilityPress, !selector.isEmpty {
        throw RegionShotError.invalidArguments("Selector fields require `--press` or `--press-element`.")
    }

    if pressPoint != nil, !selector.isEmpty {
        throw RegionShotError.invalidArguments("`--press-at` cannot be combined with selector fields.")
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

    if let menuBarMode {
        return .menuBar(
            MenuBarCommand(
                applicationSelector: applicationSelector!,
                selection: menuBarSelection,
                mode: menuBarMode,
                outputURL: wantsCaptureMenu ? try outputURL(from: outputPath) : nil
            )
        )
    }

    if applicationSelector != nil, parsed.region == nil, windowSelection == nil, outputPath != nil {
        throw RegionShotError.invalidArguments("`--output` requires a capture mode. Use rectangle coordinates or one of `--frontmost-window`, `--window-index`, or `--window-name`. `--app` alone lists windows as JSON.")
    }

    if wantsWindowList || (applicationSelector != nil && parsed.region == nil && windowSelection == nil && accessibilityMode == nil) {
        return .listWindows(
            ListWindowsCommand(
                applicationSelector: applicationSelector!
            )
        )
    }

    if let accessibilityMode {
        return .inspectAccessibility(
            AccessibilityCommand(
                applicationSelector: applicationSelector!,
                windowSelection: windowSelection,
                mode: accessibilityMode
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
        case "--help", "-h", "--list-windows", "--frontmost-window", "--list-elements", "--list-menu-bar-items", "--press", "--press-element", "--capture-menu":
            flags.insert(argument)
            index += 1
        case "--x", "--y", "--width", "--height", "--output", "--app", "--window-index", "--window-name", "--window-crop", "--menu-bar-index", "--menu-bar-item", "--element-at", "--press-at", "--role", "--subrole", "--title", "--identifier", "--description":
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

private func parseMenuBarSelection(_ parsed: ParsedArguments) throws -> MenuBarSelection? {
    var selections: [MenuBarSelection] = []

    if let rawIndex = parsed.values["--menu-bar-index"] {
        let index = try parseInteger(rawIndex, flag: "--menu-bar-index")
        guard index >= 0 else {
            throw RegionShotError.invalidArguments("`--menu-bar-index` must be zero or greater.")
        }
        selections.append(.index(index))
    }

    if let itemName = parsed.values["--menu-bar-item"] {
        let trimmed = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RegionShotError.invalidArguments("`--menu-bar-item` requires a non-empty title, description, or identifier.")
        }
        selections.append(.name(trimmed))
    }

    guard selections.count <= 1 else {
        throw RegionShotError.invalidArguments("Choose only one of `--menu-bar-index` or `--menu-bar-item`.")
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

private func parseWindowPoint(_ rawValue: String?, flag: String) throws -> WindowPoint? {
    guard let rawValue else {
        return nil
    }

    let components = rawValue
        .split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    guard components.count == 2 else {
        throw RegionShotError.invalidArguments("`\(flag)` must use `x,y`.")
    }

    let point = try WindowPoint(
        x: parseInteger(components[0], flag: flag),
        y: parseInteger(components[1], flag: flag)
    )

    guard point.x >= 0, point.y >= 0 else {
        throw RegionShotError.invalidArguments("`\(flag)` requires non-negative x and y coordinates.")
    }

    return point
}

private func parseAccessibilitySelector(from values: [String: String]) -> AccessibilitySelector {
    AccessibilitySelector(
        role: normalizedArgumentValue(values["--role"]),
        subrole: normalizedArgumentValue(values["--subrole"]),
        title: normalizedArgumentValue(values["--title"]),
        identifier: normalizedArgumentValue(values["--identifier"]),
        elementDescription: normalizedArgumentValue(values["--description"])
    )
}

private func normalizedArgumentValue(_ value: String?) -> String? {
    guard let value else {
        return nil
    }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
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
        application: windowListApplication(for: catalog.application),
        windows: catalog.windows.map(windowListEntry(for:))
    )

    return try encodeJSON(response)
}

private func inspectAccessibility(using command: AccessibilityCommand) async throws -> String {
    guard #available(macOS 14.0, *) else {
        throw RegionShotError.unsupportedFeature("Element inspection currently requires macOS 14 or newer.")
    }

    try ensureAccessibilityAccess(prompt: true)

    let catalog = try buildAccessibilityWindowCatalog(selector: command.applicationSelector)
    let selectedWindow = try selectAccessibilityWindow(from: catalog, using: command.windowSelection)
    let accessibilityWindow = selectedWindow.element

    switch command.mode {
    case .listElements:
        let response = AccessibilityTreeResponse(
            application: windowListApplication(for: catalog.application),
            window: accessibilityWindowEntry(for: selectedWindow),
            tree: accessibilityElementResponse(for: accessibilityWindow, depthRemaining: 4)
        )
        return try encodeJSON(response)
    case .elementAt(let point):
        try validate(windowPoint: point, within: selectedWindow.frame, windowTitle: displayTitle(selectedWindow.title), flag: "--element-at")

        let screenPoint = CGPoint(
            x: selectedWindow.frame.minX + CGFloat(point.x),
            y: selectedWindow.frame.minY + CGFloat(point.y)
        )

        let hitElement = try hitTestElement(at: screenPoint)
        try validateHitElement(
            hitElement,
            belongsTo: accessibilityWindow,
            selectedWindowTitle: selectedWindow.title
        )
        let refinedHitElement = deepestAccessibilityElement(
            in: accessibilityWindow,
            containing: screenPoint,
            depthRemaining: 8
        ) ?? hitElement

        let response = AccessibilityHitResponse(
            application: windowListApplication(for: catalog.application),
            window: accessibilityWindowEntry(for: selectedWindow),
            point: JSONPoint(point.point),
            screenPoint: JSONPoint(screenPoint),
            hit: accessibilityElementResponse(for: refinedHitElement, depthRemaining: 1),
            ancestors: accessibilityAncestorResponses(for: refinedHitElement, stoppingAt: accessibilityWindow)
        )
        return try encodeJSON(response)
    case .pressAt(let point):
        try validate(windowPoint: point, within: selectedWindow.frame, windowTitle: displayTitle(selectedWindow.title), flag: "--press-at")

        let screenPoint = CGPoint(
            x: selectedWindow.frame.minX + CGFloat(point.x),
            y: selectedWindow.frame.minY + CGFloat(point.y)
        )

        let hitElement = try hitTestElement(at: screenPoint)
        try validateHitElement(
            hitElement,
            belongsTo: accessibilityWindow,
            selectedWindowTitle: selectedWindow.title
        )
        let refinedHitElement = deepestAccessibilityElement(
            in: accessibilityWindow,
            containing: screenPoint,
            depthRemaining: 8
        ) ?? hitElement
        let pressableElement = try resolvePressableElement(
            startingAt: refinedHitElement,
            within: accessibilityWindow,
            failureContext: "No pressable accessibility element was found at window point \(point.x),\(point.y)."
        )

        try performPress(on: pressableElement)

        let response = AccessibilityPressResponse(
            application: windowListApplication(for: catalog.application),
            window: accessibilityWindowEntry(for: selectedWindow),
            mode: "press-at",
            action: kAXPressAction as String,
            selector: nil,
            point: JSONPoint(point.point),
            screenPoint: JSONPoint(screenPoint),
            matched: accessibilityElementResponse(for: refinedHitElement, depthRemaining: 1),
            pressed: accessibilityElementResponse(for: pressableElement, depthRemaining: 1),
            ancestors: accessibilityAncestorResponses(for: pressableElement, stoppingAt: accessibilityWindow)
        )
        return try encodeJSON(response)
    case .pressElement(let selector):
        let pressableElement = try selectAccessibilityElement(in: accessibilityWindow, using: selector)
        try performPress(on: pressableElement.element)

        let response = AccessibilityPressResponse(
            application: windowListApplication(for: catalog.application),
            window: accessibilityWindowEntry(for: selectedWindow),
            mode: "press",
            action: kAXPressAction as String,
            selector: accessibilitySelectorResponse(for: selector),
            point: nil,
            screenPoint: nil,
            matched: accessibilityElementResponse(for: pressableElement.element, depthRemaining: 1),
            pressed: accessibilityElementResponse(for: pressableElement.element, depthRemaining: 1),
            ancestors: accessibilityAncestorResponses(for: pressableElement.element, stoppingAt: accessibilityWindow)
        )
        return try encodeJSON(response)
    }
}

private func handleMenuBar(using command: MenuBarCommand) async throws -> String {
    try ensureAccessibilityAccess(prompt: true)

    let catalog = try buildMenuBarItemCatalog(selector: command.applicationSelector)

    switch command.mode {
    case .listItems:
        let response = MenuBarListResponse(
            application: windowListApplication(for: catalog.application),
            items: catalog.items.map(menuBarItemEntry(for:))
        )
        return try encodeJSON(response)
    case .pressItem:
        let item = try selectMenuBarItem(from: catalog, using: command.selection)
        let menu = try activateMenuBarItem(item, requireVisibleMenu: false)
        let response = MenuBarPressResponse(
            application: windowListApplication(for: catalog.application),
            item: menuBarItemEntry(for: item),
            action: kAXPressAction as String,
            menu: menu.map { accessibilityElementResponse(for: $0, depthRemaining: 2) }
        )
        return try encodeJSON(response)
    case .captureMenu:
        let item = try selectMenuBarItem(from: catalog, using: command.selection)
        let surface = try openMenuBarSurface(for: item, application: catalog.application)
        defer {
            closeMenuBarSurface(surface, item: item)
        }

        let outputURL = command.outputURL ?? temporaryOutputURL()
        let directoryURL = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let region = try captureRegion(forMenuFrame: surface.frame, item: item)
        try captureScreenRegion(region: region, outputURL: outputURL)
        return outputURL.path
    }
}

private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)

    guard let json = String(data: data, encoding: .utf8) else {
        throw RegionShotError.encodeFailed("Failed to encode the response as UTF-8 JSON.")
    }

    return json
}

private func windowListApplication(for application: SCRunningApplication) -> WindowListApplication {
    WindowListApplication(
        name: application.applicationName,
        bundleIdentifier: application.bundleIdentifier,
        processID: application.processID
    )
}

private func windowListApplication(for application: AutomationApplication) -> WindowListApplication {
    WindowListApplication(
        name: application.name,
        bundleIdentifier: application.bundleIdentifier,
        processID: Int32(application.processID)
    )
}

private func windowlessApplicationMessage(
    name: String,
    bundleIdentifier: String,
    processID: pid_t,
    windowKind: String,
    modeDescription: String
) -> String {
    let bundleSummary = bundleIdentifier.isEmpty ? "" : ", \(bundleIdentifier)"
    let policyNote: String

    switch NSRunningApplication(processIdentifier: processID)?.activationPolicy {
    case .accessory?:
        policyNote = " It is running as an accessory/background app, which commonly means menu-bar UI; menu bar items are not app windows."
    case .prohibited?:
        policyNote = " It is running as a background-only app and is not expected to expose normal app windows."
    case .regular?:
        policyNote = " It is a regular app, but no matching window is currently open or visible to this API."
    case nil:
        policyNote = ""
    @unknown default:
        policyNote = ""
    }

    return "`\(name)` was found (pid \(processID)\(bundleSummary)), but macOS exposed no \(windowKind) windows for it.\(policyNote) \(modeDescription) Use `--list-menu-bar-items` and `--capture-menu` for menu-bar/status-item UI, use rectangle capture (`regionshot X Y WIDTH HEIGHT`) for raw visible pixels, or open a normal app window first."
}

private func windowListEntry(for window: CatalogWindow) -> WindowListEntry {
    WindowListEntry(
        index: window.index,
        windowID: window.windowID,
        title: normalizedTitle(window.title),
        frame: JSONRect(window.frame),
        layer: window.layer,
        isOnScreen: window.isOnScreen,
        isActive: window.isActive
    )
}

private func accessibilityWindowEntry(for window: AccessibilityCatalogWindow) -> AccessibilityWindowEntry {
    AccessibilityWindowEntry(
        index: window.index,
        title: normalizedTitle(window.title),
        frame: JSONRect(window.frame),
        isFocused: window.isFocused,
        isMain: window.isMain
    )
}

private func accessibilitySelectorResponse(for selector: AccessibilitySelector) -> AccessibilitySelectorResponse {
    AccessibilitySelectorResponse(
        role: selector.role,
        subrole: selector.subrole,
        title: selector.title,
        identifier: selector.identifier,
        description: selector.elementDescription
    )
}

private func menuBarItemEntry(for item: MenuBarCatalogItem) -> MenuBarItemEntry {
    MenuBarItemEntry(
        index: item.index,
        source: item.source,
        role: item.role,
        subrole: item.subrole,
        title: item.title,
        description: item.description,
        identifier: item.identifier,
        frame: item.frame.map(JSONRect.init),
        actions: item.actions,
        childCount: item.childCount
    )
}

private func buildMenuBarItemCatalog(selector: ApplicationSelector) throws -> MenuBarItemCatalog {
    let runningApplication = try resolveAutomationApplication(selector: selector)
    let applicationElement = AXUIElementCreateApplication(runningApplication.processID)

    var items: [MenuBarCatalogItem] = []
    appendMenuBarItems(
        from: copyAXElement(from: applicationElement, attribute: "AXExtrasMenuBar" as CFString),
        source: "extras",
        to: &items
    )
    appendMenuBarItems(
        from: copyAXElement(from: applicationElement, attribute: kAXMenuBarAttribute as CFString),
        source: "menuBar",
        to: &items
    )

    guard !items.isEmpty else {
        throw RegionShotError.windowNotFound("No menu-bar items are currently available for `\(runningApplication.name)`.")
    }

    return MenuBarItemCatalog(
        application: runningApplication,
        items: items.enumerated().map { offset, item in
            MenuBarCatalogItem(
                index: offset,
                source: item.source,
                role: item.role,
                subrole: item.subrole,
                title: item.title,
                description: item.description,
                identifier: item.identifier,
                frame: item.frame,
                actions: item.actions,
                childCount: item.childCount,
                element: item.element
            )
        }
    )
}

private func appendMenuBarItems(
    from menuBar: AXUIElement?,
    source: String,
    to items: inout [MenuBarCatalogItem]
) {
    guard let menuBar else {
        return
    }

    for element in copyAXElements(from: menuBar, attribute: kAXChildrenAttribute as CFString) {
        guard let frame = copyAXFrame(from: element), !frame.isEmpty else {
            continue
        }

        let children = copyAXElements(from: element, attribute: kAXChildrenAttribute as CFString)
        items.append(
            MenuBarCatalogItem(
                index: items.count,
                source: source,
                role: copyAXString(from: element, attribute: kAXRoleAttribute as CFString),
                subrole: copyAXString(from: element, attribute: kAXSubroleAttribute as CFString),
                title: normalizedTitle(copyAXString(from: element, attribute: kAXTitleAttribute as CFString)),
                description: normalizedTitle(copyAXString(from: element, attribute: kAXDescriptionAttribute as CFString)),
                identifier: normalizedTitle(copyAXString(from: element, attribute: kAXIdentifierAttribute as CFString)),
                frame: frame,
                actions: copyAXActions(from: element),
                childCount: children.count,
                element: element
            )
        )
    }
}

private func selectMenuBarItem(
    from catalog: MenuBarItemCatalog,
    using selection: MenuBarSelection?
) throws -> MenuBarCatalogItem {
    guard let selection else {
        let extras = catalog.items.filter { $0.source == "extras" }
        if extras.count == 1, let item = extras.first {
            return item
        }

        if catalog.items.count == 1, let item = catalog.items.first {
            return item
        }

        let suggestions = catalog.items
            .prefix(6)
            .map(formatMenuBarCandidate)
            .joined(separator: ", ")
        throw RegionShotError.ambiguousWindow("More than one menu-bar item is available for `\(catalog.application.name)`. Choose `--menu-bar-index` or `--menu-bar-item`: \(suggestions)")
    }

    switch selection {
    case .index(let index):
        guard let item = catalog.items.first(where: { $0.index == index }) else {
            throw RegionShotError.windowNotFound("No menu-bar item at index \(index) for `\(catalog.application.name)`. Run `regionshot --app \"\(catalog.application.name)\" --list-menu-bar-items` to inspect available items.")
        }
        return item
    case .name(let query):
        let exactMatches = catalog.items.filter { item in
            menuBarSearchTexts(for: item, application: catalog.application).contains { text in
                normalizedSelectorText(text) == normalizedSelectorText(query)
            }
        }

        if exactMatches.count == 1, let match = exactMatches.first {
            return match
        }

        let partialMatches = catalog.items.filter { item in
            menuBarSearchTexts(for: item, application: catalog.application).contains { text in
                guard
                    let normalizedText = normalizedSelectorText(text),
                    let normalizedQuery = normalizedSelectorText(query)
                else {
                    return false
                }
                return normalizedText.contains(normalizedQuery)
            }
        }
        let matches = exactMatches.isEmpty ? partialMatches : exactMatches

        guard !matches.isEmpty else {
            throw RegionShotError.windowNotFound("No menu-bar item matching `\(query)` was found for `\(catalog.application.name)`. Run `regionshot --app \"\(catalog.application.name)\" --list-menu-bar-items` to inspect available items.")
        }

        guard matches.count == 1, let match = matches.first else {
            let suggestions = matches
                .prefix(6)
                .map(formatMenuBarCandidate)
                .joined(separator: ", ")
            throw RegionShotError.ambiguousWindow("More than one menu-bar item matches `\(query)`: \(suggestions)")
        }

        return match
    }
}

private func menuBarSearchTexts(
    for item: MenuBarCatalogItem,
    application: AutomationApplication
) -> [String] {
    var texts = [
        item.title,
        item.description,
        item.identifier,
    ].compactMap { $0 }

    if item.source == "extras", texts.isEmpty {
        texts.append(application.name)
        if !application.bundleIdentifier.isEmpty {
            texts.append(application.bundleIdentifier)
        }
    }

    return texts
}

private func formatMenuBarCandidate(_ item: MenuBarCatalogItem) -> String {
    let role = item.role ?? "?"
    let subrole = item.subrole.map { "/\($0)" } ?? ""
    let title = item.title.map { " title=\($0)" } ?? ""
    let description = item.description.map { " description=\($0)" } ?? ""
    let identifier = item.identifier.map { " id=\($0)" } ?? ""
    let frame = item.frame.map { " @ \(formatFrame($0))" } ?? ""
    return "[\(item.index)] \(item.source) \(role)\(subrole)\(title)\(description)\(identifier)\(frame)"
}

private func buildAccessibilityWindowCatalog(selector: ApplicationSelector) throws -> AccessibilityWindowCatalog {
    let runningApplication = try resolveAutomationApplication(selector: selector)
    let applicationElement = AXUIElementCreateApplication(runningApplication.processID)
    let focusedWindow = copyAXElement(from: applicationElement, attribute: kAXFocusedWindowAttribute as CFString)
    let mainWindow = copyAXElement(from: applicationElement, attribute: kAXMainWindowAttribute as CFString)
    let rawWindows = copyAXElements(from: applicationElement, attribute: kAXWindowsAttribute as CFString)

    let windows = rawWindows
        .compactMap { element -> AccessibilityCatalogWindow? in
            guard let frame = copyAXFrame(from: element), !frame.isEmpty else {
                return nil
            }

            return AccessibilityCatalogWindow(
                index: 0,
                title: normalizedTitle(copyAXString(from: element, attribute: kAXTitleAttribute as CFString)),
                frame: frame,
                isFocused: focusedWindow.map { CFEqual($0, element) } ?? false,
                isMain: mainWindow.map { CFEqual($0, element) } ?? false,
                element: element
            )
        }
        .sorted(by: accessibilityWindowSort)
        .enumerated()
        .map { offset, window in
            AccessibilityCatalogWindow(
                index: offset,
                title: window.title,
                frame: window.frame,
                isFocused: window.isFocused,
                isMain: window.isMain,
                element: window.element
            )
        }

    guard !windows.isEmpty else {
        throw RegionShotError.windowNotFound(
            windowlessApplicationMessage(
                name: runningApplication.name,
                bundleIdentifier: runningApplication.bundleIdentifier,
                processID: runningApplication.processID,
                windowKind: "accessibility app",
                modeDescription: "`--list-elements`, `--press`, and related Accessibility modes operate inside app windows."
            )
        )
    }

    return AccessibilityWindowCatalog(
        application: runningApplication,
        windows: windows
    )
}

private func resolveAutomationApplication(selector: ApplicationSelector) throws -> AutomationApplication {
    let runningApplications = NSWorkspace.shared.runningApplications

    switch selector {
    case .processID(let processID):
        guard let application = runningApplications.first(where: { $0.processIdentifier == processID }) else {
            throw RegionShotError.applicationNotFound("No running application matches pid \(processID).")
        }
        return automationApplication(from: application)
    case .name(let query):
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            throw RegionShotError.invalidArguments("`--app` requires a non-empty name or process id.")
        }

        let exactMatches = runningApplications.filter { application in
            let name = (application.localizedName ?? "").lowercased()
            let bundleIdentifier = (application.bundleIdentifier ?? "").lowercased()
            return name == normalizedQuery || bundleIdentifier == normalizedQuery
        }

        if exactMatches.count == 1, let match = exactMatches.first {
            return automationApplication(from: match)
        }

        let partialMatches = runningApplications.filter { application in
            let name = (application.localizedName ?? "").lowercased()
            let bundleIdentifier = (application.bundleIdentifier ?? "").lowercased()
            return name.contains(normalizedQuery) || bundleIdentifier.contains(normalizedQuery)
        }

        let matches = exactMatches.isEmpty ? partialMatches : exactMatches

        guard !matches.isEmpty else {
            throw RegionShotError.applicationNotFound("No running application matches `\(query)`.")
        }

        guard matches.count == 1, let match = matches.first else {
            let suggestions = matches
                .prefix(5)
                .map { application in
                    let summary = automationApplication(from: application)
                    return "\(summary.name) (pid \(summary.processID), \(summary.bundleIdentifier))"
                }
                .joined(separator: ", ")
            throw RegionShotError.ambiguousApplication("More than one running application matches `\(query)`: \(suggestions)")
        }

        return automationApplication(from: match)
    }
}

private func automationApplication(from application: NSRunningApplication) -> AutomationApplication {
    AutomationApplication(
        name: application.localizedName ?? "<unknown>",
        bundleIdentifier: application.bundleIdentifier ?? "",
        processID: application.processIdentifier
    )
}

private func accessibilityWindowSort(
    _ left: AccessibilityCatalogWindow,
    _ right: AccessibilityCatalogWindow
) -> Bool {
    if left.isFocused != right.isFocused {
        return left.isFocused && !right.isFocused
    }

    if left.isMain != right.isMain {
        return left.isMain && !right.isMain
    }

    let leftTitle = normalizedTitle(left.title) ?? ""
    let rightTitle = normalizedTitle(right.title) ?? ""
    if leftTitle != rightTitle {
        return leftTitle.localizedCaseInsensitiveCompare(rightTitle) == .orderedAscending
    }

    if left.frame.minY != right.frame.minY {
        return left.frame.minY < right.frame.minY
    }

    if left.frame.minX != right.frame.minX {
        return left.frame.minX < right.frame.minX
    }

    if left.frame.width != right.frame.width {
        return left.frame.width < right.frame.width
    }

    return left.frame.height < right.frame.height
}

private func selectAccessibilityWindow(
    from catalog: AccessibilityWindowCatalog,
    using selection: WindowSelection?
) throws -> AccessibilityCatalogWindow {
    guard let selection else {
        if let focused = catalog.windows.first(where: \.isFocused) {
            return focused
        }
        if let main = catalog.windows.first(where: \.isMain) {
            return main
        }
        guard let first = catalog.windows.first else {
            throw RegionShotError.windowNotFound("`\(catalog.application.name)` has no accessibility windows.")
        }
        return first
    }

    switch selection {
    case .frontmost:
        if let focused = catalog.windows.first(where: \.isFocused) {
            return focused
        }
        if let main = catalog.windows.first(where: \.isMain) {
            return main
        }
        guard let first = catalog.windows.first else {
            throw RegionShotError.windowNotFound("`\(catalog.application.name)` has no accessibility windows.")
        }
        return first
    case .index(let index):
        guard let window = catalog.windows.first(where: { $0.index == index }) else {
            throw RegionShotError.windowNotFound("No accessibility window at index \(index) for `\(catalog.application.name)`.")
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
            throw RegionShotError.windowNotFound("No accessibility window named `\(query)` was found for `\(catalog.application.name)`.")
        }

        guard matches.count == 1, let match = matches.first else {
            let suggestions = matches
                .prefix(5)
                .map { "[\($0.index)] \(displayTitle($0.title))" }
                .joined(separator: ", ")
            throw RegionShotError.ambiguousWindow("More than one accessibility window matches `\(query)`: \(suggestions)")
        }

        return match
    }
}

private func accessibilityElementResponse(
    for element: AXUIElement,
    depthRemaining: Int,
    childLimit: Int = 25
) -> AccessibilityElementResponse {
    let children = copyAXElements(from: element, attribute: kAXChildrenAttribute as CFString)
    let shouldDescend = depthRemaining > 0
    let limitedChildren = shouldDescend ? Array(children.prefix(childLimit)) : []
    let childResponses = shouldDescend
        ? limitedChildren.map { accessibilityElementResponse(for: $0, depthRemaining: depthRemaining - 1, childLimit: childLimit) }
        : nil
    let truncated = (children.count > childLimit) || (depthRemaining == 0 && !children.isEmpty)

    return AccessibilityElementResponse(
        role: copyAXString(from: element, attribute: kAXRoleAttribute as CFString),
        subrole: copyAXString(from: element, attribute: kAXSubroleAttribute as CFString),
        title: normalizedTitle(copyAXString(from: element, attribute: kAXTitleAttribute as CFString)),
        description: normalizedTitle(copyAXString(from: element, attribute: kAXDescriptionAttribute as CFString)),
        identifier: normalizedTitle(copyAXString(from: element, attribute: kAXIdentifierAttribute as CFString)),
        frame: copyAXFrame(from: element).map(JSONRect.init),
        actions: copyAXActions(from: element),
        childCount: children.count,
        truncated: truncated ? true : nil,
        children: childResponses
    )
}

private func accessibilityAncestorResponses(
    for element: AXUIElement,
    stoppingAt targetWindow: AXUIElement
) -> [AccessibilityElementResponse] {
    var responses: [AccessibilityElementResponse] = []
    var current = copyAXElement(from: element, attribute: kAXParentAttribute as CFString)
    var iterationCount = 0

    while let currentElement = current, iterationCount < 64 {
        responses.append(accessibilityElementResponse(for: currentElement, depthRemaining: 0))
        if CFEqual(currentElement, targetWindow) {
            break
        }

        current = copyAXElement(from: currentElement, attribute: kAXParentAttribute as CFString)
        iterationCount += 1
    }

    return responses
}

private func hitTestElement(at screenPoint: CGPoint) throws -> AXUIElement {
    var element: AXUIElement?
    let error = AXUIElementCopyElementAtPosition(
        AXUIElementCreateSystemWide(),
        Float(screenPoint.x),
        Float(screenPoint.y),
        &element
    )

    guard error == .success, let element else {
        throw RegionShotError.accessibilityQueryFailed("No accessibility element was found at screen point \(Int(screenPoint.x)),\(Int(screenPoint.y)).")
    }

    return element
}

private func validateHitElement(
    _ element: AXUIElement,
    belongsTo selectedWindow: AXUIElement,
    selectedWindowTitle: String?
) throws {
    guard let containingWindow = containingAccessibilityWindow(for: element) else {
        throw RegionShotError.accessibilityQueryFailed("The hit-tested element does not expose a containing accessibility window.")
    }

    guard CFEqual(containingWindow, selectedWindow) else {
        let actualWindow = accessibilityElementResponse(for: containingWindow, depthRemaining: 0)
        let actualTitle = displayTitle(actualWindow.title)
        throw RegionShotError.accessibilityQueryFailed("The requested point resolved to a different visible window (`\(actualTitle)`) instead of the selected window `\(displayTitle(selectedWindowTitle))`. Another window or overlay may be in front.")
    }
}

private func containingAccessibilityWindow(for element: AXUIElement) -> AXUIElement? {
    var current: AXUIElement? = element
    var iterationCount = 0

    while let currentElement = current, iterationCount < 64 {
        if copyAXString(from: currentElement, attribute: kAXRoleAttribute as CFString) == (kAXWindowRole as String) {
            return currentElement
        }

        current = copyAXElement(from: currentElement, attribute: kAXParentAttribute as CFString)
        iterationCount += 1
    }

    return nil
}

private func deepestAccessibilityElement(
    in root: AXUIElement,
    containing screenPoint: CGPoint,
    depthRemaining: Int,
    childLimit: Int = 64
) -> AXUIElement? {
    guard let rootFrame = copyAXFrame(from: root), rootFrame.contains(screenPoint) else {
        return nil
    }

    guard depthRemaining > 0 else {
        return root
    }

    let matchingChildren = copyAXElements(from: root, attribute: kAXChildrenAttribute as CFString)
        .prefix(childLimit)
        .compactMap { child -> (element: AXUIElement, area: CGFloat)? in
            guard let frame = copyAXFrame(from: child), frame.contains(screenPoint) else {
                return nil
            }
            return (child, frame.width * frame.height)
        }
        .sorted { $0.area < $1.area }

    for child in matchingChildren {
        if let descendant = deepestAccessibilityElement(
            in: child.element,
            containing: screenPoint,
            depthRemaining: depthRemaining - 1,
            childLimit: childLimit
        ) {
            return descendant
        }
    }

    return root
}

private func resolvePressableElement(
    startingAt element: AXUIElement,
    within targetWindow: AXUIElement,
    failureContext: String
) throws -> AXUIElement {
    var current: AXUIElement? = element
    var iterationCount = 0

    while let currentElement = current, iterationCount < 64 {
        if supportsAXAction(currentElement, action: kAXPressAction as String) {
            return currentElement
        }

        if CFEqual(currentElement, targetWindow) {
            break
        }

        current = copyAXElement(from: currentElement, attribute: kAXParentAttribute as CFString)
        iterationCount += 1
    }

    throw RegionShotError.accessibilityQueryFailed(failureContext)
}

private func selectAccessibilityElement(
    in root: AXUIElement,
    using selector: AccessibilitySelector
) throws -> AccessibilityElementCandidate {
    var candidates = collectAccessibilityElementCandidates(in: root, depthRemaining: 10, childLimit: 80)
        .filter { $0.actions.contains(kAXPressAction as String) }

    candidates = filterCandidates(candidates, exactMatchFor: selector.role) { candidate in
        candidate.role
    }
    candidates = filterCandidates(candidates, exactMatchFor: selector.subrole) { candidate in
        candidate.subrole
    }
    candidates = refineCandidates(
        candidates,
        preferredText: selector.title
    ) { candidate in
        candidate.title
    }
    candidates = refineCandidates(
        candidates,
        preferredText: selector.identifier
    ) { candidate in
        candidate.identifier
    }
    candidates = refineCandidates(
        candidates,
        preferredText: selector.elementDescription
    ) { candidate in
        candidate.description
    }

    guard !candidates.isEmpty else {
        throw RegionShotError.accessibilityQueryFailed("No pressable accessibility element matched \(describe(selector: selector)).")
    }

    if candidates.count == 1, let candidate = candidates.first {
        return candidate
    }

    let suggestions = candidates
        .prefix(5)
        .map(formatAccessibilityCandidate)
        .joined(separator: ", ")

    throw RegionShotError.accessibilityQueryFailed("More than one pressable accessibility element matched \(describe(selector: selector)): \(suggestions)")
}

private func collectAccessibilityElementCandidates(
    in root: AXUIElement,
    depthRemaining: Int,
    childLimit: Int,
    currentDepth: Int = 0
) -> [AccessibilityElementCandidate] {
    let candidate = AccessibilityElementCandidate(
        element: root,
        depth: currentDepth,
        role: copyAXString(from: root, attribute: kAXRoleAttribute as CFString),
        subrole: copyAXString(from: root, attribute: kAXSubroleAttribute as CFString),
        title: normalizedTitle(copyAXString(from: root, attribute: kAXTitleAttribute as CFString)),
        description: normalizedTitle(copyAXString(from: root, attribute: kAXDescriptionAttribute as CFString)),
        identifier: normalizedTitle(copyAXString(from: root, attribute: kAXIdentifierAttribute as CFString)),
        frame: copyAXFrame(from: root),
        actions: copyAXActions(from: root)
    )

    guard depthRemaining > 0 else {
        return [candidate]
    }

    let childCandidates = copyAXElements(from: root, attribute: kAXChildrenAttribute as CFString)
        .prefix(childLimit)
        .flatMap { child in
            collectAccessibilityElementCandidates(
                in: child,
                depthRemaining: depthRemaining - 1,
                childLimit: childLimit,
                currentDepth: currentDepth + 1
            )
        }

    return [candidate] + childCandidates
}

private func filterCandidates(
    _ candidates: [AccessibilityElementCandidate],
    exactMatchFor query: String?,
    extractor: (AccessibilityElementCandidate) -> String?
) -> [AccessibilityElementCandidate] {
    guard let query = normalizedSelectorText(query) else {
        return candidates
    }

    return candidates.filter { candidate in
        normalizedSelectorText(extractor(candidate)) == query
    }
}

private func refineCandidates(
    _ candidates: [AccessibilityElementCandidate],
    preferredText query: String?,
    extractor: (AccessibilityElementCandidate) -> String?
) -> [AccessibilityElementCandidate] {
    guard let query = normalizedSelectorText(query) else {
        return candidates
    }

    let exactMatches = candidates.filter { candidate in
        normalizedSelectorText(extractor(candidate)) == query
    }
    if !exactMatches.isEmpty {
        return exactMatches
    }

    return candidates.filter { candidate in
        guard let value = normalizedSelectorText(extractor(candidate)) else {
            return false
        }
        return value.contains(query)
    }
}

private func openMenuBarSurface(
    for item: MenuBarCatalogItem,
    application: AutomationApplication
) throws -> MenuBarSurface {
    if let existingMenu = visibleMenu(for: item.element) {
        cancelMenu(existingMenu)
        waitForMenuToClose(existingMenu)
        Thread.sleep(forTimeInterval: 0.1)
    }

    guard supportsAXAction(item.element, action: kAXPressAction as String) else {
        throw RegionShotError.accessibilityQueryFailed("Menu-bar item \(formatMenuBarCandidate(item)) does not support `AXPress`.")
    }

    let excludedWindowIDs = Set(
        currentWindowSnapshots()
            .filter { $0.ownerPID == application.processID }
            .map(\.windowID)
    )

    var error = AXUIElementPerformAction(item.element, kAXPressAction as CFString)
    if let surface = waitForVisibleMenuBarSurface(
        for: item,
        application: application,
        excludingWindowIDs: excludedWindowIDs
    ) {
        return surface
    }

    Thread.sleep(forTimeInterval: 0.1)
    error = AXUIElementPerformAction(item.element, kAXPressAction as CFString)
    if let surface = waitForVisibleMenuBarSurface(
        for: item,
        application: application,
        excludingWindowIDs: []
    ) {
        return surface
    }

    guard error == .success else {
        throw RegionShotError.accessibilityQueryFailed("Failed to perform `AXPress` on \(formatMenuBarCandidate(item)) (AX error \(error.rawValue)).")
    }

    throw RegionShotError.accessibilityQueryFailed("No visible menu or menu-like popover appeared after pressing \(formatMenuBarCandidate(item)).")
}

private func activateMenuBarItem(
    _ item: MenuBarCatalogItem,
    requireVisibleMenu: Bool
) throws -> AXUIElement? {
    guard supportsAXAction(item.element, action: kAXPressAction as String) else {
        throw RegionShotError.accessibilityQueryFailed("Menu-bar item \(formatMenuBarCandidate(item)) does not support `AXPress`.")
    }

    var error = AXUIElementPerformAction(item.element, kAXPressAction as CFString)
    var visibleMenu = waitForVisibleMenu(for: item.element)

    if requireVisibleMenu, visibleMenu == nil {
        Thread.sleep(forTimeInterval: 0.1)
        error = AXUIElementPerformAction(item.element, kAXPressAction as CFString)
        visibleMenu = waitForVisibleMenu(for: item.element)
    }

    if requireVisibleMenu, visibleMenu == nil {
        throw RegionShotError.accessibilityQueryFailed("No visible menu appeared after pressing \(formatMenuBarCandidate(item)).")
    }

    guard error == .success || visibleMenu != nil else {
        throw RegionShotError.accessibilityQueryFailed("Failed to perform `AXPress` on \(formatMenuBarCandidate(item)) (AX error \(error.rawValue)).")
    }

    return visibleMenu
}

private func waitForVisibleMenu(
    for item: AXUIElement,
    timeout: TimeInterval = 1.5
) -> AXUIElement? {
    let deadline = Date().addingTimeInterval(timeout)

    repeat {
        if let menu = visibleMenu(for: item) {
            return menu
        }
        Thread.sleep(forTimeInterval: 0.05)
    } while Date() < deadline

    return nil
}

private func waitForVisibleMenuBarSurface(
    for item: MenuBarCatalogItem,
    application: AutomationApplication,
    excludingWindowIDs: Set<CGWindowID>,
    timeout: TimeInterval = 1.5
) -> MenuBarSurface? {
    let deadline = Date().addingTimeInterval(timeout)

    repeat {
        if let menu = visibleMenu(for: item.element) {
            return .menu(menu)
        }

        if let windowFrame = visibleMenuBarSurfaceWindowFrame(
            for: application,
            near: item,
            excludingWindowIDs: excludingWindowIDs
        ) {
            return .window(windowFrame)
        }

        Thread.sleep(forTimeInterval: 0.05)
    } while Date() < deadline

    return nil
}

private func visibleMenuBarSurfaceWindowFrame(
    for application: AutomationApplication,
    near item: MenuBarCatalogItem,
    excludingWindowIDs: Set<CGWindowID>
) -> CGRect? {
    guard let itemFrame = item.frame else {
        return nil
    }

    return currentWindowSnapshots()
        .filter { snapshot in
            snapshot.ownerPID == application.processID &&
            snapshot.layer > 0 &&
            !excludingWindowIDs.contains(snapshot.windowID) &&
            snapshot.bounds.width >= 20 &&
            snapshot.bounds.height >= 20 &&
            isLikelyMenuBarSurfaceWindow(snapshot.bounds, near: itemFrame)
        }
        .sorted { left, right in
            let leftDistance = abs(left.bounds.minY - itemFrame.maxY)
            let rightDistance = abs(right.bounds.minY - itemFrame.maxY)
            if leftDistance != rightDistance {
                return leftDistance < rightDistance
            }

            let leftArea = left.bounds.width * left.bounds.height
            let rightArea = right.bounds.width * right.bounds.height
            return leftArea < rightArea
        }
        .first?
        .bounds
}

private func isLikelyMenuBarSurfaceWindow(_ windowFrame: CGRect, near itemFrame: CGRect) -> Bool {
    let horizontalMargin: CGFloat = 80
    let itemMidX = itemFrame.midX
    let horizontallyRelated =
        itemMidX >= windowFrame.minX - horizontalMargin &&
        itemMidX <= windowFrame.maxX + horizontalMargin

    let belowMenuBar =
        windowFrame.minY >= itemFrame.maxY - 8 &&
        windowFrame.minY <= itemFrame.maxY + 220

    let aboveMenuBar =
        windowFrame.maxY <= itemFrame.minY + 8 &&
        windowFrame.maxY >= itemFrame.minY - 220

    return horizontallyRelated && (belowMenuBar || aboveMenuBar)
}

private func waitForMenuToClose(
    _ menu: AXUIElement,
    timeout: TimeInterval = 0.5
) {
    let deadline = Date().addingTimeInterval(timeout)

    repeat {
        if let frame = copyAXFrame(from: menu), frame.isEmpty {
            return
        }
        Thread.sleep(forTimeInterval: 0.05)
    } while Date() < deadline
}

private func visibleMenu(for item: AXUIElement) -> AXUIElement? {
    copyAXElements(from: item, attribute: kAXChildrenAttribute as CFString)
        .first { element in
            guard copyAXString(from: element, attribute: kAXRoleAttribute as CFString) == (kAXMenuRole as String) else {
                return false
            }
            guard let frame = copyAXFrame(from: element) else {
                return false
            }
            return !frame.isEmpty
        }
}

private func cancelMenu(_ menu: AXUIElement) {
    _ = AXUIElementPerformAction(menu, kAXCancelAction as CFString)
}

private func closeMenuBarSurface(_ surface: MenuBarSurface, item: MenuBarCatalogItem) {
    switch surface {
    case .menu(let menu):
        cancelMenu(menu)
    case .window:
        _ = AXUIElementPerformAction(item.element, kAXPressAction as CFString)
    }
}

private func captureRegion(
    forMenuFrame frame: CGRect?,
    item: MenuBarCatalogItem
) throws -> CaptureRegion {
    guard let frame, !frame.isEmpty else {
        throw RegionShotError.captureFailed("The opened menu for \(formatMenuBarCandidate(item)) did not expose a visible frame.")
    }

    let minX = Int(floor(frame.minX))
    let minY = Int(floor(frame.minY))
    let maxX = Int(ceil(frame.maxX))
    let maxY = Int(ceil(frame.maxY))
    let originX = max(0, minX)
    let originY = max(0, minY)
    let region = CaptureRegion(
        x: originX,
        y: originY,
        width: maxX - originX,
        height: maxY - originY
    )
    try validate(region: region)
    return region
}

private func performPress(on element: AXUIElement) throws {
    let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
    guard error == .success else {
        let target = formatAccessibilityCandidate(
            AccessibilityElementCandidate(
                element: element,
                depth: 0,
                role: copyAXString(from: element, attribute: kAXRoleAttribute as CFString),
                subrole: copyAXString(from: element, attribute: kAXSubroleAttribute as CFString),
                title: normalizedTitle(copyAXString(from: element, attribute: kAXTitleAttribute as CFString)),
                description: normalizedTitle(copyAXString(from: element, attribute: kAXDescriptionAttribute as CFString)),
                identifier: normalizedTitle(copyAXString(from: element, attribute: kAXIdentifierAttribute as CFString)),
                frame: copyAXFrame(from: element),
                actions: copyAXActions(from: element)
            )
        )
        throw RegionShotError.accessibilityQueryFailed("Failed to perform `AXPress` on \(target) (AX error \(error.rawValue)).")
    }
}

private func supportsAXAction(_ element: AXUIElement, action: String) -> Bool {
    let normalizedAction = normalizedSelectorText(action)
    return copyAXActions(from: element).contains { candidate in
        normalizedSelectorText(candidate) == normalizedAction
    }
}

private func normalizedSelectorText(_ value: String?) -> String? {
    guard let value else {
        return nil
    }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }

    return trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
}

private func describe(selector: AccessibilitySelector) -> String {
    let parts = [
        selector.role.map { "role `\($0)`" },
        selector.subrole.map { "subrole `\($0)`" },
        selector.title.map { "title `\($0)`" },
        selector.identifier.map { "identifier `\($0)`" },
        selector.elementDescription.map { "description `\($0)`" },
    ].compactMap { $0 }

    return parts.joined(separator: ", ")
}

private func formatAccessibilityCandidate(_ candidate: AccessibilityElementCandidate) -> String {
    let role = candidate.role ?? "?"
    let subrole = candidate.subrole.map { "/\($0)" } ?? ""
    let title = candidate.title.map { " title=\($0)" } ?? ""
    let identifier = candidate.identifier.map { " id=\($0)" } ?? ""
    let frame = candidate.frame.map { " @ \(formatFrame($0))" } ?? ""
    return "\(role)\(subrole)\(title)\(identifier)\(frame)"
}

private func copyAXString(from element: AXUIElement, attribute: CFString) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
        return nil
    }
    return value as? String
}

private func copyAXElement(from element: AXUIElement, attribute: CFString) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success, let value else {
        return nil
    }
    guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
        return nil
    }
    let axElement = value as! AXUIElement
    return axElement
}

private func copyAXElements(from element: AXUIElement, attribute: CFString) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
        return []
    }
    return value as? [AXUIElement] ?? []
}

private func copyAXActions(from element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success else {
        return []
    }
    return names as? [String] ?? []
}

private func copyAXFrame(from element: AXUIElement) -> CGRect? {
    guard
        let position = copyAXPoint(from: element, attribute: kAXPositionAttribute as CFString),
        let size = copyAXSize(from: element, attribute: kAXSizeAttribute as CFString)
    else {
        return nil
    }

    return CGRect(origin: position, size: size)
}

private func copyAXPoint(from element: AXUIElement, attribute: CFString) -> CGPoint? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success, let value else {
        return nil
    }
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }

    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cgPoint else {
        return nil
    }

    var point = CGPoint.zero
    guard AXValueGetValue(axValue, .cgPoint, &point) else {
        return nil
    }
    return point
}

private func copyAXSize(from element: AXUIElement, attribute: CFString) -> CGSize? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success, let value else {
        return nil
    }
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }

    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cgSize else {
        return nil
    }

    var size = CGSize.zero
    guard AXValueGetValue(axValue, .cgSize, &size) else {
        return nil
    }
    return size
}

private func formatFrame(_ frame: CGRect) -> String {
    "\(Int(frame.minX.rounded(.down))),\(Int(frame.minY.rounded(.down))) \(Int(frame.width.rounded(.down)))x\(Int(frame.height.rounded(.down)))"
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
        throw RegionShotError.windowNotFound(
            windowlessApplicationMessage(
                name: application.applicationName,
                bundleIdentifier: application.bundleIdentifier,
                processID: application.processID,
                windowKind: "capturable app",
                modeDescription: "`--app` window listing and app/window capture only target app windows."
            )
        )
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

private func ensureAccessibilityAccess(prompt: Bool) throws {
    let isTrusted: Bool
    if prompt {
        let promptKey = "AXTrustedCheckOptionPrompt"
        isTrusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    } else {
        isTrusted = AXIsProcessTrusted()
    }

    guard isTrusted else {
        throw RegionShotError.accessibilityPermissionDenied
    }
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

private func validate(windowPoint: WindowPoint, within windowFrame: CGRect, windowTitle: String, flag: String) throws {
    guard CGFloat(windowPoint.x) < windowFrame.width, CGFloat(windowPoint.y) < windowFrame.height else {
        let windowWidth = Int(windowFrame.width.rounded(.down))
        let windowHeight = Int(windowFrame.height.rounded(.down))
        throw RegionShotError.invalidArguments("`\(flag)` \(windowPoint.x),\(windowPoint.y) falls outside the selected window \(windowTitle) sized \(windowWidth)x\(windowHeight) points.")
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
