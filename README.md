# RegionShot

`RegionShot` is a small macOS Swift 6 command-line tool that captures only a rectangular region of the screen and writes a PNG file.

By default it creates a temporary file and prints the final path, which makes it easy to chain into other tooling without wasting screenshot context on the rest of the display.

## Usage

```bash
RegionShot
RegionShot 120 240 800 600
RegionShot --x 120 --y 240 --width 800 --height 600
RegionShot 120 240 800 600 --app "System Settings"
RegionShot 120 240 800 600 --app 12345
RegionShot 120 240 800 600 --output ~/Desktop/region.png
```

Running the binary without parameters prints a concise self-description and usage summary.

Without `--app`, the rectangle is forwarded directly to macOS `screencapture -R` as `x,y,width,height`.

With `--app`, the value may be either:

- an application name such as `System Settings`
- a bundle identifier such as `com.apple.systempreferences`
- a process id such as `12345`

In `--app` mode the output contains only that application's windows inside the requested rectangle, even if other apps are visually in front.

## Install

```bash
./Scripts/install.sh
```

That script:

- builds the package in release mode
- installs the executable to `~/Scripts/RegionShot`
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
