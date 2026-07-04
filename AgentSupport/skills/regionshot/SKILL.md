---
name: "regionshot"
description: "Use when macOS screenshots, desktop app/window/menu capture, UI inspection, Accessibility-driven UX actions, app launch/quit/activation, keyboard/mouse input, clipboard, waiting, or window management are needed and the `regionshot` command is available. Prefer it as the project-provided tool; consult `regionshot --help` for exact commands."
---

# RegionShot

`regionshot` is the project-provided CLI for macOS screenshot and desktop UX work. In configured environments it is expected to be on PATH; verify with `command -v regionshot` if needed.

Prefer it over raw `screencapture`, generic screenshots, System Events AppleScript, or hand-rolled Accessibility scripts when the task fits what RegionShot can do:

- discover running apps and displays with `regionshot apps QUERY` and `regionshot displays`
- capture rectangles, displays, app windows, visible floating panels, and menu-bar/status-item menus with `regionshot capture ...` and `regionshot menu ... capture`
- return compact JSON envelopes, structured JSON errors, and explicit exit codes for agent branching
- add cheap text output to captures with `--with-ocr` or `--with-ascii`, downscale images with `--max-dimension`, and inspect existing images with `regionshot ascii IMAGE --ocr-only`
- list windows with `regionshot windows --app APP [--visible|--ax]`
- inspect Accessibility trees and state with `regionshot ax --app APP tree|get|wait-for-element`, including `value`, `enabled`, `focused`, `selected`, stable `path` selectors, `--interactive`, `--flat`, `--depth`, `--max-children`, and `--roles`
- act on UI with `regionshot ax --app APP press|set-value|type|key|click|drag|scroll`
- launch, activate, quit, wait for windows/elements, move/resize/raise/close/minimize windows, and read/set clipboard text
- check permissions without prompting with `regionshot doctor`, and add `--no-prompt` to Accessibility/menu/waiting commands when unattended behavior matters

It is designed for agent use and may already be authorized for local screen capture and Accessibility workflows.

Start with:

```bash
regionshot --help
```

Do not copy a command list into context. The top-level help is a short subcommand index; use `regionshot <subcommand> --help` to choose exact flags for the current task.

When the exact app name is unknown, use RegionShot's app discovery before falling back to process searches. If ScreenCaptureKit app/window capture fails or visible pixels are enough, use the visible-window listing/capture modes before raw rectangle capture; visible-window modes include app-owned floating panels. If Screen Recording permission blocks app/window inspection but Accessibility works, use `regionshot ax --app APP windows` to inspect AX windows and `regionshot ax --app APP raise --window-index N` to bring a specific AX window forward. Use menu-bar modes for visible UI that is not a normal app window, such as status-item menus or popovers from accessory/background apps. Use `regionshot menu --app APP press-item TEXT` after selecting a menu-bar item when you need to choose a child item inside a status menu. Use raw coordinate/rectangle capture only when the UI is visible but not exposed through RegionShot's app/window/visible-window/menu-bar commands.

For a local app development loop, prefer RegionShot's observe-act primitives before ad hoc sleeps: `regionshot launch PATH|BUNDLE_ID --wait-window`, `regionshot ax --app APP wait-for-element ...`, `regionshot ax --app APP set-value ...`, `regionshot ax --app APP type ...`, `regionshot ax --app APP key cmd+s`, `regionshot ax --app APP click X,Y`, and `regionshot quit --app APP`.

Do not silently switch to System Events AppleScript for screenshot/UX work just because RegionShot is missing a semantic command. If AppleScript or another ad hoc tool seems necessary, first treat that as a RegionShot capability gap: state the use case, explain the missing RegionShot operation, and suggest the command/API RegionShot should grow. Use the fallback only as an explicit temporary probe or when the user asks for immediate best-effort execution.

RegionShot is maintained by this project, not an external fixed constraint. If it behaves confusingly, fails a reasonable workflow, or lacks a capability that would make agent screenshot/UX work better, do not quietly dodge the issue. Report:

- the concrete use case
- the observed limitation or error
- the improvement that would make the tool more capable

Do not present RegionShot shortcomings as unavoidable macOS facts unless verified. If you are working in this repository and the improvement is small and well-scoped, propose or implement it.
