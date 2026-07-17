import Foundation
import Darwin

enum AccountStore {
    static let claudeDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    static var claudeCLI: String {
        if let bundled = Bundle.main.path(forResource: "claude-account", ofType: nil),
           FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/claude-account").path
    }
    static let appDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".usage-bar")
    static let registryURL = appDir.appendingPathComponent("accounts.json")

    static func claudeAccounts() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: claudeDir.path)) ?? []
        return names.filter { $0.hasPrefix(".cred-") }
            .map { String($0.dropFirst(".cred-".count)) }.sorted()
    }

    static func accounts() -> [AccountProfile] {
        claudeAccounts().map(AccountProfile.claude) + managedAccounts()
    }

    static func accounts(for provider: Provider) -> [AccountProfile] {
        accounts().filter { $0.provider == provider }
    }

    static func managedAccounts() -> [AccountProfile] {
        guard let data = try? Data(contentsOf: registryURL) else { return [] }
        return (try? JSONDecoder().decode([AccountProfile].self, from: data)) ?? []
    }

    static func saveManaged(_ profiles: [AccountProfile]) throws {
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(profiles)
        try data.write(to: registryURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: registryURL.path)
    }

    static func add(provider: Provider, name: String, currentHome: Bool) throws -> AccountProfile {
        precondition(provider != .claude)
        var profiles = managedAccounts()
        let currentPath = currentHome ? defaultHome(provider).path : nil
        if let existing = profiles.first(where: { $0.provider == provider && $0.homePath == currentPath }) {
            return existing
        }
        let id = "\(provider.rawValue):\(UUID().uuidString.lowercased())"
        let home: URL
        if currentHome {
            home = defaultHome(provider)
        } else {
            home = appDir.appendingPathComponent("providers/\(provider.rawValue)/\(id.split(separator: ":").last!)")
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        let profile = AccountProfile(id: id, provider: provider, name: name,
                                     homePath: home.path, usesCurrentHome: currentHome)
        profiles.append(profile)
        try saveManaged(profiles)
        return profile
    }

    static func remove(_ profile: AccountProfile) throws {
        if profile.provider == .claude {
            try FileManager.default.removeItem(at: claudeDir.appendingPathComponent(".cred-\(profile.name)"))
        } else {
            try saveManaged(managedAccounts().filter { $0.id != profile.id })
        }
    }

    static func defaultHome(_ provider: Provider) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch provider {
        case .claude: return home.appendingPathComponent(".claude")
        case .codex: return home.appendingPathComponent(".codex")
        case .grok: return home.appendingPathComponent(".grok")
        case .kimi: return home.appendingPathComponent(".kimi-code")
        }
    }

    static func isSignedIn(_ profile: AccountProfile) -> Bool {
        guard let homePath = profile.homePath else { return false }
        if profile.provider == .kimi {
            let home = URL(fileURLWithPath: homePath)
            let oauth = home.appendingPathComponent("credentials/kimi-code.json")
            let config = home.appendingPathComponent("config.toml")
            if FileManager.default.fileExists(atPath: oauth.path) { return true }
            guard let text = try? String(contentsOf: config, encoding: .utf8) else { return false }
            return kimiAPIKey(in: text) != nil
        }
        let auth = URL(fileURLWithPath: homePath).appendingPathComponent("auth.json")
        return FileManager.default.fileExists(atPath: auth.path)
    }

    static func activeClaudeAccount() -> String? {
        let marker = claudeDir.appendingPathComponent(".account-active")
        return (try? String(contentsOf: marker, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    static func run(_ path: String, _ args: [String], environment: [String: String]? = nil,
                    input: Data? = nil) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        if let environment { process.environment = environment }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        if input != nil { process.standardInput = Pipe() }
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        if let input, let pipe = process.standardInput as? Pipe {
            try? pipe.fileHandleForWriting.write(contentsOf: input)
            try? pipe.fileHandleForWriting.close()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    static func executableCandidates(_ name: String, home: String,
                                     applicationRoots: [String]) -> [String] {
        switch name {
        case "codex":
            let commandLine = ["\(home)/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
            let desktop = applicationRoots.flatMap { root in
                [
                    "\(root)/ChatGPT.app/Contents/Resources/codex",
                    "\(root)/Codex.app/Contents/Resources/codex",
                    "\(root)/Codex.app/Contents/MacOS/Codex",
                    "\(root)/Codex.app/Contents/MacOS/codex",
                ]
            }
            return commandLine + desktop
        case "grok":
            return ["\(home)/.grok/bin/grok", "\(home)/.local/bin/grok", "/opt/homebrew/bin/grok"]
        case "kimi":
            return ["\(home)/.kimi-code/bin/kimi", "\(home)/.local/bin/kimi",
                    "/opt/homebrew/bin/kimi", "/usr/local/bin/kimi"]
        default:
            return []
        }
    }

    static func executable(_ name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = executableCandidates(name, home: home,
            applicationRoots: ["\(home)/Applications", "/Applications"])
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func liveClaudeCredential() -> String? {
        let (status, output) = run("/usr/bin/security",
            ["find-generic-password", "-w", "-s", "Claude Code-credentials", "-a", NSUserName()])
        let blob = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return status == 0 && !blob.isEmpty ? blob : nil
    }

    static func claudeAccessToken(in blob: String?) -> String? {
        guard let blob, let data = blob.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        return token
    }

    static func preferredClaudeToken(isActive: Bool, liveCredential: String?,
                                     savedCredential: String?) -> String? {
        if isActive, let token = claudeAccessToken(in: liveCredential) { return token }
        return claudeAccessToken(in: savedCredential)
    }

    static func claudeToken(for name: String) -> String? {
        let saved = try? String(contentsOf: claudeDir.appendingPathComponent(".cred-\(name)"),
                                encoding: .utf8)
        let isActive = name == activeClaudeAccount()
        return preferredClaudeToken(isActive: isActive,
            liveCredential: isActive ? liveClaudeCredential() : nil,
            savedCredential: saved)
    }

    static func kimiAPIKey(in config: String) -> String? {
        let lines = config.components(separatedBy: .newlines)
        var inKimiSection = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[providers.kimi]" {
                inKimiSection = true
            } else if trimmed.hasPrefix("[") {
                inKimiSection = false
            } else if inKimiSection, trimmed.hasPrefix("api_key") {
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                return parts[1].trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return nil
    }

    static func kimiToken(for profile: AccountProfile) -> String? {
        guard let homePath = profile.homePath else { return nil }
        let home = URL(fileURLWithPath: homePath)

        // Prefer OAuth access token when available and not expired.
        let oauthFile = home.appendingPathComponent("credentials/kimi-code.json")
        if let data = try? Data(contentsOf: oauthFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let accessToken = json["access_token"] as? String,
           let expiresAt = json["expires_at"] as? NSNumber,
           expiresAt.doubleValue > Date().timeIntervalSince1970 + 60 {
            return accessToken
        }

        // Fall back to the API key configured for the kimi provider.
        let configFile = home.appendingPathComponent("config.toml")
        if let config = try? String(contentsOf: configFile, encoding: .utf8) {
            if let key = kimiAPIKey(in: config), !key.isEmpty {
                return key
            }
        }

        return nil
    }

    static func switchClaude(to name: String) -> (Bool, String) {
        let (status, output) = run(claudeCLI, [name])
        return (status == 0, output)
    }

    static func snapshotClaude(_ name: String) -> (Bool, String) {
        let (status, output) = run(claudeCLI, ["snapshot", name])
        return (status == 0, output)
    }

    static func notify(title: String, message: String) {
        func escape(_ value: String) -> String {
            value.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }
        _ = run("/usr/bin/osascript", ["-e",
            "display notification \"\(escape(message))\" with title \"\(escape(title))\""])
    }
}

enum ProviderClient {
    static func fetch(_ profile: AccountProfile) -> (ProviderUsage?, String) {
        switch profile.provider {
        case .claude:
            guard let token = AccountStore.claudeToken(for: profile.name) else {
                return (nil, "Sign in to Claude Code again")
            }
            return UsageAPI.fetchClaude(token: token)
        case .codex:
            return fetchCodex(profile)
        case .grok:
            return fetchGrok(profile)
        case .kimi:
            return fetchKimi(profile)
        }
    }

    private static func providerEnvironment(_ profile: AccountProfile) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        environment["PATH"] = "\(home)/.local/bin:\(home)/.grok/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        if let variable = profile.provider.homeVariable, let path = profile.homePath {
            environment[variable] = path
        }
        environment["TERM"] = "xterm-256color"
        return environment
    }

    static func fetchCodex(_ profile: AccountProfile, executable override: String? = nil) -> (ProviderUsage?, String) {
        guard AccountStore.isSignedIn(profile) else { return (nil, "Sign in to refresh") }
        guard let codex = override ?? AccountStore.executable("codex") else {
            return (nil, "Open the Codex app or install its CLI")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codex)
        process.arguments = ["app-server", "--stdio"]
        process.environment = providerEnvironment(profile)
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let lock = NSLock()
        var buffer = ""
        var usage: ProviderUsage?
        var failure = "Codex did not return usage"
        let finished = DispatchSemaphore(value: 0)

        func send(_ object: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: object),
                  var line = String(data: data, encoding: .utf8) else { return }
            line += "\n"
            try? input.fileHandleForWriting.write(contentsOf: Data(line.utf8))
        }

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            lock.lock(); buffer += chunk
            let lines = buffer.components(separatedBy: "\n")
            buffer = lines.last ?? ""
            lock.unlock()
            for line in lines.dropLast() {
                guard let data = line.data(using: .utf8),
                      let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = (message["id"] as? NSNumber)?.intValue else { continue }
                if id == 1 {
                    send(["jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read"])
                } else if id == 2 {
                    usage = UsageAPI.parseCodexRateLimits(message)
                    if let error = message["error"] as? [String: Any], let text = error["message"] as? String {
                        failure = text
                    }
                    finished.signal()
                }
            }
        }

        do { try process.run() } catch { return (nil, error.localizedDescription) }
        send(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "usage-bar", "title": "Usage Bar", "version": "1"],
            "capabilities": NSNull(),
        ]])
        let result = finished.wait(timeout: .now() + 15)
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        return result == .success && usage != nil ? (usage, "") : (nil, failure)
    }

    private static func fetchGrok(_ profile: AccountProfile) -> (ProviderUsage?, String) {
        guard AccountStore.isSignedIn(profile) else { return (nil, "Sign in to refresh") }
        guard let grok = AccountStore.executable("grok") else { return (nil, "Grok CLI not found") }
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        var windowSize = winsize(ws_row: 24, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&masterFD, &slaveFD, nil, nil, &windowSize) == 0 else {
            return (nil, "Couldn’t open a terminal for Grok")
        }
        let master = FileHandle(fileDescriptor: masterFD, closeOnDealloc: true)
        let slave = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: grok)
        process.arguments = ["--no-alt-screen"]
        process.environment = providerEnvironment(profile)
        process.standardInput = slave
        process.standardOutput = slave
        process.standardError = slave
        let lock = NSLock()
        var raw = ""
        var parsed: ProviderUsage?
        var answeredCursorQuery = false
        let finished = DispatchSemaphore(value: 0)
        master.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            lock.lock(); raw += chunk
            let shouldAnswerCursor = !answeredCursorQuery && raw.contains("\u{001B}[6n")
            if shouldAnswerCursor { answeredCursorQuery = true }
            if parsed == nil { parsed = UsageAPI.parseGrokTerminal(raw) }
            let didParse = parsed != nil
            lock.unlock()
            if shouldAnswerCursor {
                try? master.write(contentsOf: Data("\u{001B}[24;1R".utf8))
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
                    try? master.write(contentsOf: Data("/usage show\r".utf8))
                }
            }
            if didParse { finished.signal() }
        }
        do { try process.run() } catch { return (nil, error.localizedDescription) }
        try? slave.close()
        let result = finished.wait(timeout: .now() + 18)
        master.readabilityHandler = nil
        if process.isRunning { process.interrupt() }
        return result == .success && parsed != nil ? (parsed, "") : (nil, "Grok usage is unavailable")
    }

    private static func fetchKimi(_ profile: AccountProfile) -> (ProviderUsage?, String) {
        guard AccountStore.isSignedIn(profile) else { return (nil, "Sign in to refresh") }
        guard let token = AccountStore.kimiToken(for: profile) else {
            return (nil, "No Kimi token found")
        }
        return UsageAPI.fetchKimi(token: token)
    }
}
