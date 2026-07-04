# RegionShot Command Guide

This page lists the main command forms. Run `regionshot --help` for the exact
help text from the installed binary.

## Version

```bash
regionshot --version
```

## Doctor

```bash
regionshot doctor
```

`doctor` prints compact JSON with non-prompting Screen Recording and
Accessibility permission status, the RegionShot version, and the parent host
process that macOS permissions apply to.

## Clipboard

```bash
regionshot clipboard
regionshot clipboard --set "copied text"
```

`clipboard` reads or sets plain text on the general pasteboard and prints JSON.

## App Lifecycle

```bash
regionshot activate --app "System Settings"
regionshot activate --pid 12345
regionshot launch com.apple.TextEdit --wait-window --timeout 10
regionshot launch .build/debug/MyDebugApp --wait-window --args --fixture smoke
regionshot quit --app "My Debug App"
regionshot quit --pid 12345 --force
```

`activate` resolves a running app by name, bundle id, or process id, asks macOS
to activate it, and prints JSON describing the app and whether macOS accepted the
activation request.

`launch` starts an app bundle path, bundle id, or executable path. Add
`--wait-window` to wait until the launched process exposes its first accessibility
window. Arguments after `--args` are passed to the launched app unchanged.

`quit` resolves a running app and asks it to terminate. Add `--force` to call
force-terminate instead. The command prints JSON describing the app and whether
macOS accepted the termination request.

## Displays

```bash
regionshot --list-displays
```

`--list-displays` prints compact JSON for active displays, including the display
id, point frame, pixel size, scale, and whether the display is the main display.

## Basic Capture

```bash
regionshot
regionshot 120 240 800 600
regionshot --x 120 --y 240 --width 800 --height 600
regionshot 120 240 800 600 --output ~/Desktop/region.png
```

Without `--app`, rectangle capture is forwarded to the system
`/usr/sbin/screencapture` tool.

By default, capture commands create a temporary file and print the path.

## Find Apps

```bash
regionshot --find-app Terminal
regionshot --find-app RimWorld
```

Use this when you do not know the exact running app name. The output includes
matching app names, process ids, bundle identifiers, paths, activation policy,
and visible-window counts.

`--app` accepts an app name, a bundle identifier, or a process id. Pure integer
values keep the historical behavior and are treated as process ids. Use
`--pid` for explicit process-id selection, or `--app-name` to force name/bundle
matching when an app name is numeric:

```bash
regionshot --app "System Settings"
regionshot --app com.apple.systempreferences
regionshot --app 12345
regionshot --pid 12345
regionshot --app-name "2048"
```

## Windows

```bash
regionshot --app "System Settings" --list-windows
regionshot --app "System Settings" --frontmost-window
regionshot --app "System Settings" --window-index 0
regionshot --app "System Settings" --window-name "<window title>"
regionshot --app "System Settings" --frontmost-window --window-crop 40,80,300,160
```

Window indices are frontmost first within the selected app.

`--window-crop x,y,width,height` is relative to the selected window's top-left
corner in points.

## Visible Windows

```bash
regionshot --app "RimWorld" --list-visible-windows
regionshot --app "RimWorld" --visible-window
regionshot --app "Drafty" --visible-window --output ~/Desktop/drafty-panel.png
```

`--list-visible-windows` and `--visible-window` use the current visible window
stack instead of app/window capture. This is useful when system app/window
capture is unavailable, times out, or when visible pixels are exactly what you
need.

Visible-window modes include normal windows and app-owned floating panels. They
capture what is visible in that rectangle, so windows in front of the target are
included.

## App-Filtered Rectangles

```bash
regionshot 120 240 800 600 --app "System Settings"
regionshot 120 240 800 600 --app 12345
```

In app rectangle mode, the output contains only the selected app's windows
inside the rectangle, even if other apps are visually in front.

## Menu-Bar Items

```bash
regionshot --app "Drafty" --list-menu-bar-items
regionshot --app "Drafty" --capture-menu
regionshot --app "Drafty" --menu-bar-index 0 --capture-menu
regionshot --app "Drafty" --menu-bar-index 0 --press-menu-item "Quick Tasks"
regionshot --app "Drafty" --menu-bar-item "Drafty" --press-menu-item "Preferences..."
```

