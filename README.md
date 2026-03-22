# RegionShot

`RegionShot` is a small macOS Swift 6 command-line tool that installs a lowercase `regionshot` binary for capturing only the relevant portion of the screen.

By default it creates a temporary file and prints the final path, which makes it easy to chain into other tooling without wasting screenshot context on the rest of the display.

## Usage

```bash
regionshot
regionshot 120 240 800 600
regionshot --x 120 --y 240 --width 800 --height 600
regionshot --app "System Settings"
regionshot --app "System Settings" --list-windows
regionshot --app "System Settings" --frontmost-window
regionshot --app "System Settings" --frontmost-window --window-crop 40,80,300,160
regionshot --app "System Settings" --window-index 0
regionshot --app "System Settings" --window-name "<window title>"
regionshot 120 240 800 600 --app "System Settings"
regionshot 120 240 800 600 --app 12345
regionshot 120 240 800 600 --output ~/Desktop/region.png
```

Running the binary without parameters prints a concise self-description and usage summary.

Without `--app`, the rectangle is forwarded directly to macOS `screencapture -R` as `x,y,width,height`.

With `--app`, the value may be either:

- an application name such as `System Settings`
- a bundle identifier such as `com.apple.systempreferences`
- a process id such as `12345`

If `--app` is provided without rectangle coordinates or a specific window flag, `regionshot` prints a JSON window list to stdout for inspection.

`--output` only applies to capture modes. If you pass `--app` without rectangle coordinates or a window selector, no file is written.

Window indices are frontmost-first within the selected app.

In `--app` rectangle mode the output contains only that application's windows inside the requested rectangle, even if other apps are visually in front.

In specific-window mode, `regionshot` can capture:

- the app's frontmost window via `--frontmost-window`
- the app window at a frontmost-first index via `--window-index`
- the app window whose title matches via `--window-name`

`--window-crop x,y,width,height` works with those specific-window modes and is relative to the selected window's top-left corner in points. This is useful for element-level screenshots inside a known window.

## Install

```bash
./Scripts/install.sh
```

That script:

- builds the package in release mode
- installs the executable to `~/Scripts/regionshot`
- signs it with the first locally available `Apple Development` identity

You can override the signing identity or install directory:

```bash
CODESIGN_IDENTITY="Apple Development: Andreas Pardeike (MLYF6EP5DL)" ./Scripts/install.sh
INSTALL_DIR="$HOME/bin" ./Scripts/install.sh
```

## Notes

- The tool uses the system `/usr/sbin/screencapture` utility for the actual capture.
- The app-filtered capture path uses `ScreenCaptureKit`.
- macOS may require Screen Recording permission for the host app that launches the tool.
