# Claude Notifier

<img width="512" height="512" alt="AppIcon" src="https://github.com/user-attachments/assets/3b74c8ec-34cf-4bc5-9a51-9452d2e10144" />

A native macOS notification tool for [Claude Code](https://claude.ai/code). 

Delivers Notification Center banners for permission prompts, task completions, and questions with action buttons you can click directly from the banner.

## Features

- **Permission prompts** — when Claude requests Bash, Write, Edit, or other tool use, a banner appears with Allow / Deny / Snooze buttons. Clicking a button injects the keystroke into your terminal automatically.
- **Task complete** — fires when a long-running Claude task finishes so you can come back to it without polling.
- **Questions** — when Claude asks a question (`AskUserQuestion`), pick an option directly from the notification.
- **Menu bar app** — optional flame icon in the menu bar with quick toggles for each notification type.
- **Settings UI** — full preferences window with per-notification-type sound and behavior controls.
- **First-run wizard** — seven-step onboarding that configures terminal detection, sounds, and notification types.
- **Sound control** — per-type sounds with a global mute toggle.

<img width="376" height="217" alt="Screenshot 2026-05-26 at 4 13 05 PM" src="https://github.com/user-attachments/assets/94d0e711-d3ea-4df9-b9e6-a8c050951ca0" />


*Push notification example that appears when Claude needs your input before actioning.*


<img width="821" height="552" alt="Screenshot 2026-05-26 at 4 14 15 PM" src="https://github.com/user-attachments/assets/78a19297-1d49-46e7-97b5-3086e18fb374" />


*Settings screen showcasing the options for notifications, giving control to the user, having them set the notifications up to work for them.*


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

The source code is plain Swift files with no dependencies. The build script compiles them into a native macOS app bundle (`claude-notifier.app`) using the Swift compiler that ships with Xcode Command Line Tools, then signs it so macOS will run it without Gatekeeper warnings.

```bash
git clone https://github.com/kirylrusetski-geotab/claude-notifier.git ~/.claude/scripts
cd ~/.claude/scripts
chmod +x build-claude-notifier.sh
./build-claude-notifier.sh
```

The app bundle is created at `~/.claude/scripts/claude-notifier.app`. You don't need to move it anywhere — the hook script references it by that path.

### 2. Wire up Claude Code hooks

Claude Code has a hooks system that runs shell commands in response to events. This step tells Claude Code to call the notifier's shell script on two events:

- **`Notification`** (matched to `permission_prompt|idle_prompt`) — fires when Claude is waiting for your input, either at a permission prompt or because it has gone idle. This is what triggers the interactive banners with Allow / Deny / Snooze buttons.
- **`Stop`** — fires when a Claude task finishes. This is what triggers the task-complete notification so you know to come back.

Merge the following into your `~/.claude/settings.json` (create the file if it doesn't exist, or add the `hooks` key alongside any existing keys):

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "permission_prompt|idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/scripts/claude-notify-macos.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/scripts/claude-notify-macos.sh"
          }
        ]
      }
    ]
  }
}
```

> **Note:** If `settings.json` already exists, merge the `hooks` block into it rather than replacing the file — other keys like `model` or `statusLine` should be preserved.

### 3. Run the setup wizard

The app needs one-time configuration before it can deliver notifications. The wizard covers:

- **Terminal detection** — the notifier injects keystrokes into your terminal after you click Allow or Deny on a permission prompt. It needs to know which terminal app you use (Terminal.app, iTerm2, Ghostty, etc.) so it can target the right window.
- **Menu bar app** — optionally starts a background process that adds a flame icon to your menu bar with quick toggles for each notification type.
- **Notification permission** — macOS requires explicit permission before any app can show Notification Center banners. The wizard requests this and confirms it was granted.
- **Sounds** — choose whether notifications play a sound and which one.
- **Notification types** — enable or disable permission prompts, task-complete, and question notifications individually.

Double-click `claude-notifier.app` or run:

```bash
~/.claude/scripts/claude-notifier.app/Contents/MacOS/claude-notifier
```

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

## License

GPL v3 — see [LICENSE](LICENSE).

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
