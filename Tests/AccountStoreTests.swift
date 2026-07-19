import Foundation

@main
enum AccountStoreTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func credential(_ token: String) -> String {
        "{\"claudeAiOauth\":{\"accessToken\":\"\(token)\"}}"
    }

    static func main() throws {
        let codexCandidates = AccountStore.executableCandidates("codex", home: "/Users/test",
            applicationRoots: ["/Applications", "/Users/test/Applications"])
        require(codexCandidates.contains("/Applications/ChatGPT.app/Contents/Resources/codex"),
                "Codex discovery should include the ChatGPT desktop bundle")
        require(codexCandidates.contains("/Applications/Codex.app/Contents/Resources/codex"),
                "Codex discovery should include the Codex desktop bundle")
        require(codexCandidates.contains("/Users/test/Applications/ChatGPT.app/Contents/Resources/codex"),
                "Codex discovery should include per-user desktop installs")

        require(AccountStore.preferredClaudeToken(isActive: true,
                    liveCredential: credential("live"), savedCredential: credential("saved")) == "live",
                "The active Claude account should prefer its live Keychain token")
        require(AccountStore.preferredClaudeToken(isActive: true,
                    liveCredential: nil, savedCredential: credential("saved")) == "saved",
                "The active Claude account should fall back to its saved snapshot")
        require(AccountStore.preferredClaudeToken(isActive: true,
                    liveCredential: "not-json", savedCredential: credential("saved")) == "saved",
                "A malformed live Claude credential should fall back to its saved snapshot")
        require(AccountStore.preferredClaudeToken(isActive: false,
                    liveCredential: credential("wrong"), savedCredential: credential("saved")) == "saved",
                "Inactive Claude accounts should use their saved snapshots")

        let currentKimi = AccountProfile(id: "kimi:current", provider: .kimi, name: "Current",
            homePath: "/Users/test/.kimi", usesCurrentHome: true)
        let currentHomes = AccountStore.kimiHomes(for: currentKimi,
            userHome: URL(fileURLWithPath: "/Users/test")).map(\.path)
        require(currentHomes == ["/Users/test/.kimi-code", "/Users/test/.kimi"],
                "Current Kimi accounts should search legacy and current data homes")
        let isolatedKimi = AccountProfile(id: "kimi:isolated", provider: .kimi, name: "Other",
            homePath: "/tmp/isolated-kimi", usesCurrentHome: false)
        require(AccountStore.kimiHomes(for: isolatedKimi,
                    userHome: URL(fileURLWithPath: "/Users/test")).map(\.path) == ["/tmp/isolated-kimi"],
                "Isolated Kimi accounts must not read the current login")

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let validKimi = AccountStore.KimiOAuthCredential(accessToken: "valid", refreshToken: "refresh",
            expiresAt: now.timeIntervalSince1970 + 3_600)
        let expiredKimi = AccountStore.KimiOAuthCredential(accessToken: "expired", refreshToken: "refresh",
            expiresAt: now.timeIntervalSince1970 - 1)
        require(AccountStore.usableKimiAccessToken(validKimi, now: now) == "valid",
                "Kimi should use an unexpired access token")
        require(AccountStore.usableKimiAccessToken(expiredKimi, now: now) == nil,
                "Kimi should refresh an expired access token")

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-bar-kimi-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: temp.appendingPathComponent("credentials"),
                                                withIntermediateDirectories: true)
        let credentialData = try JSONEncoder().encode(expiredKimi)
        try credentialData.write(to: temp.appendingPathComponent("credentials/kimi-code.json"))
        let refreshProfile = AccountProfile(id: "kimi:refresh", provider: .kimi, name: "Refresh",
            homePath: temp.path, usesCurrentHome: false)
        var refreshCalled = false
        let refreshed = AccountStore.kimiToken(for: refreshProfile, now: now) { file, credential, callNow in
            refreshCalled = true
            require(file.lastPathComponent == "kimi-code.json", "Kimi should refresh the stored credential")
            require(credential == expiredKimi, "Kimi should pass the expired credential to the refresher")
            require(callNow == now, "Kimi refresh should use the caller's clock")
            return ("refreshed", "")
        }
        require(refreshCalled && refreshed.0 == "refreshed" && refreshed.1.isEmpty,
                "Kimi should renew an expired OAuth token automatically")

        let refreshJSON: [String: Any] = [
            "access_token": "new-access", "refresh_token": "new-refresh", "expires_in": 3_600,
            "scope": "kimi-code", "token_type": "Bearer",
        ]
        let parsedRefresh = AccountStore.refreshedKimiCredential(from: refreshJSON, now: now)
        require(parsedRefresh?.accessToken == "new-access" && parsedRefresh?.refreshToken == "new-refresh",
                "Kimi refresh should preserve rotated OAuth tokens")
        require(parsedRefresh?.expiresAt == now.timeIntervalSince1970 + 3_600,
                "Kimi refresh should calculate the new expiry")

        print("Account store tests passed")
    }
}
