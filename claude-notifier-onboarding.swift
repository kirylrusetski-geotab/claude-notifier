import Cocoa
import SwiftUI
import UserNotifications

// MARK: - Login item management

func installLoginItem(_ enabled: Bool) {
    let plistPath = (NSHomeDirectory() as NSString)
        .appendingPathComponent("Library/LaunchAgents/com.kirylrusetski.claude-notifier.plist")
    let uid = getuid()

    if enabled {
        guard let binaryPath = Bundle.main.executablePath ?? CommandLine.arguments.first else { return }
        let plist: [String: Any] = [
            "Label": "com.kirylrusetski.claude-notifier",
            "ProgramArguments": [binaryPath, "--menu-bar"],
            "RunAtLoad": true,
        ]
        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: URL(fileURLWithPath: plistPath))
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootstrap", "gui/\(uid)", plistPath]
        try? task.run()
        task.waitUntilExit()
    } else {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootout", "gui/\(uid)/com.kirylrusetski.claude-notifier"]
        try? task.run()
        task.waitUntilExit()
        try? FileManager.default.removeItem(atPath: plistPath)
    }
}

// MARK: - Onboarding wizard

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
                Text("Claude Notifier is installed and running.")
                    .font(.title2)
                    .bold()
                Text("This app delivers Notification Center banners when Claude Code needs your attention: permission prompts, completed tasks, and questions. Let's get you set up. It takes about a minute.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 440)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct TerminalStep: View {
    @AppStorage(SettingsKey.terminalOverride) var terminalOverrideRaw: String = TerminalOverride.auto.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                icon: "terminal",
                title: "Which terminal are you using?",
                subtitle: "The notifier focuses your terminal and injects keystrokes after you respond to a permission prompt. Auto-detect reads environment variables from Claude Code. Set this manually if auto-detect picks the wrong app."
            )

            VStack(alignment: .leading, spacing: 8) {
                Picker("Terminal", selection: $terminalOverrideRaw) {
                    Text("Auto-detect").tag(TerminalOverride.auto.rawValue)
                    Text("Terminal.app").tag(TerminalOverride.terminal.rawValue)
                    Text("iTerm2").tag(TerminalOverride.iterm2.rawValue)
                    Text("kitty").tag(TerminalOverride.kitty.rawValue)
                    Text("Ghostty").tag(TerminalOverride.ghostty.rawValue)
                    Text("Warp").tag(TerminalOverride.warp.rawValue)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                if terminalOverrideRaw == TerminalOverride.kitty.rawValue {
                    Text("kitty requires allow_remote_control yes in kitty.conf for keystroke injection.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct MenuBarStep: View {
    @AppStorage(SettingsKey.menuBarStartNow) var startNow: Bool = false
    @AppStorage(SettingsKey.menuBarStartAtLogin) var startAtLogin: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                icon: "menubar.rectangle",
                title: "Menu bar app",
                subtitle: "The menu bar app adds a flame icon to your menu bar with quick toggles for each notification type. It runs silently in the background."
            )

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show menu bar icon now", isOn: $startNow)
                    .toggleStyle(.checkbox)
                Toggle("Start menu bar app automatically at login", isOn: $startAtLogin)
                    .toggleStyle(.checkbox)
            }
        }
    }
}

