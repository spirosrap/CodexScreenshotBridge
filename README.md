# Codex Screenshot Bridge

Codex Screenshot Bridge is a lightweight macOS menu-bar app that moves screenshots directly into the Codex desktop input box.

It supports both screenshot styles:
- file-based screenshots (saved to disk)
- clipboard-only screenshots (copy shortcut flow)

![Codex Screenshot Bridge updated UI](assets/codex-screenshot-bridge-permission-panel.png)

Current menu-bar window with the built-in permission status panel.

## Features

- Menu-bar app (`LSUIElement`) with instant enable/disable toggle
- Watches screenshot folder for new files and pastes the screenshot file URL
- Watches clipboard for screenshot image captures
- Detects and disables the macOS screenshot floating thumbnail delay
- Optional auto-focus Codex + send `Cmd+V`
- Fast path targets the normal conversation composer without taking a window screenshot first
- Fresh-project startup screens are left manual; after the first prompt, the bridge targets the normal conversation composer
- Optional custom Codex bundle ID if app auto-detection is unreliable
- Built-in Accessibility permission status panel
- Small in-app event log for troubleshooting

## Requirements

- macOS 13 or newer
- Swift 5.10+ (if running from source)
- Accessibility permission (required only for auto-paste)

## Quick Start (Source)

```bash
swift build
swift run CodexScreenshotBridge
```

Then:
1. Click the menu-bar icon.
2. Enable `Bridge Enabled`.
3. Enable `Auto-paste into Codex`.
4. Enable `Handle clipboard screenshot shortcut` if you use clipboard screenshot shortcuts.
5. Type the first prompt manually on a fresh Codex startup screen; later screenshots auto-paste into the normal composer.
6. Use the in-app permission action if Accessibility is missing.

## Package As .app

Use the packaging script:

```bash
./scripts/package_app.sh
```

This creates:
- `~/Applications/CodexScreenshotBridge.app`

## Permissions

For automatic paste (`Cmd+V`) you must allow Accessibility access:

1. Open `System Settings` -> `Privacy & Security` -> `Accessibility`.
2. Enable `CodexScreenshotBridge` (or Terminal/Xcode if running from source).

Without this permission, clipboard copy still works but key injection is blocked by macOS.

The menu-bar window also shows the current Accessibility status and includes request/refresh actions for quick troubleshooting.

## Configuration Notes

- Default screenshot folder is read from `com.apple.screencapture location` and falls back to `~/Desktop`.
- Filename-based detection currently looks for names containing `Screenshot` or `Screen Shot`.
- Clipboard screenshot detection is independent from file watching and works for copy shortcuts.
- File-based screenshots can be delayed by the macOS floating thumbnail. Use `Disable Floating Thumbnail` in the app to make saved screenshots appear in the watched folder immediately.

## Troubleshooting

- Nothing pastes: verify Accessibility permission and keep Codex running.
- File screenshots paste several seconds late: disable the macOS floating thumbnail from the app's `Screenshot Speed` section.
- Initial Codex startup screen does not paste: enter the first prompt manually, then use the bridge in the normal conversation screen.
- App cannot find Codex: set `Codex bundle ID` in the app menu.
- File-based screenshots not detected: set the correct screenshot folder from `Choose Folder`.

## Development

Build:

```bash
swift build
```

Run the automated test suite:

```bash
./scripts/run_tests.sh
```

Release build:

```bash
swift build -c release
```

## License

MIT. See `LICENSE`.
