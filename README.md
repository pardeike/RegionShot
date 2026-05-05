# RegionShot

`RegionShot` is a small macOS Swift 6 command-line tool that installs a lowercase `regionshot` binary. It wraps native macOS `screencapture` and `ScreenCaptureKit` so capture results come from the system screenshot stack.

By default it creates a temporary file and prints the final path, which makes it easy to chain into other tooling without wasting screenshot context on the rest of the display.

## Requirements

- macOS 13 or newer.
- Swift tools 6.2 or newer. If `swift --version` is not available, install Xcode or the Xcode command line tools with `xcode-select --install`.
- Screen Recording permission for screenshot capture and ScreenCaptureKit app/window listing.
- Accessibility permission for `--list-elements`, `--press`, `--press-at`, `--element-at`, and menu-bar modes.

macOS grants those permissions to the host app that launches `regionshot`, such as Terminal, iTerm, or Codex. After granting permission in System Settings, rerun the command that prompted for it.

## Install

```bash
./Scripts/install.sh
command -v regionshot
regionshot --help
```

The installer builds the release binary, installs it to `~/Scripts/regionshot`, copies the bundled Codex support files beside it, and signs the executable. It uses the first locally available `Apple Development` identity when one exists and falls back to ad-hoc signing otherwise.

Both the release and private install paths copy the repo's `Codex/` support files beside the binary. On launch, `regionshot` will silently install or update `~/.codex/skills/regionshot` and a managed `regionshot` pointer block in `~/.codex/AGENTS.md` when those support files are present. If the support file structure is missing, the binary skips this step and continues normally.

If `command -v regionshot` prints nothing, add `~/Scripts` to your zsh PATH:

```bash
echo 'export PATH="$HOME/Scripts:$PATH"' >> ~/.zprofile
source ~/.zprofile
```

You can override the install directory or signing identity:

```bash
INSTALL_DIR="$HOME/bin" ./Scripts/install.sh
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./Scripts/install.sh
```

For a repo-local prototype binary that does not touch `~/Scripts/regionshot`, use:

```bash
./Scripts/build-private.sh
```

That writes `.build/private-bin/regionshot-private`.

## Quick Smoke Test

```bash
regionshot 0 0 200 200
regionshot --find-app Terminal
regionshot --app Terminal --list-visible-windows
```

If you are not using Terminal.app, replace `Terminal` with the app you are running commands from, or use `regionshot --find-app TEXT` to discover the exact name.

## Usage

```bash
regionshot
regionshot --find-app RimWorld
regionshot 120 240 800 600
regionshot --x 120 --y 240 --width 800 --height 600
regionshot --app "System Settings"
regionshot --app "System Settings" --list-windows
regionshot --app "System Settings" --frontmost-window
regionshot --app "System Settings" --frontmost-window --timeout 10
regionshot --app "System Settings" --frontmost-window --window-crop 40,80,300,160
regionshot --app "System Settings" --window-index 0
regionshot --app "System Settings" --window-name "<window title>"
regionshot --app "RimWorld" --list-visible-windows
regionshot --app "RimWorld" --visible-window
regionshot --app "Drafty" --list-menu-bar-items
regionshot --app "Drafty" --capture-menu
regionshot --app "Drafty" --menu-bar-index 0 --capture-menu
regionshot --app "System Settings" --list-elements
regionshot --app "System Settings" --press --role AXButton --title Done
regionshot --app "System Settings" --press-at 14,14
regionshot --app "System Settings" --element-at 14,14
regionshot --app "System Settings" --window-name "<window title>" --press --role AXButton --title Done
regionshot 120 240 800 600 --app "System Settings"
regionshot 120 240 800 600 --app 12345
regionshot 120 240 800 600 --output ~/Desktop/region.png
```

Running the binary without parameters prints a condensed LLM-oriented capability summary: output semantics, accepted command forms, and the key rules that affect capture behavior.

Without `--app`, the rectangle is forwarded directly to macOS `screencapture -R` as `x,y,width,height`.

With `--app`, the value may be either:

- an application name such as `System Settings`
- a bundle identifier such as `com.apple.systempreferences`
- a process id such as `12345`

If you do not know the exact running app name, use `--find-app TEXT`. It prints compact JSON with matching app names, pids, bundle identifiers, paths, activation policy, and visible-window counts.

If `--app` is provided without rectangle coordinates or a specific window flag, `regionshot` prints a JSON window list to stdout for inspection.

`--output` only applies to capture modes. If you pass `--app` without rectangle coordinates or a window selector, no file is written.

App/window modes target normal app windows. Accessory/background apps such as menu-bar utilities may resolve as running applications while exposing no capturable or accessibility windows; use menu-bar modes for their status items and menus.

Window indices are frontmost-first within the selected app.

`--list-visible-windows` and `--visible-window` use the current CGWindowList visible-window stack instead of ScreenCaptureKit app/window capture. This is the fallback for apps where semantic app/window capture is unavailable or times out, and for cases where visible pixels are exactly what you want. It captures whatever is visible in that rectangle, so windows in front of the target are included.

In `--app` rectangle mode the output contains only that application's windows inside the requested rectangle, even if other apps are visually in front.

In specific-window mode, `regionshot` can capture:

- the app's frontmost window via `--frontmost-window`
- the app window at a frontmost-first index via `--window-index`
- the app window whose title matches via `--window-name`

`--window-crop x,y,width,height` works with those specific-window modes and is relative to the selected window's top-left corner in points. This is useful for element-level screenshots inside a known window.

Menu-bar modes inspect and operate on generic Accessibility menu-bar items exposed by the selected app. `--list-menu-bar-items` prints JSON entries for status items and app menu-bar items. `--capture-menu` opens the selected menu-bar item, captures the visible menu or menu-like popover rectangle, prints the PNG path, and closes it. If you omit `--menu-bar-index` or `--menu-bar-item`, RegionShot selects the single status-item entry when exactly one is available; otherwise it fails with candidate suggestions.

`--list-elements` prints a bounded JSON accessibility tree for the selected window. If you omit a window selector, it defaults to the app's focused window, then main window, then first accessibility window.

`--press` is the preferred interaction mode. It finds a pressable accessibility element inside the selected window using selector fields such as `--role`, `--subrole`, `--title`, `--identifier`, and `--description`, then performs `AXPress`. `--press-element` remains as an alias.

For `--title`, `--identifier`, and `--description`, the matcher prefers exact case-insensitive matches and only falls back to case-insensitive substring matching when no exact match exists.

If a selector is ambiguous, the command fails and prints a short candidate list instead of pressing an arbitrary element.

`--press-at x,y` is the fallback mode when the accessibility tree is too weak or a selector is inconvenient. It resolves the deepest visible element at a window-relative point, walks up to the nearest ancestor that supports `AXPress`, and presses that element.

`--element-at x,y` hit-tests the visible accessibility element at a window-relative point and prints JSON for the hit element plus its ancestor chain. This uses the visible screen stack, so another window or overlay in front can change the result.

App-filtered screenshot capture and `--list-windows` use the ScreenCaptureKit window catalog, so they require macOS Screen Recording permission for the host process.

ScreenCaptureKit app/window operations time out after five seconds by default. Use `--timeout SECONDS` when the system is slow. Timeout errors suggest RegionShot visible-window fallback commands instead of hanging indefinitely.

Accessibility inspection and actions use Accessibility APIs directly and require macOS Accessibility permission for the host process.

## Notes

- The tool uses the system `/usr/sbin/screencapture` utility for the actual capture.
- The app-filtered capture path uses `ScreenCaptureKit`.
- macOS may require Screen Recording permission for the host app that launches the tool.
