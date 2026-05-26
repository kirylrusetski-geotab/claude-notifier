import Cocoa
import SwiftUI

// Self-launches a child claude-notifier process with the given args. Used by
// test buttons and (later) the menu bar's "Test notification" submenu. Output
// is discarded — the child writes its own banner.
func launchSelf(_ args: [String]) {
    guard let path = Bundle.main.executablePath ?? CommandLine.arguments.first else { return }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = args
    task.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
    task.standardError = FileHandle(forWritingAtPath: "/dev/null")
    do { try task.run() } catch {
        fputs("Failed to launch test: \(error)\n", stderr)
    }
}

func currentEffectiveSound(override: String, fallback: String? = nil) -> String {
    NotifierSettings.shared.effectiveSound(for: override, fallback: fallback)
}

// MARK: - Reusable controls

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.headline)
            .bold()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

// All form controls share this width so the right edge of pickers, text
// fields, and number fields stays aligned across rows.
private let controlWidth: CGFloat = 240
private let labelWidth: CGFloat = 220

private struct LabeledRow<Content: View>: View {
    let label: String
    let help: String?
    @ViewBuilder var content: () -> Content

    init(_ label: String, help: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.help = help
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                    .frame(width: labelWidth, alignment: .leading)
                content()
                    .frame(maxWidth: controlWidth, alignment: .leading)
                Spacer(minLength: 0)
            }
            if let help = help {
                Text(help)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, labelWidth + 12)
                    .padding(.trailing, 4)
            }
        }
    }
}

private struct NumberField: View {
    @Binding var value: Int
    var label: String = ""

    var body: some View {
        HStack(spacing: 0) {
            TextField("", value: $value, formatter: {
                let f = NumberFormatter()
                f.numberStyle = .none
                f.allowsFloats = false
                return f
            }())
            .multilineTextAlignment(.leading)
            .textFieldStyle(.roundedBorder)
            .frame(width: 100)
            .accessibilityLabel(label)
            Spacer(minLength: 0)
        }
    }
}

private struct SoundPicker: View {
    @Binding var selection: String
    var includeUseDefault: Bool
    var defaultFallback: String = ""

