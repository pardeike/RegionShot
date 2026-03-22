---
name: "regionshot"
description: "Use when the task involves macOS desktop app window screenshots, occluded-window capture, app/window inspection, in-window crops, or Accessibility element inspection and actions using the installed `/Users/ap/Scripts/regionshot` binary."
---

# RegionShot

Use `/Users/ap/Scripts/regionshot` for macOS desktop app window capture and desktop UI automation. Prefer it over raw `screencapture` or generic screenshot tooling when the task is about a desktop app window, especially if the target window may be occluded.

## When to use this skill

Use this skill when the task involves:

- capturing a specific macOS app window
- capturing a window even when another window is on top
- listing or selecting windows inside a running app
- cropping to window-local coordinates
- inspecting Accessibility elements in a desktop app window
- invoking selector-based Accessibility actions in a desktop app

## Binary

Use the installed binary directly:

```bash
/Users/ap/Scripts/regionshot --help
```

Do not assume the repo-local build is the one the user wants tested. Prefer the installed `/Users/ap/Scripts/regionshot` binary unless the user explicitly asks to test a private or in-repo build.

## Core workflows

List matching app windows:

```bash
/Users/ap/Scripts/regionshot --app "<App>" --list-windows
```

Capture a specific window:

```bash
/Users/ap/Scripts/regionshot --app "<App>" --window-name "<Title>"
```

Capture the app's frontmost window:

```bash
/Users/ap/Scripts/regionshot --app "<App>" --frontmost-window
```

Capture a crop inside a selected window:

```bash
/Users/ap/Scripts/regionshot --app "<App>" --frontmost-window --window-crop x,y,width,height
```

List Accessibility elements for the selected window:

```bash
/Users/ap/Scripts/regionshot --app "<App>" --list-elements
```

Inspect the visible element at a window-relative point:

```bash
/Users/ap/Scripts/regionshot --app "<App>" --element-at x,y
```

Selector-first Accessibility action:

```bash
/Users/ap/Scripts/regionshot --app "<App>" --press --role AXButton --title Done
```

Coordinate fallback for Accessibility action:

```bash
/Users/ap/Scripts/regionshot --app "<App>" --press-at x,y
```

## Selection guidance

For automation, prefer selector-based `--press`. It is the primary interface and is more reliable for agents than coordinate-based actions because it operates on the window's Accessibility tree rather than visible screen pixels.

Use `--press-at` and `--element-at` only as fallbacks when selectors are unavailable or ambiguous. Those modes depend on the visible screen stack and can fail if another window, sheet, or overlay is in front of the target point.

For Accessibility modes, if no explicit window selector is given, `regionshot` defaults to the app's focused window, then main window, then first available Accessibility window.

Use `--window-name` when a stable title is available. Use `--frontmost-window` when the task deliberately activates the target app first.

## Permissions

Window listing and screenshot capture use ScreenCaptureKit and require Screen Recording permission.

Accessibility inspection and actions use Accessibility APIs and require Accessibility permission.
