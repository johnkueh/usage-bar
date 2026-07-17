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

        print("Account store tests passed")
    }
}