    private var soundToPlay: String {
        if selection != SettingsKey.useDefaultSound && !selection.isEmpty { return selection }
        if !defaultFallback.isEmpty { return defaultFallback }
        return NotifierSettings.shared.string(SettingsKey.defaultSound)
    }

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $selection) {
                if includeUseDefault {
                    Text("Use default").tag(SettingsKey.useDefaultSound)
                }
                ForEach(availableSounds, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()

            Button {
                NSSound(named: NSSound.Name(soundToPlay))?.play()
            } label: {
                Image(systemName: "play.circle")
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderless)
            .help("Preview \(soundToPlay)")
            .accessibilityLabel("Preview \(soundToPlay)")

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Tabs

struct GeneralTab: View {
    @AppStorage(SettingsKey.appDisplayName)   var appDisplayName: String = "GIA Desktop"
    @AppStorage(SettingsKey.titleSource)      var titleSourceRaw: String = TitleSource.tabName.rawValue
    @AppStorage(SettingsKey.titleFixedText)   var titleFixedText: String = "Claude Code"
    @AppStorage(SettingsKey.defaultSound)     var defaultSound: String = "Glass"
    @AppStorage(SettingsKey.terminalOverride) var terminalOverrideRaw: String = TerminalOverride.auto.rawValue
    @AppStorage(SettingsKey.soundsEnabled)    var soundsEnabled: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Notification context")
                LabeledRow("Source",
                           help: "Sets the subtitle shown in each notification (e.g. \"❋ GIA Claude · Edit\").\n• Terminal tab name: reads your active tab title, useful when multiple sessions are open.\n• Fixed text: shows the same label on every notification.") {
                    Picker("", selection: $titleSourceRaw) {
                        Text("Terminal tab name").tag(TitleSource.tabName.rawValue)
                        Text("Fixed text").tag(TitleSource.fixed.rawValue)
                    }
                    .labelsHidden()
                    .accessibilityLabel("Notification context source")
                }
                if titleSourceRaw == TitleSource.fixed.rawValue {
                    LabeledRow("Fixed context text",
                               help: "Shown in the notification subtitle when source is set to Fixed text.") {
                        TextField("", text: $titleFixedText)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Fixed notification context")
                    }
                }

                Divider().padding(.vertical, 4)

                SectionHeader(title: "Terminal")
                LabeledRow("Override",
                           help: "Auto-detect identifies your terminal automatically. Set this if it picks the wrong one, for example when Claude Code is launched via a script or multiple terminals are open.") {
                    Picker("", selection: $terminalOverrideRaw) {
                        Text("Auto-detect").tag(TerminalOverride.auto.rawValue)
                        Text("Terminal.app").tag(TerminalOverride.terminal.rawValue)
                        Text("iTerm2").tag(TerminalOverride.iterm2.rawValue)
                        Text("kitty").tag(TerminalOverride.kitty.rawValue)
                        Text("Ghostty").tag(TerminalOverride.ghostty.rawValue)
                        Text("Warp").tag(TerminalOverride.warp.rawValue)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                Divider().padding(.vertical, 4)

                LabeledRow("Play sounds",
                           help: "Turn off to silence every notification regardless of the sound chosen below.") {
                    Toggle("", isOn: $soundsEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                LabeledRow("Default sound",
                           help: "Used by any notification type whose Sound is set to \"Use default\".") {
                    SoundPicker(selection: $defaultSound, includeUseDefault: false)
                }
                .disabled(!soundsEnabled)
                .opacity(soundsEnabled ? 1.0 : 0.5)
            }
            .padding(20)
        }
    }
}

struct PermissionTab: View {
    @AppStorage(SettingsKey.permissionEnabled)     var enabled: Bool = true
    @AppStorage(SettingsKey.permissionSound)       var sound: String = ""
    @AppStorage(SettingsKey.permissionAllowLabel)  var allowLabel: String = "Allow"
    @AppStorage(SettingsKey.permissionDenyLabel)   var denyLabel: String = "Deny"
    @AppStorage(SettingsKey.permissionSnoozeLabel) var snoozeLabel: String = "Snooze"
    @AppStorage(SettingsKey.permissionMaxWait)     var maxWait: Int = 1800
    @AppStorage(SettingsKey.permissionKeepFocus)   var keepFocus: Bool = false
    @AppStorage(SettingsKey.snoozeDurationSeconds) var snoozeDuration: Int = 300

    @State private var showAdvanced = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Show permission notifications", isOn: $enabled)
                        .toggleStyle(.switch)
                    Text(enabled
                         ? "Permission notifications are active. Claude permission prompts (Bash, Write, Edit, etc.) will appear in Notification Center."
                         : "When off, Claude permission prompts (Bash, Write, Edit, etc.) won't trigger a notification — you'll only see them in the terminal.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Divider().padding(.vertical, 4)

                    LabeledRow("Sound",
                               help: "Sound played when a permission notification appears. \"Use default\" falls back to the sound set on the General tab.") {
                        SoundPicker(selection: $sound, includeUseDefault: true)
                    }

                    Divider().padding(.vertical, 4)

                    SectionHeader(title: "Behavior")
                    LabeledRow("After clicking Allow or Deny",
                               help: "Off: focus jumps to the terminal so you can see Claude's next step. On: the keystroke still goes to the terminal, but focus snaps back to whatever app you were in.") {
                        Toggle("Keep focus in current app", isOn: $keepFocus)
                            .toggleStyle(.switch)
                    }

                    Divider().padding(.vertical, 4)

                    SectionHeader(title: "Timing")
                    LabeledRow("Max wait (seconds)",
                               help: "How long the notification stays interactive before timing out. After this, focus returns to the terminal so you can respond there.") {
                        NumberField(value: $maxWait, label: "Max wait (seconds)")
                    }
                    LabeledRow("Snooze duration (seconds)",
                               help: "If you click Snooze, the same prompt re-fires after this many seconds.") {
                        NumberField(value: $snoozeDuration, label: "Snooze duration (seconds)")
                    }

                    Divider().padding(.vertical, 4)

                    DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Action Labels")
                            Text("Renaming these requires updating the shell hook to match.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            LabeledRow("Allow label") {
                                TextField("", text: $allowLabel)
                                    .textFieldStyle(.roundedBorder)
                            }
                            LabeledRow("Deny label") {
                                TextField("", text: $denyLabel)
                                    .textFieldStyle(.roundedBorder)
                            }
                            LabeledRow("Snooze label") {
                                TextField("", text: $snoozeLabel)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(.top, 8)
                    }

                    Divider().padding(.vertical, 4)

                    HStack {
                        Spacer()
                        Button("Send a test prompt") {
                            launchSelf(["--test", "permission"])
                        }
                    }
                }
                .disabled(!enabled)
                .opacity(enabled ? 1.0 : 0.5)
            }
            .padding(20)
        }
    }
}