Menu-bar modes work with accessibility menu-bar items exposed by the selected
app. They are useful for status-item apps and menu-like popovers.

If you omit `--menu-bar-index` or `--menu-bar-item`, RegionShot selects the
single status-item entry when exactly one is available. If there are multiple
candidates, the command fails and prints suggestions.

`--press-menu-item TEXT` opens the selected menu-bar item, then presses a child
menu item by title, description, or identifier.

## Accessibility Inspection And Actions

```bash
regionshot --app "System Settings" --list-elements
regionshot --app "System Settings" --list-elements --depth 2 --max-children 12
regionshot --app "System Settings" --list-elements --roles AXButton,AXTextField --interactive --flat
regionshot --app "System Settings" --wait-for-window "Network" --timeout 10
regionshot --app "System Settings" --get --path 0.3.1
regionshot --app "System Settings" --get --role AXTextField --title Name
regionshot --app "System Settings" --wait-for-element --role AXButton --title Done --timeout 10
regionshot --app "System Settings" --set-value "Andreas" --path 0.3.1
regionshot --app "System Settings" --set-value "Andreas" --role AXTextField --title Name
regionshot --app "System Settings" --type "typed text"
regionshot --app "System Settings" --key "cmd+s"
regionshot --app "System Settings" --click 24,24
regionshot --app "System Settings" --click 24,24 --right
regionshot --app "System Settings" --drag 24,24,160,24
regionshot --app "System Settings" --scroll 0,-800
regionshot --app "System Settings" --press --role AXButton --title Done
regionshot --app "System Settings" --press-at 14,14
regionshot --app "System Settings" --element-at 14,14
regionshot --app "System Settings" --window-name "<window title>" --press --role AXButton --title Done
```

`--list-elements` prints a bounded JSON accessibility tree for the selected
window. If you omit a window selector, RegionShot uses the focused window, then
the main window, then the first accessibility window.
Element JSON includes structural fields plus readable state when macOS exposes
it: `path`, `value`, `enabled`, `focused`, and `selected`.
Use `--depth N` and `--max-children N` with `--list-elements` to reduce or
expand the tree. Use `--roles ROLE[,ROLE...]` to keep only matching roles and
their ancestors, `--interactive` to keep elements with actions and their
ancestors, and `--flat` to return a flat `elements` array instead of a nested
tree. Empty `actions` arrays are omitted from element JSON.
Use `--path PATH` with `--get`, `--wait-for-element`, `--set-value`, or `--press`
to target a listed element directly. Paths cannot be combined with fuzzy selector
fields such as `--role` or `--title`.

`--wait-for-window TITLE` polls the app's accessibility windows until one title
matches, then returns that window as JSON. Use `--timeout SECONDS` to adjust the
wait.

`--get` finds one accessibility element using selector fields and returns its
full JSON attributes without performing an action. It uses the same selector
fields and matching rules as `--press`.

`--wait-for-element` polls until exactly one matching accessibility element is
available, then returns it using the same JSON shape as `--get`. Use
`--timeout SECONDS` to adjust the wait.

`--set-value TEXT` finds one accessibility element using selector fields, writes
the element's `AXValue`, and returns the updated element. Empty text is valid and
can be used to clear text fields that support `AXValue` writes.

`--type TEXT` activates the app and posts Unicode keyboard input to its process.
`--key CHORD` posts a shortcut or named key such as `cmd+s`, `cmd+shift+s`,
`escape`, or `return`.

`--click X,Y`, `--drag X1,Y1,X2,Y2`, and `--scroll DX,DY` activate the app,
raise the selected window when supported, and post CGEvent mouse input. Click and
drag coordinates are window-relative points. Scroll is posted at the selected
window's center point and accepts signed horizontal/vertical deltas.

`--press` finds a pressable accessibility element using selector fields such as
`--role`, `--subrole`, `--title`, `--identifier`, and `--description`, then
performs `AXPress`.

For `--title`, `--identifier`, and `--description`, matching prefers exact
case-insensitive matches. It only falls back to substring matching when no exact
match exists.

If a selector is ambiguous, the command fails and prints a short candidate list
instead of pressing an arbitrary element.

`--press-at x,y` is a fallback for weak accessibility trees. It resolves the
deepest visible element at a window-relative point, walks up to the nearest
ancestor that supports `AXPress`, and presses that element.

