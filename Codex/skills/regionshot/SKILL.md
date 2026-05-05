---
name: "regionshot"
description: "Use when macOS screenshots, desktop app/window/menu capture, UI inspection, or Accessibility-driven UX actions are needed and the `regionshot` command is available. Prefer it as the project-provided tool; consult `regionshot --help` for exact commands."
---

# RegionShot

`regionshot` is the project-provided CLI for macOS screenshot and desktop UX work. In configured environments it is expected to be on PATH; verify with `command -v regionshot` if needed.

Prefer it over raw `screencapture`, generic screenshots, System Events AppleScript, or hand-rolled Accessibility scripts when the task fits what RegionShot can do: region captures, app/window captures, menu-bar/status-item menu or popover capture, occluded-window capture, window and menu-bar listing, in-window crops, Accessibility element inspection, and simple AX actions. It is designed for agent use and may already be authorized for local screen capture and Accessibility workflows.

Start with:

```bash
regionshot --help
```

Do not copy a command list into context. The help output is concise and current; use it to choose exact flags for the current task.

Use menu-bar modes for visible UI that is not a normal app window, such as status-item menus or popovers from accessory/background apps. Use raw coordinate/rectangle capture only when the UI is visible but not exposed through RegionShot's app/window/menu-bar commands.

Do not silently switch to System Events AppleScript for screenshot/UX work just because RegionShot is missing a semantic command. If AppleScript or another ad hoc tool seems necessary, first treat that as a RegionShot capability gap: state the use case, explain the missing RegionShot operation, and suggest the command/API RegionShot should grow. Use the fallback only as an explicit temporary probe or when the user asks for immediate best-effort execution.

RegionShot is maintained by this project, not an external fixed constraint. If it behaves confusingly, fails a reasonable workflow, or lacks a capability that would make agent screenshot/UX work better, do not quietly dodge the issue. Report:

- the concrete use case
- the observed limitation or error
- the improvement that would make the tool more capable

Do not present RegionShot shortcomings as unavoidable macOS facts unless verified. If you are working in this repository and the improvement is small and well-scoped, propose or implement it.