struct TaskCompleteTab: View {
    @AppStorage(SettingsKey.taskCompleteEnabled)     var enabled: Bool = true
    @AppStorage(SettingsKey.taskCompleteMinDuration) var minDuration: Int = 30
    @AppStorage(SettingsKey.taskCompleteSound)       var sound: String = "Ping"
    @AppStorage(SettingsKey.taskCompleteTimeout)     var timeout: Int = 10

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Show task-complete notifications", isOn: $enabled)
                        .toggleStyle(.switch)
                    Text(enabled
                         ? "Task-complete notifications are active. You'll be notified when long-running Claude tasks finish."
                         : "When off, you won't be notified when a long-running Claude task finishes.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Divider().padding(.vertical, 4)

                    LabeledRow("Sound",
                               help: "Sound played when a task-complete notification appears.") {
                        SoundPicker(selection: $sound, includeUseDefault: true)
                    }

                    Divider().padding(.vertical, 4)

                    SectionHeader(title: "Behavior")
                    LabeledRow("Minimum task duration (s)",
                               help: "Only tasks that ran at least this many seconds trigger a notification. Set higher to avoid pings for quick commands.") {
                        NumberField(value: $minDuration, label: "Minimum task duration (seconds)")
                    }
                    LabeledRow("Notification timeout (s)",
                               help: "How long the banner stays on screen before auto-dismissing.") {
                        NumberField(value: $timeout, label: "Notification timeout (seconds)")
                    }

                    Divider().padding(.vertical, 4)

                    HStack {
                        Spacer()
                        Button("Send a test notification") {
                            launchSelf(["--test", "task"])
                        }
                    }
                }
                .disabled(!enabled)
                .opacity(enabled ? 1.0 : 0.5)
            }
            .padding(20)
        }
    }
}

struct QuestionsTab: View {
    @AppStorage(SettingsKey.questionEnabled)         var enabled: Bool = true
    @AppStorage(SettingsKey.questionSound)           var sound: String = ""
    @AppStorage(SettingsKey.questionMaxWait)         var maxWait: Int = 1800
    @AppStorage(SettingsKey.questionMultiSelectMode) var multiSelectModeRaw: String = MultiSelectMode.notifyOnly.rawValue
    @AppStorage(SettingsKey.questionKeepFocus)       var keepFocus: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Show question notifications", isOn: $enabled)
                        .toggleStyle(.switch)
                    Text(enabled
                         ? "Question notifications are active. AskUserQuestion prompts will appear in Notification Center."
                         : "When off, AskUserQuestion prompts won't trigger a notification — focus jumps straight to the terminal so you can answer there.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Divider().padding(.vertical, 4)

                    LabeledRow("Sound",
                               help: "Sound played when a question notification appears. \"Use default\" falls back to the sound set on the General tab.") {
                        SoundPicker(selection: $sound, includeUseDefault: true)
                    }

                    Divider().padding(.vertical, 4)

                    SectionHeader(title: "Behavior")
                    LabeledRow("After picking an option",
                               help: "Off: focus jumps to the terminal after the selection lands. On: the keystroke still goes to the terminal, but focus snaps back to whatever app you were in.") {
                        Toggle("Keep focus in current app", isOn: $keepFocus)
                            .toggleStyle(.switch)
                    }

                    Divider().padding(.vertical, 4)

                    SectionHeader(title: "Timing")
                    LabeledRow("Max wait (seconds)",
                               help: "How long the notification stays interactive before timing out and returning focus to the terminal.") {
                        NumberField(value: $maxWait, label: "Max wait (seconds)")
                    }

                    Divider().padding(.vertical, 4)

                    SectionHeader(title: "Multi-select fallback")
                    LabeledRow("When multi-select",
                               help: "Notification Center can't render multi-select inline. Pick what happens instead.") {
                        Picker("", selection: $multiSelectModeRaw) {
                            Text("Notify, then focus terminal").tag(MultiSelectMode.notifyOnly.rawValue)
                            Text("Open terminal silently").tag(MultiSelectMode.focusTerminal.rawValue)
                        }
                        .labelsHidden()
                    }

                    Divider().padding(.vertical, 4)

                    HStack {
                        Spacer()
                        Button("Send a test question") {
                            launchSelf(["--test", "question"])
                        }
                    }
                }
                .disabled(!enabled)
                .opacity(enabled ? 1.0 : 0.5)
            }
            .padding(20)
        }
    }
}

