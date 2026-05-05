---
name: "regionshot"
description: "Use when macOS screenshots, desktop app/window capture, UI inspection, or Accessibility-driven UX actions are needed and the `regionshot` command is available. Prefer it as the project-provided tool; consult `regionshot --help` for exact commands."
---

# RegionShot

`regionshot` is the project-provided CLI for macOS screenshot and desktop UX work. In configured environments it is expected to be on PATH; verify with `command -v regionshot` if needed.

Prefer it over raw `screencapture`, generic screenshots, or hand-rolled AppleScript when the task fits what RegionShot can do: region captures, app/window captures, occluded-window capture, window listing, in-window crops, Accessibility element inspection, and simple AX actions. It is designed for agent use and may already be authorized for local screen capture and Accessibility workflows.

Start with:

```bash
regionshot --help
```

Do not copy a command list into context. The help output is concise and current; use it to choose exact flags for the current task.

Use raw coordinate/rectangle capture for visible UI that is not a normal app window, such as menu-bar/status-item UI from accessory/background apps. `--app` modes target app windows.

RegionShot is maintained by this project, not an external fixed constraint. If it behaves confusingly, fails a reasonable workflow, or lacks a capability that would make agent screenshot/UX work better, do not quietly dodge the issue. Report:

- the concrete use case
- the observed limitation or error
- the improvement that would make the tool more capable

Do not present RegionShot shortcomings as unavoidable macOS facts unless verified. If you are working in this repository and the improvement is small and well-scoped, propose or implement it.
