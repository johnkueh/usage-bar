import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    let menu = NSMenu()
    var usage: [String: UsageState] = [:]
    var lastRefresh: Date?
    var refreshing = false
    var heartbeating = false
    var menuOpen = false
    var unknownClaudeEmail: String?
    let defaults = UserDefaults.standard

    var pinnedID: String? {
        get { defaults.string(forKey: "pinned-account-id") }
        set { defaults.set(newValue, forKey: "pinned-account-id") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        migratePreferences()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        menu.delegate = self
        if let button = statusItem.button {
            button.title = "·"
            button.imagePosition = .imageOnly
        }
        chooseDefaultPinIfNeeded()
        rebuildMenu()
        refresh()

        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self?.refresh() }
        }

        if ProcessInfo.processInfo.environment["DEBUG_SHOOT"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.debugShoot() }
        }
        if let target = ProcessInfo.processInfo.environment["DEBUG_SWITCH"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.performClaudeSwitch(to: target)
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { NSApp.terminate(nil) }
            }
        }
    }

    func migratePreferences() {
        ["autopilot", "autopilot-last-switch", "autopilot-last-reason"].forEach {
            defaults.removeObject(forKey: $0)
        }
    }

    func chooseDefaultPinIfNeeded() {
        let profiles = AccountStore.accounts()
        if let pinnedID, profiles.contains(where: { $0.id == pinnedID }) { return }
        if let active = AccountStore.activeClaudeAccount() {
            pinnedID = AccountProfile.claude(active).id
        } else {
            pinnedID = profiles.first?.id
        }
    }

    // MARK: - Refresh

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let profiles = AccountStore.accounts()
        let activeClaude = AccountStore.activeClaudeAccount()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            var result: [String: UsageState] = [:]
            var liveEmail: String?
            var expiredClaude: [String] = []

            for profile in profiles {
                let (snapshot, error) = ProviderClient.fetch(profile)
                if let snapshot {
                    result[profile.id] = .fresh(snapshot)
                    UsageCache.save(profile.id, snapshot)
                    if profile.provider == .claude, profile.name == activeClaude,
                       let token = AccountStore.claudeToken(for: profile.name) {
                        liveEmail = UsageAPI.fetchClaudeEmail(token: token)
                    }
                } else {
                    result[profile.id] = self.fallback(profile.id, error)
                    if profile.provider == .claude, error == "Token expired", profile.name != activeClaude {
                        expiredClaude.append(profile.name)
                    }
                }
            }

            DispatchQueue.main.async {
                self.usage = result
                self.lastRefresh = Date()
                self.refreshing = false
                self.reconcileClaudeEmail(liveEmail, active: activeClaude)
                self.chooseDefaultPinIfNeeded()
                self.updateStatusButton()
                self.rebuildMenu()
                self.heartbeatClaudeIfNeeded(expiredClaude)
            }
        }
    }

    func fallback(_ id: String, _ reason: String) -> UsageState {
        if let cached = UsageCache.load(id) { return .stale(cached, reason) }
        return .unavailable(reason)
    }

    func heartbeatClaudeIfNeeded(_ names: [String]) {
        guard !heartbeating else { return }
        let due = names.filter { name in
            guard let last = defaults.object(forKey: "heartbeat-\(name)") as? Date else { return true }
            return Date().timeIntervalSince(last) >= 1_200
        }
        guard !due.isEmpty else { return }
        heartbeating = true
        due.forEach { defaults.set(Date(), forKey: "heartbeat-\($0)") }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            for name in due { _ = AccountStore.run(AccountStore.claudeCLI, ["refresh", name]) }
            DispatchQueue.main.async {
                self?.heartbeating = false
                self?.refresh()
            }
        }
    }

    func reconcileClaudeEmail(_ liveEmail: String?, active: String?) {
        guard let liveEmail, let active else { return }
        let known = AccountStore.claudeAccounts().compactMap { defaults.string(forKey: "email-\($0)") }
        let activeEmail = defaults.string(forKey: "email-\(active)")
        if activeEmail == nil || activeEmail == liveEmail {
            defaults.set(liveEmail, forKey: "email-\(active)")
            unknownClaudeEmail = nil
        } else if known.contains(liveEmail) {
            unknownClaudeEmail = nil
        } else {
            unknownClaudeEmail = liveEmail
        }
    }

    // MARK: - Status bar

    func updateStatusButton() {
        guard let button = statusItem.button else { return }
        let profiles = AccountStore.accounts()
        let pinned = profiles.first { $0.id == pinnedID } ?? profiles.first
        button.title = ""
        button.imagePosition = .imageOnly
        if let pinned {
            let state = usage[pinned.id]
            button.image = Render.statusText(provider: pinned.provider, usage: state?.usage,
                                             stale: state?.isStale ?? false)
            if let snapshot = state?.usage {
                let values = snapshot.windows.map { String(format: "%@ %.0f%%", $0.label, $0.usedPercent) }
                    .joined(separator: ", ")
                button.toolTip = "\(pinned.provider.title) — \(pinned.name) — \(values)"
            } else {
                button.toolTip = "\(pinned.provider.title) — \(pinned.name) — no usage yet"
            }
        } else {
            button.image = Render.statusText(provider: .claude, usage: nil, stale: false)
            button.toolTip = "Usage Bar — add an account"
        }
    }

    // MARK: - Menu

    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < 30 { return }
        refresh()
    }

    func menuDidClose(_ menu: NSMenu) { menuOpen = false }

    func rebuildMenu() {
        if menuOpen { updateOpenMenu(); return }
        menu.removeAllItems()
        let profiles = AccountStore.accounts()
        let activeClaude = AccountStore.activeClaudeAccount()

        if let email = unknownClaudeEmail {
            let detected = NSMenuItem(title: "Save new Claude login — \(email)…",
                                      action: #selector(addClaudeAccount), keyEquivalent: "")
            detected.target = self
            menu.addItem(detected)
            menu.addItem(.separator())
        }

        for (providerIndex, provider) in Provider.allCases.enumerated() {
            if providerIndex > 0 { menu.addItem(.separator()) }
            let heading = NSMenuItem(title: provider.title.uppercased(), action: nil, keyEquivalent: "")
            heading.isEnabled = false
            menu.addItem(heading)
            let providerProfiles = profiles.filter { $0.provider == provider }
            if providerProfiles.isEmpty {
                let empty = NSMenuItem(title: "No accounts added", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                empty.indentationLevel = 1
                menu.addItem(empty)
            }
            for profile in providerProfiles {
                menu.addItem(accountItem(profile, activeClaude: activeClaude))
            }
        }

        menu.addItem(.separator())
        menu.addItem(addAccountItem())
        let refreshItem = NSMenuItem(title: refreshing ? "Refreshing…" : "Refresh all",
                                     action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.isEnabled = !refreshing
        if let lastRefresh { refreshItem.toolTip = "Updated \(Render.shortTime(lastRefresh))" }
        menu.addItem(refreshItem)

        let launch = NSMenuItem(title: "Launch at login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launch)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Usage Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    func accountItem(_ profile: AccountProfile, activeClaude: String?) -> NSMenuItem {
        let item = NSMenuItem(title: profile.name, action: nil, keyEquivalent: "")
        item.representedObject = profile.id
        item.attributedTitle = Render.accountTitle(profile: profile, state: usage[profile.id],
            activeClaude: activeClaude, pinned: profile.id == pinnedID)
        let submenu = NSMenu()

        let pin = NSMenuItem(title: "Show in menu bar", action: #selector(pinAccount(_:)), keyEquivalent: "")
        pin.target = self
        pin.representedObject = profile.id
        pin.state = profile.id == pinnedID ? .on : .off
        submenu.addItem(pin)

        if profile.provider == .claude, profile.name != activeClaude {
            let switchItem = NSMenuItem(title: "Switch to this account", action: #selector(switchClaude(_:)), keyEquivalent: "")
            switchItem.target = self
            switchItem.representedObject = profile.name
            submenu.addItem(switchItem)
        }

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshNow), keyEquivalent: "")
        refreshItem.target = self
        submenu.addItem(refreshItem)

        if !(profile.provider == .claude && profile.name == activeClaude) {
            submenu.addItem(.separator())
            let remove = NSMenuItem(title: "Remove account…", action: #selector(removeAccount(_:)), keyEquivalent: "")
            remove.target = self
            remove.representedObject = profile.id
            submenu.addItem(remove)
        }
        item.submenu = submenu
        return item
    }

    func addAccountItem() -> NSMenuItem {
        let root = NSMenuItem(title: "Add account…", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let claude = NSMenuItem(title: "Add Claude Code account…", action: #selector(addClaudeAccount), keyEquivalent: "")
        claude.target = self
        submenu.addItem(claude)
        submenu.addItem(.separator())
        addProviderActions(.codex, to: submenu)
        submenu.addItem(.separator())
        addProviderActions(.grok, to: submenu)
        root.submenu = submenu
        return root
    }

    func addProviderActions(_ provider: Provider, to menu: NSMenu) {
        let current = NSMenuItem(title: "Add current \(provider.title) login…",
                                 action: #selector(addCurrentProvider(_:)), keyEquivalent: "")
        current.target = self
        current.representedObject = provider.rawValue
        menu.addItem(current)
        let another = NSMenuItem(title: "Sign in to another \(provider.title) account…",
                                 action: #selector(addAnotherProvider(_:)), keyEquivalent: "")
        another.target = self
        another.representedObject = provider.rawValue
        menu.addItem(another)
    }

    func updateOpenMenu() {
        let profiles = Dictionary(uniqueKeysWithValues: AccountStore.accounts().map { ($0.id, $0) })
        let activeClaude = AccountStore.activeClaudeAccount()
        for item in menu.items {
            guard let id = item.representedObject as? String, let profile = profiles[id] else { continue }
            item.attributedTitle = Render.accountTitle(profile: profile, state: usage[id],
                activeClaude: activeClaude, pinned: id == pinnedID)
        }
    }

    // MARK: - Actions

    @objc func refreshNow() { refresh() }

    @objc func pinAccount(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        pinnedID = id
        updateStatusButton()
        rebuildMenu()
    }

    @objc func switchClaude(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        performClaudeSwitch(to: name)
    }

    func performClaudeSwitch(to name: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (ok, output) = AccountStore.switchClaude(to: name)
            DispatchQueue.main.async {
                if ok {
                    AccountStore.notify(title: "Claude account switched",
                                        message: "New sessions and agents now use \(name).")
                } else {
                    self?.errorAlert("Claude account switch failed", output.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                self?.refresh()
            }
        }
    }

    @objc func addClaudeAccount() {
        guard let name = askForName(title: "Add Claude Code account",
            detail: unknownClaudeEmail.map { "Current login: \($0)" }
                ?? "Sign in with Claude Code first, then save the current login here.") else { return }
        guard !AccountStore.claudeAccounts().contains(name) else {
            errorAlert("Account already added", "A Claude Code account named \(name) already exists.")
            return
        }
        let (ok, output) = AccountStore.snapshotClaude(name)
        if ok {
            if let email = unknownClaudeEmail { defaults.set(email, forKey: "email-\(name)") }
            unknownClaudeEmail = nil
            if pinnedID == nil { pinnedID = AccountProfile.claude(name).id }
            refresh()
        } else {
            errorAlert("Claude account wasn’t added", output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    @objc func addCurrentProvider(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let provider = Provider(rawValue: raw) else { return }
        let auth = AccountStore.defaultHome(provider).appendingPathComponent("auth.json")
        guard FileManager.default.fileExists(atPath: auth.path) else {
            errorAlert("No \(provider.title) login found", "Sign in with the \(provider.title) CLI, then try again.")
            return
        }
        guard let name = askForName(title: "Add current \(provider.title) login",
                                    detail: "Name this account so you can recognize it in Usage Bar.") else { return }
        do {
            let profile = try AccountStore.add(provider: provider, name: name, currentHome: true)
            if pinnedID == nil { pinnedID = profile.id }
            refresh()
        } catch { errorAlert("Account wasn’t added", error.localizedDescription) }
    }

    @objc func addAnotherProvider(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let provider = Provider(rawValue: raw) else { return }
        guard let name = askForName(title: "Add another \(provider.title) account",
                                    detail: "Usage Bar will open an isolated CLI sign-in in Terminal.") else { return }
        do {
            let profile = try AccountStore.add(provider: provider, name: name, currentHome: false)
            launchSignIn(profile)
            refresh()
        } catch { errorAlert("Account wasn’t added", error.localizedDescription) }
    }

    func launchSignIn(_ profile: AccountProfile) {
        guard let variable = profile.provider.homeVariable, let home = profile.homePath,
              let executable = AccountStore.executable(profile.provider == .codex ? "codex" : "grok") else {
            errorAlert("CLI not found", "Install the \(profile.provider.title) CLI, then try again.")
            return
        }
        func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command: String
        if profile.provider == .codex {
            command = "env \(variable)=\(shellQuote(home)) \(shellQuote(executable)) login"
        } else {
            command = "env \(variable)=\(shellQuote(home)) \(shellQuote(executable))"
        }
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        _ = AccountStore.run("/usr/bin/osascript", ["-e",
            "tell application \"Terminal\" to do script \"\(escaped)\""])
    }

    @objc func removeAccount(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let profile = AccountStore.accounts().first(where: { $0.id == id }) else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Remove \(profile.name)?"
        alert.informativeText = profile.provider == .claude
            ? "This removes the saved Claude credential snapshot. The login itself stays signed in."
            : "This removes the account from Usage Bar. Its CLI login files stay on this Mac."
        alert.addButton(withTitle: "Remove account")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try AccountStore.remove(profile)
            defaults.removeObject(forKey: "email-\(profile.name)")
            if pinnedID == id { pinnedID = nil; chooseDefaultPinIfNeeded() }
            usage.removeValue(forKey: id)
            updateStatusButton()
            rebuildMenu()
        } catch { errorAlert("Account wasn’t removed", error.localizedDescription) }
    }

    @objc func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { errorAlert("Launch at login couldn’t be changed", error.localizedDescription) }
        rebuildMenu()
    }

    func askForName(title: String, detail: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Account name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Add account")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40 else {
            errorAlert("Enter an account name", "Use 1–40 characters.")
            return nil
        }
        return name
    }

    func errorAlert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    // MARK: - Visual proof hook

    func debugShoot() {
        let demoProfiles = [
            AccountProfile.claude("Personal"),
            AccountProfile(id: "demo:codex", provider: .codex, name: "Personal", homePath: nil, usesCurrentHome: true),
            AccountProfile(id: "demo:grok", provider: .grok, name: "Work", homePath: nil, usesCurrentHome: true),
        ]
        let now = Date()
        let demoUsage: [String: UsageState] = [
            demoProfiles[0].id: .fresh(ProviderUsage(windows: [
                UsageWindow(label: "5 hours", shortLabel: "5h", usedPercent: 12, resetsAt: now.addingTimeInterval(8_400), durationMinutes: 300),
                UsageWindow(label: "Weekly", shortLabel: "W", usedPercent: 41, resetsAt: now.addingTimeInterval(345_600), durationMinutes: 10_080),
            ], fetchedAt: now)),
            demoProfiles[1].id: .fresh(ProviderUsage(windows: [
                UsageWindow(label: "Weekly", shortLabel: "W", usedPercent: 68, resetsAt: now.addingTimeInterval(259_200), durationMinutes: 10_080),
            ], fetchedAt: now)),
            demoProfiles[2].id: .stale(ProviderUsage(windows: [
                UsageWindow(label: "Weekly", shortLabel: "W", usedPercent: 92, resetsAt: now.addingTimeInterval(172_800), durationMinutes: 10_080),
            ], fetchedAt: now.addingTimeInterval(-900)), "Offline"),
        ]

        func bitmap(size: NSSize, appearance: NSAppearance.Name, background: NSColor,
                    draw: @escaping (NSRect) -> Void, path: String) {
            let scale: CGFloat = 2
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0) else { return }
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
                let rect = NSRect(origin: .zero, size: size)
                background.setFill(); rect.fill(); draw(rect)
            }
            NSGraphicsContext.restoreGraphicsState()
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }

        for (suffix, appearance, background) in [
            ("dark", NSAppearance.Name.darkAqua, NSColor(calibratedWhite: 0.10, alpha: 1)),
            ("light", NSAppearance.Name.aqua, NSColor(calibratedWhite: 0.94, alpha: 1)),
        ] {
            let status = Render.statusText(provider: .claude, usage: demoUsage[demoProfiles[0].id]?.usage, stale: false)
            bitmap(size: NSSize(width: status.size.width + 16, height: 28), appearance: appearance,
                   background: background, draw: { rect in
                status.draw(at: NSPoint(x: 8, y: (rect.height - status.size.height) / 2),
                            from: .zero, operation: .sourceOver, fraction: 1)
            }, path: "/tmp/usage-bar-status-\(suffix).png")

            let rows = demoProfiles.map { Render.accountTitle(profile: $0, state: demoUsage[$0.id],
                activeClaude: "Personal", pinned: $0.provider == .claude) }
            let sectionFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
            let width: CGFloat = 420
            let heights = rows.map { ceil($0.size().height) + 18 }
            let totalHeight = heights.reduce(0, +) + 3 * 28 + 72
            bitmap(size: NSSize(width: width, height: totalHeight), appearance: appearance,
                   background: background, draw: { rect in
                var y = rect.height - 26
                for index in 0..<rows.count {
                    let heading = NSAttributedString(string: demoProfiles[index].provider.title.uppercased(), attributes: [
                        .font: sectionFont, .foregroundColor: NSColor.secondaryLabelColor])
                    heading.draw(at: NSPoint(x: 16, y: y)); y -= 24
                    rows[index].draw(at: NSPoint(x: 24, y: y - rows[index].size().height + 10))
                    y -= heights[index]
                }
                NSColor.separatorColor.setFill()
                NSRect(x: 0, y: 57, width: width, height: 1).fill()
                let footer = NSAttributedString(string: "Add account…     Refresh all     Launch at login ✓",
                    attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
                footer.draw(at: NSPoint(x: 16, y: 28))
            }, path: "/tmp/usage-bar-menu-\(suffix).png")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