struct PermissionStep: View {
    @State private var authStatus: String = "Checking…"
    @State private var hasRequested = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                icon: "bell.badge",
                title: "Notification permission",
                subtitle: "Claude Notifier needs permission to display banners in Notification Center. Without it, notifications won't appear — but you can still respond to prompts in the terminal."
            )

            HStack(spacing: 12) {
                Image(systemName: authStatusIcon)
                    .font(.title2)
                    .foregroundStyle(authStatusColor)
                Text(authStatus)
                    .font(.body)
            }
            .padding(.vertical, 4)

            HStack(spacing: 12) {
                if !hasRequested {
                    Button("Request permission") {
                        requestPermission()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                } label: {
                    Label("Open System Settings…", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
            }
        }
        .onAppear { refreshStatus() }
    }

    private var authStatusIcon: String {
        switch authStatus {
        case "Granted": return "checkmark.circle.fill"
        case "Denied": return "xmark.circle.fill"
        default: return "questionmark.circle.fill"
        }
    }

    private var authStatusColor: Color {
        switch authStatus {
        case "Granted": return .green
        case "Denied": return .red
        default: return .secondary
        }
    }

    private func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    authStatus = "Granted"
                case .denied:
                    authStatus = "Denied"
                case .notDetermined:
                    authStatus = "Not requested yet"
                @unknown default:
                    authStatus = "Unknown"
                }
            }
        }
    }

    private func requestPermission() {
        hasRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            DispatchQueue.main.async { refreshStatus() }
        }
    }
}

struct SoundStep: View {
    @AppStorage(SettingsKey.soundsEnabled) var soundsEnabled: Bool = true
    @AppStorage(SettingsKey.defaultSound) var defaultSound: String = "Glass"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                icon: "speaker.wave.2",
                title: "Sounds",
                subtitle: "Play a sound with each notification to draw your attention. You can choose different sounds per notification type in Settings later."
            )

            VStack(alignment: .leading, spacing: 16) {
                Toggle("Play sounds", isOn: $soundsEnabled)
                    .toggleStyle(.checkbox)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Default sound")
                        .font(.subheadline)
                        .foregroundColor(soundsEnabled ? .primary : .secondary)

                    HStack(spacing: 8) {
                        Picker("Default sound", selection: $defaultSound) {
                            ForEach(availableSounds, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .disabled(!soundsEnabled)

                        Button {
                            NSSound(named: NSSound.Name(defaultSound))?.play()
                        } label: {
                            Image(systemName: "play.circle")
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.borderless)
                        .disabled(!soundsEnabled)
                        .accessibilityLabel("Preview \(defaultSound)")
                    }
                }
                .opacity(soundsEnabled ? 1.0 : 0.5)
            }
        }
    }
}

struct NotificationTypesStep: View {
    @AppStorage(SettingsKey.permissionEnabled)     var permissionEnabled: Bool = true
    @AppStorage(SettingsKey.taskCompleteEnabled)   var taskCompleteEnabled: Bool = true
    @AppStorage(SettingsKey.questionEnabled)       var questionEnabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                icon: "bell.badge",
                title: "Which notifications do you want?",
                subtitle: "You can change these at any time in Settings."
            )

            VStack(alignment: .leading, spacing: 16) {
                NotificationTypeRow(
                    isOn: $permissionEnabled,
                    label: "Permission prompts",
                    description: "Appears when Claude Code requests permission to run a command, write a file, or use a tool. You can Allow, Deny, or Snooze from the notification."
                )
                Divider()
                NotificationTypeRow(
                    isOn: $taskCompleteEnabled,
                    label: "Task complete",
                    description: "Fires when a long-running Claude task finishes so you can come back to it. Only triggers for tasks that took longer than a configurable minimum."
                )
                Divider()
                NotificationTypeRow(
                    isOn: $questionEnabled,
                    label: "Questions",
                    description: "Appears when Claude Code asks you a question (AskUserQuestion). You can pick an option directly from the notification."
                )
            }
        }
    }
}