struct AboutTab: View {
    @State private var showResetConfirm = false
    @State private var menuBarRunning: Bool = false
    @State private var launchObserver: NSObjectProtocol? = nil
    @State private var terminateObserver: NSObjectProtocol? = nil

    var bundleID: String { Bundle.main.bundleIdentifier ?? "unknown" }

    private func isMenuBarRunning() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { !$0.isEqual(NSRunningApplication.current) }
    }
    var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown" }
    var scriptPath: String { "~/.claude/scripts/claude-notify-macos.sh" }
    var configPath: String { "~/Library/Preferences/\(bundleID).plist" }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Build")
                    LabeledRow("Version") {
                        Text(version).foregroundColor(.secondary)
                    }
                    LabeledRow("Bundle ID") {
                        Text(bundleID).foregroundColor(.secondary).textSelection(.enabled)
                    }

                    Divider().padding(.vertical, 4)

                    SectionHeader(title: "Paths")
                    LabeledRow("Hook script") {
                        Text(scriptPath)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .font(.system(.footnote, design: .monospaced))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    LabeledRow("Settings file") {
                        Text(configPath)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .font(.system(.footnote, design: .monospaced))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider().padding(.vertical, 4)

                    LabeledRow("Menu bar app",
                               help: "Adds a flame icon to the menu bar with quick toggles. Runs in the background unless you quit Claude Notifier.") {
                        Toggle("", isOn: Binding(
                            get: { menuBarRunning },
                            set: { newVal in
                                if newVal {
                                    launchSelf(["--menu-bar"])
                                } else {
                                    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                                        .first { !$0.isEqual(NSRunningApplication.current) }?
                                        .terminate()
                                }
                                menuBarRunning = newVal
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }

                    Divider().padding(.vertical, 4)

                    HStack(spacing: 8) {
                        Button("Open shell script in editor") {
                            let expanded = (scriptPath as NSString).expandingTildeInPath
                            NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
                        }
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 8) {
                        Button("Re-run setup wizard") {
                            launchSelf(["--onboarding"])
                        }
                        .help("Re-open the first-time setup wizard to reconfigure terminal, sounds, and notification types.")
                        Spacer(minLength: 0)
                    }

                    // System-navigation action (opens another app — marked with external-link icon)
                    HStack(spacing: 8) {
                        Button {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        } label: {
                            Label("System Notification Settings…", systemImage: "arrow.up.right.square")
                        }
                        .help("Open System Settings → Notifications to manage alert style and permissions for Claude Notifier.")
                        Spacer(minLength: 0)
                    }
                }
                .padding(20)
            }

            // Destructive action anchored to the bottom, visually separated from utility buttons
            Divider()
            HStack {
                Spacer()
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label("Reset all to defaults", systemImage: "trash")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .alert("Reset all settings?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                NotifierSettings.shared.resetAll()
            }
        } message: {
            Text("This clears every customization and falls back to the bundled defaults.")
        }
        .onAppear {
            menuBarRunning = isMenuBarRunning()
            let nc = NSWorkspace.shared.notificationCenter
            launchObserver = nc.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil, queue: .main) { _ in menuBarRunning = isMenuBarRunning() }
            terminateObserver = nc.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil, queue: .main) { _ in menuBarRunning = isMenuBarRunning() }
        }
        .onDisappear {
            let nc = NSWorkspace.shared.notificationCenter
            if let obs = launchObserver    { nc.removeObserver(obs) }
            if let obs = terminateObserver { nc.removeObserver(obs) }
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case permissions = "Permission Prompts"
    case taskComplete = "Task Complete"
    case questions = "Questions"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general:      return "gear"
        case .permissions:  return "lock.shield"
        case .taskComplete: return "checkmark.circle"
        case .questions:    return "questionmark.circle"
        case .about:        return "info.circle"
        }
    }
}

