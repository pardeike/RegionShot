# RegionShot

RegionShot is a small macOS command line tool for screenshots, window capture,
menu capture, and simple UI actions.

It is built for agents and scripts. It helps them ask macOS for the right
thing instead of guessing screen rectangles:

- find a running app
- list app windows
- capture a window or a visible floating panel
- open and capture a menu-bar item
- press a known menu item or accessibility button
- convert a screenshot to a compact text view

## Install

Download `RegionShot-1.0.0-macos.dmg` from the GitHub release, open it, and run
`Install RegionShot.command`.

The installer copies `regionshot` to `~/Scripts/regionshot`.

If your shell does not find it, add `~/Scripts` to your PATH:

```bash
echo 'export PATH="$HOME/Scripts:$PATH"' >> ~/.zprofile
source ~/.zprofile
```

Check the install:

```bash
command -v regionshot
regionshot --help
```

## Permissions

macOS may ask for Screen Recording permission when RegionShot captures the
screen or lists windows.

macOS may ask for Accessibility permission when RegionShot inspects UI elements,
presses buttons, or works with menu-bar items.

The permission is granted to the app that starts `regionshot`, usually Terminal,
iTerm, or Codex. After granting permission in System Settings, run the command
again.

## Common Commands

```bash
regionshot 0 0 800 600
regionshot --find-app Terminal
regionshot --app Terminal --list-visible-windows
regionshot --app Terminal --visible-window --output ~/Desktop/terminal.png
regionshot --app Drafty --list-menu-bar-items
regionshot --app Drafty --menu-bar-index 0 --press-menu-item "Quick Tasks"
regionshot --ascii ~/Desktop/terminal.png
```

Running `regionshot` without arguments prints a short command summary.

For the full command guide, see [docs/usage.md](docs/usage.md).

## Build From Source

Requirements:

- macOS 13 or newer
- Swift tools 6.4 or newer to build

The Swift tools requirement is build-time only. The binary still targets macOS
13 or newer.

Build and install:

```bash
./Scripts/install.sh
regionshot --help
```

For a repo-local prototype binary that does not touch `~/Scripts/regionshot`,
run:

```bash
./Scripts/build-private.sh
```

That writes `.build/private-bin/regionshot-private`.

## Codex Support

The install scripts also copy the bundled Codex support files. When those files
are present, `regionshot` keeps `~/.codex/skills/regionshot` and the managed
RegionShot block in `~/.codex/AGENTS.md` up to date.

If the support files are missing, the binary skips this step and still works.

## Maintainers

Release packaging and notarization are documented in
[docs/release.md](docs/release.md).
