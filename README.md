# claude-notifier

A native macOS notification tool for [Claude Code](https://claude.ai/code). Delivers Notification Center banners for permission prompts, task completions, and questions — with action buttons you can click directly from the banner.

## Features

- **Permission prompts** — when Claude requests Bash, Write, Edit, or other tool use, a banner appears with Allow / Deny / Snooze buttons. Clicking a button injects the keystroke into your terminal automatically.
- **Task complete** — fires when a long-running Claude task finishes so you can come back to it without polling.
- **Questions** — when Claude asks a question (`AskUserQuestion`), pick an option directly from the notification.
- **Menu bar app** — optional flame icon in the menu bar with quick toggles for each notification type.
- **Settings UI** — full preferences window with per-notification-type sound and behavior controls.
- **First-run wizard** — seven-step onboarding that configures terminal detection, sounds, and notification types.
- **Sound control** — per-type sounds with a global mute toggle.

## Requirements

- macOS 13 Ventura or later
- Swift compiler (`swiftc`) — included with Xcode Command Line Tools
- [Claude Code](https://claude.ai/code) with hooks support

Install Command Line Tools if needed:

```bash
xcode-select --install
```

## Installation

### 1. Clone and build

```bash
git clone https://github.com/kirylrusetski-geotab/claude-notifier.git ~/.claude/scripts
cd ~/.claude/scripts
chmod +x build-claude-notifier.sh
./build-claude-notifier.sh
```

The build script compiles all Swift source files and signs the app bundle in place at `claude-notifier.app`.

### 2. Wire up Claude Code hooks

Add the following to your `~/.claude/settings.json` (create the file if it doesn't exist):

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/scripts/claude-notify-macos.sh"
          }
        ]
      }
    ]
  }
}
```

### 3. Run the setup wizard

Double-click `claude-notifier.app` or run:

```bash
~/.claude/scripts/claude-notifier.app/Contents/MacOS/claude-notifier
```

The wizard walks you through terminal detection, menu bar setup, notification permissions, sounds, and notification types.

## Usage

After installation the shell hook runs automatically when Claude Code fires a notification event. No further configuration is required.

### Settings

Open the preferences window at any time:

```bash
~/.claude/scripts/claude-notifier.app/Contents/MacOS/claude-notifier --settings
```

Or double-click the app after first-run setup is complete.

### Menu bar app

```bash
~/.claude/scripts/claude-notifier.app/Contents/MacOS/claude-notifier --menu-bar
```

Adds a flame icon to the menu bar with quick toggles for each notification type and a Test notification submenu.

### Test a notification

```bash
~/.claude/scripts/claude-notifier.app/Contents/MacOS/claude-notifier --test permission
~/.claude/scripts/claude-notifier.app/Contents/MacOS/claude-notifier --test task
~/.claude/scripts/claude-notifier.app/Contents/MacOS/claude-notifier --test question
```

### Send a one-off notification

```bash
~/.claude/scripts/claude-notifier.app/Contents/MacOS/claude-notifier \
  -title "My title" \
  -message "Body text" \
  -action "Yes" -action "No" \
  -sound Glass
```

Prints the clicked action label (or `@TIMEOUT`, `@DISMISSED`, `@CONTENTCLICKED`) to stdout.

## Building

```bash
./build-claude-notifier.sh
```

Source files:

| File | Purpose |
|------|---------|
| `claude-notifier.swift` | Entry point, notification delivery engine |
| `claude-notifier-config.swift` | Settings keys, defaults, and shared config store |
| `claude-notifier-settings.swift` | Settings window UI and menu bar app |
| `claude-notifier-onboarding.swift` | First-run wizard and splash screen |
| `claude-notify-macos.sh` | Shell hook called by Claude Code |
| `build-claude-notifier.sh` | Build script |

## License

MIT