`--element-at x,y` prints JSON for the visible accessibility element at a
window-relative point plus its ancestor chain.

## ASCII And OCR View

```bash
regionshot --ascii /tmp/screenshot.png
regionshot --ascii /tmp/screenshot.png --ascii-width 160 --ascii-max-height 80
regionshot --ascii /tmp/screenshot.png --ascii-style tone --ascii-width 100 --ascii-max-height 60
regionshot --ascii /tmp/screenshot.png --ascii-language de-DE,sv-SE
regionshot --ascii /tmp/screenshot.png --ocr-only
```

`--ascii IMAGE` reads an existing screenshot or image file and prints a compact
text inspection report.

The default `layout` style renders sparse borders, dividers, and scrollbars,
then overlays Vision OCR text at approximate screenshot positions. The OCR
block list is printed below the layout map with pixel bounds and confidence.
By default RegionShot leaves Vision's recognition languages unset. Use
`--ascii-language CODE[,CODE...]` to pass explicit OCR language codes.

Useful options:

- `--ascii-width N`, range `16...240`
- `--ascii-max-height N`, range `8...240`
- `--ascii-style tone`
- `--ascii-language CODE[,CODE...]`
- `--ascii-invert`
- `--ascii-no-ocr`
- `--ocr-only`

`--ocr-only` skips ASCII rendering and returns JSON OCR blocks with pixel
bounds, which is cheaper when text is the only needed signal.

## Timeouts

ScreenCaptureKit app/window operations time out after five seconds by default.

Use `--timeout SECONDS` when the system is slow:

```bash
regionshot --app "System Settings" --frontmost-window --timeout 10
```

If app/window capture times out, try visible-window capture:

```bash
regionshot --app "System Settings" --list-visible-windows
regionshot --app "System Settings" --visible-window --output ~/Desktop/window.png
```

## Accessibility Windows

```bash
regionshot --app "Terminal" --list-accessibility-windows
regionshot --app "Terminal" --window-index 0 --raise-window
regionshot --app "Terminal" --window-name "server logs" --raise-window
regionshot --app "Terminal" --window-name "server logs" --raise
regionshot --app "Terminal" --window-name "server logs" --close-window
regionshot --app "Terminal" --window-name "server logs" --minimize-window
regionshot --app "Terminal" --window-name "server logs" --move-window 120,80
regionshot --app "Terminal" --window-name "server logs" --resize-window 900,600
```

`--list-accessibility-windows` lists windows through Accessibility instead of
ScreenCaptureKit. The JSON includes each window's title, frame, supported AX
actions, `isFocused`, `isMain`, `isFrontmostApplication`, and
`isFrontmostWindow`.

`isFrontmostWindow` means the selected app is the current
`NSWorkspace.frontmostApplication`, and the window is that app's focused AX
window. If the app exposes no focused AX window, RegionShot falls back to the
main window, then index 0.

`--raise-window` activates the app and performs `AXRaise` on the selected AX
window. Select the window with `--window-index`, `--window-name`, or
`--frontmost-window`; if you omit a selector, RegionShot uses the same focused,
main, then first-window fallback as other Accessibility modes.

`--close-window` presses the selected AX window's close button using the same
window-selection rules.

`--minimize-window` presses the selected AX window's minimize button using the
same window-selection rules.

`--move-window X,Y` sets the selected AX window's `AXPosition`; negative
coordinates are allowed for multi-display layouts. `--resize-window W,H` sets
the selected AX window's `AXSize`; width and height must be positive.

## Permissions

Capture and app/window listing require Screen Recording permission for the host
process.

Accessibility inspection and actions require Accessibility permission for the
host process.

The host process is the app that starts `regionshot`, such as Terminal, iTerm,
or Codex.

Use `regionshot doctor` to check both permissions without triggering a system
permission prompt.

## Exit Codes

RegionShot uses distinct exit codes so automation can decide whether to retry,
ask for a more specific selector, or hand the issue to the user:

- `64`: usage error or invalid arguments
- `65`: ambiguous app or window match
- `66`: app or window not found
- `69`: unavailable feature or missing permission
- `70`: capture, Accessibility, or encoding failure
- `75`: timed out operation