private struct NotificationTypeRow: View {
    @Binding var isOn: Bool
    let label: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.body)
                    .bold()
                Text(description)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct DoneStep: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("You're all set.")
                    .font(.title2)
                    .bold()
                Text("Claude Notifier is configured and will run in the background. You can change any setting at any time by double-clicking the app or using the menu bar icon.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 440)

                Button("Open Settings") {
                    onOpenSettings()
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shared header

private struct StepHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.title3)
                .bold()
            Text(subtitle)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Root wizard view

struct OnboardingRootView: View {
    @State private var currentStep = 0
    @State private var insertionEdge: Edge = .trailing
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    let onFinish: () -> Void

    private let totalSteps = 7

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: insertionEdge),
            removal: .move(edge: insertionEdge == .trailing ? .leading : .trailing)
        )
    }

    private func advance(by delta: Int) {
        insertionEdge = delta > 0 ? .trailing : .leading
        if reduceMotion {
            currentStep += delta
        } else {
            withAnimation(.easeInOut(duration: 0.22)) { currentStep += delta }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Step content — .id forces SwiftUI to treat each step as a distinct
            // view so insertion/removal transitions fire on every step change.
            Group {
                switch currentStep {
                case 0: WelcomeStep()
                case 1: TerminalStep()
                case 2: MenuBarStep()
                case 3: PermissionStep()
                case 4: SoundStep()
                case 5: NotificationTypesStep()
                default: DoneStep(onOpenSettings: {
                    launchSelf(["--settings"])
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onFinish() }
                })
                }
            }
            .id(currentStep)
            .transition(stepTransition)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 40)
            .padding(.top, 32)
            .padding(.bottom, 16)

            Divider()

            // Footer
            HStack {
                // Skip button — available on all steps except Done
                if currentStep < totalSteps - 1 {
                    Button("Skip setup") {
                        onFinish()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                }

                Spacer()

                // Step indicator: dots + count label
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        ForEach(0..<totalSteps, id: \.self) { i in
                            Circle()
                                .fill(i == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .accessibilityHidden(true)

                    Text("Step \(currentStep + 1) of \(totalSteps)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                }

                Spacer()

                if currentStep > 0 {
                    Button("Back") {
                        advance(by: -1)
                    }
                    .buttonStyle(.bordered)
                }

                if currentStep < totalSteps - 1 {
                    Button("Next") {
                        if currentStep == 2 {
                            applyMenuBarSideEffects()
                        }
                        advance(by: 1)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Close") {
                        onFinish()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 16)
            .accessibilityElement(children: .contain)
            .accessibilityValue("Step \(currentStep + 1) of \(totalSteps)")
        }
    }

    private func applyMenuBarSideEffects() {
        let s = NotifierSettings.shared
        let startNow = s.bool(SettingsKey.menuBarStartNow)
        let startAtLogin = s.bool(SettingsKey.menuBarStartAtLogin)

        if startNow {
            launchSelf(["--menu-bar"])
        }
        installLoginItem(startAtLogin)
    }
}

// MARK: - Onboarding app delegate

class OnboardingAppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rootView = OnboardingRootView {
            NotifierSettings.shared.setBool(SettingsKey.onboardingCompleted, true)
            NSApp.terminate(nil)
        }
        .frame(width: 640, height: 520)
        let hosting = NSHostingController(rootView: rootView)
        window = NSWindow(contentViewController: hosting)
        window.title = "Claude Notifier Setup"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

func runOnboardingApp() -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = OnboardingAppDelegate()
    app.delegate = delegate
    app.run()
    exit(0)
}

// MARK: - Splash screen

struct SplashView: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "flame.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Claude Notifier is running")
                .font(.title3)
                .bold()

            Text("Notifications appear in Notification Center when Claude needs your input or finishes a task.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)

            Button("Open Settings") {
                onOpenSettings()
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 320)
    }
}

class SplashAppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    private var dismissTimer: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let splashView = SplashView {
            self.dismissTimer?.cancel()
            launchSelf(["--settings"])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.terminate(nil)
            }
        }
        let hosting = NSHostingController(rootView: splashView)
        window = NSWindow(contentViewController: hosting)
        window.title = ""
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let item = DispatchWorkItem { NSApp.terminate(nil) }
        dismissTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

func runSplashApp() -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = SplashAppDelegate()
    app.delegate = delegate
    app.run()
    exit(0)
}
