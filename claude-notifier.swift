import Cocoa
import UserNotifications

func parseArgs() -> [String: String] {
    let argv = CommandLine.arguments
    var result: [String: String] = [:]
    var i = 1
    while i < argv.count {
        let key = argv[i]
        guard key.hasPrefix("-") else {
            fputs("Warning: ignoring unexpected argument: \(key)\n", stderr)
            i += 1
            continue
        }
        guard i + 1 < argv.count else {
            fputs("Warning: flag \(key) has no value\n", stderr)
            break
        }
        result[String(key.dropFirst())] = argv[i + 1]
        i += 2
    }
    return result
}

func parseDouble(_ key: String, _ raw: String?, default defaultValue: Double) -> Double {
    guard let raw = raw else { return defaultValue }
    if let parsed = Double(raw) { return parsed }
    fputs("Warning: invalid \(key) value '\(raw)', defaulting to \(defaultValue)\n", stderr)
    return defaultValue
}

class NotificationAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var hasFinished = false
    private var notificationID: String?
    private var sigtermSource: DispatchSourceSignal?
    let title: String
    let message: String
    let subtitle: String
    let sound: String
    let actionLabels: [String]
    let timeout: Double
    let maxWaitForAction: Double

    init(title: String, message: String, subtitle: String, sound: String,
         actionLabels: [String], timeout: Double, maxWaitForAction: Double) {
        self.title = title
        self.message = message
        self.subtitle = subtitle
        self.sound = sound
        self.actionLabels = actionLabels
        self.timeout = timeout
        self.maxWaitForAction = maxWaitForAction
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Remove the banner when the shell sends SIGTERM (permission resolved in terminal).
        signal(SIGTERM, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        src.setEventHandler { [weak self] in self?.finish("@EXTERNALLY_RESOLVED") }
        src.resume()
        sigtermSource = src

        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            guard granted else {
                if let error = error {
                    fputs("Notification permission error: \(error)\n", stderr)
                } else {
                    fputs("Notification permission denied\n", stderr)
                }
                self.finish("@DENIED")
                return
            }
            self.postNotification(center)
        }

        if actionLabels.isEmpty {
            if timeout > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                    self.finish("@TIMEOUT")
                }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + maxWaitForAction) {
                self.finish("@TIMEOUT")
            }
        }
    }

    func postNotification(_ center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        if !subtitle.isEmpty { content.subtitle = subtitle }
        content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: sound))

        if !actionLabels.isEmpty {
            let categoryID = "CLAUDE_\(UUID().uuidString)"
            let actions = actionLabels.enumerated().map { i, label in
                UNNotificationAction(identifier: "ACTION_\(i)", title: label, options: [])
            }
            let category = UNNotificationCategory(
                identifier: categoryID,
                actions: actions,
                intentIdentifiers: [],
                options: .customDismissAction
            )
            center.setNotificationCategories([category])
            content.categoryIdentifier = categoryID
        }

        let id = UUID().uuidString
        self.notificationID = id
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request) { error in
            if let error = error {
                fputs("Failed to post: \(error)\n", stderr)
                self.finish("@ERROR")
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            finish("@CONTENTCLICKED")
        case UNNotificationDismissActionIdentifier:
            finish("@DISMISSED")
        default:
            if response.actionIdentifier.hasPrefix("ACTION_"),
               let idx = Int(response.actionIdentifier.dropFirst("ACTION_".count)),
               idx < actionLabels.count {
                finish(actionLabels[idx])
            } else {
                finish(response.actionIdentifier)
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func finish(_ result: String) {
        DispatchQueue.main.async {
            guard !self.hasFinished else { return }
            self.hasFinished = true
            if let id = self.notificationID {
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
            }
            print(result)
            NSApplication.shared.terminate(nil)
        }
    }
}

func parseActionLabels() -> [String] {
    let argv = CommandLine.arguments
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
        let csv = parseArgs()["actions"] ?? ""
        if !csv.isEmpty { labels = csv.split(separator: ",").map(String.init) }
    }
    return labels
}

func runNotificationApp() -> Never {
    let args = parseArgs()
    let title      = args["title"]    ?? "Claude Code"
    let message    = args["message"]  ?? ""
    let subtitle   = args["subtitle"] ?? ""
    let sound      = args["sound"]    ?? "Glass"
    let timeout    = parseDouble("timeout", args["timeout"], default: 0)
    let maxWaitForAction = parseDouble("max-wait", args["max-wait"], default: 1800)
    let actionLabels = parseActionLabels()

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = NotificationAppDelegate(
        title: title, message: message, subtitle: subtitle,
        sound: sound, actionLabels: actionLabels,
        timeout: timeout, maxWaitForAction: maxWaitForAction
    )
    app.delegate = delegate
    app.run()
    exit(0)
}

@main
struct NotifierEntry {
    static let usage = """
    Usage:
      claude-notifier -title "Title" -message "Body" \\
                      [-subtitle "Sub"] [-action A] [-action B] ... \\
                      [-sound Glass] [-timeout SECONDS] [-max-wait SECONDS]

      claude-notifier --settings         Open settings window
      claude-notifier --menu-bar         Run as menu bar app
      claude-notifier --test <type>      Fire a test notification (permission|task|question)

    Flags:
      -title TEXT          Notification title (default: "Claude Code")
      -message TEXT        Notification body
      -subtitle TEXT       Optional subtitle line
      -action LABEL        Action button label (repeat for multiple buttons)
      -actions A,B,C       Deprecated: use repeated -action flags instead
      -sound NAME          NSSound name (default: Glass)
      -timeout SECONDS     Exit after SECONDS if no user response (fire-and-forget only)
      -max-wait SECONDS    Hard cap for action-button mode (default: 1800)

    Output:
      On user action, prints the clicked label to stdout.
      Otherwise prints @TIMEOUT, @DISMISSED, @CONTENTCLICKED, @DENIED, or @ERROR.
    """

    static func main() {
        // No args = launched from Finder/Dock. Show onboarding on first launch,
        // splash confirmation on subsequent launches.
        guard let first = CommandLine.arguments.dropFirst().first else {
            if NotifierSettings.shared.bool(SettingsKey.onboardingCompleted) {
                runSplashApp()
            } else {
                runOnboardingApp()
            }
        }
        if ["-h", "--help", "-help"].contains(first) {
            print(usage)
            return
        }
        switch first {
        case "--settings":
            runSettingsApp()
        case "--menu-bar":
            runMenuBarApp()
        case "--onboarding":
            runOnboardingApp()
        case "--test":
            let kind = CommandLine.arguments.dropFirst(2).first ?? ""
            runTestNotification(kind: kind)
        default:
            break
        }
        runNotificationApp()
    }
}
