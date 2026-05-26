import Foundation
import SwiftUI

enum TitleSource: String, CaseIterable {
    case tabName = "tabName"
    case fixed = "fixed"
}

enum MultiSelectMode: String, CaseIterable {
    case notifyOnly = "notifyOnly"
    case focusTerminal = "focusTerminal"
}

enum TerminalOverride: String, CaseIterable {
    case auto     = "auto"
    case terminal = "terminal"
    case iterm2   = "iterm2"
    case kitty    = "kitty"
    case ghostty  = "ghostty"
    case warp     = "warp"
}

let availableSounds = ["Glass", "Ping", "Hero", "Submarine", "Tink", "Pop", "Purr", "Sosumi", "Blow", "Bottle", "Frog", "Morse"]

// All settings keys live here so resetAll() and the shell side can stay in sync.
enum SettingsKey {
    static let appDisplayName          = "appDisplayName"
    static let titleSource             = "titleSource"
    static let titleFixedText          = "titleFixedText"
    static let defaultSound            = "defaultSound"

    static let permissionEnabled       = "permissionEnabled"
    static let permissionSound         = "permissionSound"
    static let permissionAllowLabel    = "permissionAllowLabel"
    static let permissionDenyLabel     = "permissionDenyLabel"
    static let permissionSnoozeLabel   = "permissionSnoozeLabel"
    static let permissionMaxWait       = "permissionMaxWait"
    static let permissionKeepFocus     = "permissionKeepFocus"
    static let snoozeDurationSeconds   = "snoozeDurationSeconds"

    static let taskCompleteEnabled     = "taskCompleteEnabled"
    static let taskCompleteMinDuration = "taskCompleteMinDuration"
    static let taskCompleteSound       = "taskCompleteSound"
    static let taskCompleteTimeout     = "taskCompleteTimeout"

    static let questionEnabled         = "questionEnabled"
    static let questionSound           = "questionSound"
    static let questionMaxWait         = "questionMaxWait"
    static let questionMultiSelectMode = "questionMultiSelectMode"
    static let questionKeepFocus       = "questionKeepFocus"

    static let terminalOverride        = "terminalOverride"

    static let onboardingCompleted     = "onboardingCompleted"
    static let soundsEnabled           = "soundsEnabled"
    static let menuBarStartNow         = "menuBarStartNow"
    static let menuBarStartAtLogin     = "menuBarStartAtLogin"

    // Sentinel value meaning "use the global default sound". Stored in per-type
    // sound keys (permissionSound, questionSound) when the user selects "Use default".
    static let useDefaultSound         = "__default__"

    static let all: [String] = [
        appDisplayName, titleSource, titleFixedText, defaultSound,
        permissionEnabled, permissionSound, permissionAllowLabel,
        permissionDenyLabel, permissionSnoozeLabel, permissionMaxWait,
        permissionKeepFocus, snoozeDurationSeconds,
        taskCompleteEnabled, taskCompleteMinDuration, taskCompleteSound,
        taskCompleteTimeout,
        questionEnabled, questionSound, questionMaxWait,
        questionMultiSelectMode, questionKeepFocus,
        terminalOverride,
        onboardingCompleted, soundsEnabled, menuBarStartNow, menuBarStartAtLogin,
    ]
}

// Shared settings store. SwiftUI Views read/write via @AppStorage bindings
// keyed on the same UserDefaults keys; non-View Swift code reads via the
// helpers below; the shell reads via `defaults read com.kirylrusetski.claude-notifier <key>`.
final class NotifierSettings: ObservableObject {
    static let shared = NotifierSettings()
    private let defaults = UserDefaults.standard

    private init() {
        // Seed defaults so first read from shell or SwiftUI has a value.
        let seeds: [String: Any] = [
            SettingsKey.appDisplayName: "GIA Desktop",
            SettingsKey.titleSource: TitleSource.tabName.rawValue,
            SettingsKey.titleFixedText: "Claude Code",
            SettingsKey.defaultSound: "Glass",
            SettingsKey.permissionEnabled: true,
            SettingsKey.permissionSound: SettingsKey.useDefaultSound,
            SettingsKey.permissionAllowLabel: "Allow",
            SettingsKey.permissionDenyLabel: "Deny",
            SettingsKey.permissionSnoozeLabel: "Snooze",
            SettingsKey.permissionMaxWait: 1800,
            SettingsKey.permissionKeepFocus: false,
            SettingsKey.snoozeDurationSeconds: 300,
            SettingsKey.taskCompleteEnabled: true,
            SettingsKey.taskCompleteMinDuration: 30,
            SettingsKey.taskCompleteSound: "Ping",
            SettingsKey.taskCompleteTimeout: 10,
            SettingsKey.questionEnabled: true,
            SettingsKey.questionSound: SettingsKey.useDefaultSound,
            SettingsKey.questionMaxWait: 1800,
            SettingsKey.questionMultiSelectMode: MultiSelectMode.notifyOnly.rawValue,
            SettingsKey.questionKeepFocus: false,
            SettingsKey.terminalOverride: TerminalOverride.auto.rawValue,
            SettingsKey.onboardingCompleted: false,
            SettingsKey.soundsEnabled: true,
            SettingsKey.menuBarStartNow: false,
            SettingsKey.menuBarStartAtLogin: false,
        ]
        defaults.register(defaults: seeds)

        // Migrate legacy empty-string "Use default" sentinel to the named constant.
        for key in [SettingsKey.permissionSound, SettingsKey.questionSound] {
            if defaults.string(forKey: key) == "" {
                defaults.set(SettingsKey.useDefaultSound, forKey: key)
            }
        }
    }

    // String helpers
    func string(_ key: String) -> String { defaults.string(forKey: key) ?? "" }
    func setString(_ key: String, _ value: String) { defaults.set(value, forKey: key) }

    // Int helpers
    func int(_ key: String) -> Int { defaults.integer(forKey: key) }
    func setInt(_ key: String, _ value: Int) { defaults.set(value, forKey: key) }

    // Bool helpers
    func bool(_ key: String) -> Bool { defaults.bool(forKey: key) }
    func setBool(_ key: String, _ value: Bool) { defaults.set(value, forKey: key) }

    var titleSource: TitleSource {
        TitleSource(rawValue: string(SettingsKey.titleSource)) ?? .tabName
    }

    var questionMultiSelectMode: MultiSelectMode {
        MultiSelectMode(rawValue: string(SettingsKey.questionMultiSelectMode)) ?? .notifyOnly
    }

    var terminalOverride: TerminalOverride {
        TerminalOverride(rawValue: string(SettingsKey.terminalOverride)) ?? .auto
    }

    func effectiveSound(for override: String, fallback: String? = nil) -> String {
        if !override.isEmpty { return override }
        if let fallback = fallback, !fallback.isEmpty { return fallback }
        return string(SettingsKey.defaultSound)
    }

    func resetAll() {
        for key in SettingsKey.all {
            defaults.removeObject(forKey: key)
        }
    }
}