struct SettingsRootView: View {
    @State private var selection: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .font(.system(size: 13))
                    .padding(.vertical, 2)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            Group {
                switch selection {
                case .general:      GeneralTab()
                case .permissions:  PermissionTab()
                case .taskComplete: TaskCompleteTab()
                case .questions:    QuestionsTab()
                case .about:        AboutTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle(selection.rawValue)
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 520, idealHeight: 580)
    }
}

class SettingsAppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hosting = NSHostingController(rootView: SettingsRootView())
        window = NSWindow(contentViewController: hosting)
        window.title = "Claude Notifier"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = false
        window.setContentSize(NSSize(width: 820, height: 580))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

func runSettingsApp() -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = SettingsAppDelegate()
    app.delegate = delegate
    app.run()
    exit(0)
}

// MARK: - Menu bar app

class MenuBarController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindowController: NSWindowController?

    // Held strong so .state can be flipped in place when the user changes a
    // setting elsewhere (e.g. opens settings, toggles, comes back to the menu).
    private var permItem: NSMenuItem!
    private var taskItem: NSMenuItem!
    private var questionItem: NSMenuItem!

    private let observedKeys = [
        SettingsKey.permissionEnabled,
        SettingsKey.taskCompleteEnabled,
        SettingsKey.questionEnabled,
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: "Claude Notifier")
            button.toolTip = "Claude Notifier"
        }
        buildMenu()

        for key in observedKeys {
            UserDefaults.standard.addObserver(self, forKeyPath: key, options: .new, context: nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        for key in observedKeys {
            UserDefaults.standard.removeObserver(self, forKeyPath: key)
        }
    }

    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        guard let key = keyPath, observedKeys.contains(key) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.updateToggleStates()
        }
    }

    private func updateToggleStates() {
        let s = NotifierSettings.shared
        permItem?.state     = s.bool(SettingsKey.permissionEnabled)   ? .on : .off
        taskItem?.state     = s.bool(SettingsKey.taskCompleteEnabled) ? .on : .off
        questionItem?.state = s.bool(SettingsKey.questionEnabled)     ? .on : .off
    }

    private func buildMenu() {
        let menu = NSMenu()
        let s = NotifierSettings.shared

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: "Settings")
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        permItem = NSMenuItem(title: "Permission prompts", action: #selector(togglePermission), keyEquivalent: "")
        permItem.target = self
        permItem.state = s.bool(SettingsKey.permissionEnabled) ? .on : .off
        permItem.toolTip = "Toggle permission prompt notifications"
        menu.addItem(permItem)

        taskItem = NSMenuItem(title: "Task complete", action: #selector(toggleTask), keyEquivalent: "")
        taskItem.target = self
        taskItem.state = s.bool(SettingsKey.taskCompleteEnabled) ? .on : .off
        taskItem.toolTip = "Toggle task-complete notifications"
        menu.addItem(taskItem)

        questionItem = NSMenuItem(title: "Questions", action: #selector(toggleQuestion), keyEquivalent: "")
        questionItem.target = self
        questionItem.state = s.bool(SettingsKey.questionEnabled) ? .on : .off
        questionItem.toolTip = "Toggle question notifications"
        menu.addItem(questionItem)

        let testRoot = NSMenuItem(title: "Test notification", action: nil, keyEquivalent: "")
        let testSubmenu = NSMenu()
        let permTest = NSMenuItem(title: "Permission prompt", action: #selector(testPermission), keyEquivalent: "")
        permTest.target = self
        testSubmenu.addItem(permTest)
        let taskTest = NSMenuItem(title: "Task complete", action: #selector(testTask), keyEquivalent: "")
        taskTest.target = self
        testSubmenu.addItem(taskTest)
        let questionTest = NSMenuItem(title: "Question", action: #selector(testQuestion), keyEquivalent: "")
        questionTest.target = self
        testSubmenu.addItem(questionTest)
        testRoot.submenu = testSubmenu
        menu.addItem(testRoot)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Claude Notifier", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func togglePermission() {
        let s = NotifierSettings.shared
        s.setBool(SettingsKey.permissionEnabled, !s.bool(SettingsKey.permissionEnabled))
    }

    @objc private func toggleTask() {
        let s = NotifierSettings.shared
        s.setBool(SettingsKey.taskCompleteEnabled, !s.bool(SettingsKey.taskCompleteEnabled))
    }

    @objc private func toggleQuestion() {
        let s = NotifierSettings.shared
        s.setBool(SettingsKey.questionEnabled, !s.bool(SettingsKey.questionEnabled))
    }

    @objc private func openSettings() {
        // Self-launch a separate process so the settings window runs in its
        // own NSApplication context (regular activation policy + dock icon)
        // without disrupting the menu bar app's accessory mode.
        launchSelf(["--settings"])
    }

    @objc private func testPermission() { launchSelf(["--test", "permission"]) }
    @objc private func testTask()       { launchSelf(["--test", "task"]) }
    @objc private func testQuestion()   { launchSelf(["--test", "question"]) }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

func runMenuBarApp() -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let controller = MenuBarController()
    app.delegate = controller
    app.run()
    exit(0)
}

func soundArgIfEnabled(_ sound: String) -> [String] {
    guard NotifierSettings.shared.bool(SettingsKey.soundsEnabled) else { return [] }
    return ["-sound", sound]
}

// Test buttons fire a real notification with the user's current settings.
func runTestNotification(kind: String) -> Never {
    let s = NotifierSettings.shared
    let title = "Claude Notifier"
    var args: [String] = []

    switch kind {
    case "permission":
        let allow  = s.string(SettingsKey.permissionAllowLabel)
        let deny   = s.string(SettingsKey.permissionDenyLabel)
        let snooze = s.string(SettingsKey.permissionSnoozeLabel)
        args = [
            "-title", title,
            "-subtitle", "Bash",
            "-message", "TEST: rm -rf /tmp/example",
            "-action", allow, "-action", deny, "-action", snooze,
            "-max-wait", String(s.int(SettingsKey.permissionMaxWait)),
        ] + soundArgIfEnabled(currentEffectiveSound(override: s.string(SettingsKey.permissionSound)))
    case "task":
        args = [
            "-title", title,
            "-message", "TEST: task complete",
            "-timeout", String(s.int(SettingsKey.taskCompleteTimeout)),
        ] + soundArgIfEnabled(currentEffectiveSound(override: s.string(SettingsKey.taskCompleteSound), fallback: "Ping"))
    case "question":
        args = [
            "-title", title,
            "-subtitle", "Question",
            "-message", "TEST: which option do you prefer?",
            "-action", "Option A", "-action", "Option B", "-action", "Option C",
            "-max-wait", String(s.int(SettingsKey.questionMaxWait)),
        ] + soundArgIfEnabled(currentEffectiveSound(override: s.string(SettingsKey.questionSound)))
    default:
        fputs("Unknown test kind '\(kind)'. Use: permission | task | question\n", stderr)
        exit(2)
    }

    var argv = [CommandLine.arguments.first ?? "claude-notifier"]
    argv.append(contentsOf: args)
    runNotificationModeWith(argv: argv)
}

func parseActionLabels(argv: [String]) -> [String] {
    var labels: [String] = []
    var i = 1
    while i < argv.count - 1 {
        if argv[i] == "-action" {
            labels.append(argv[i + 1])
            i += 2
        } else {
            i += 1
        }
    }
    if labels.isEmpty {
        let csv = parseFlags(argv: argv)["actions"] ?? ""
        if !csv.isEmpty { labels = csv.split(separator: ",").map(String.init) }
    }
    return labels
}

func runNotificationModeWith(argv: [String]) -> Never {
    let parsed = parseFlags(argv: argv)
    let app = NSApplication.shared
    let delegate = NotificationAppDelegate(
        title: parsed["title"] ?? "Claude Code",
        message: parsed["message"] ?? "",
        subtitle: parsed["subtitle"] ?? "",
        sound: parsed["sound"] ?? "Glass",
        actionLabels: parseActionLabels(argv: argv),
        timeout: Double(parsed["timeout"] ?? "0") ?? 0,
        maxWaitForAction: Double(parsed["max-wait"] ?? "1800") ?? 1800
    )
    app.delegate = delegate
    app.run()
    exit(0)
}

func parseFlags(argv: [String]) -> [String: String] {
    var result: [String: String] = [:]
    var i = 1
    while i < argv.count {
        let key = argv[i]
        guard key.hasPrefix("-"), i + 1 < argv.count else {
            i += 1
            continue
        }
        result[String(key.dropFirst())] = argv[i + 1]
        i += 2
    }
    return result
}
