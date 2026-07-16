import Foundation

@main
enum UsageParserTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() {
        let codexWeekly: [String: Any] = ["result": ["rateLimits": ["primary": [
            "usedPercent": 28.0, "windowDurationMins": 10_080, "resetsAt": 1_800_000_000,
        ]]]]
        let weekly = UsageAPI.parseCodexRateLimits(codexWeekly)
        require(weekly?.windows.count == 1, "Codex weekly-only response should stay one window")
        require(weekly?.windows.first?.shortLabel == "W", "Codex weekly label")

        let codexRestored: [String: Any] = ["result": ["rateLimits": [
            "primary": ["usedPercent": 11.0, "windowDurationMins": 300, "resetsAt": 1_800_000_000],
            "secondary": ["usedPercent": 42.0, "windowDurationMins": 10_080, "resetsAt": 1_800_100_000],
        ]]]
        let restored = UsageAPI.parseCodexRateLimits(codexRestored)
        require(restored?.windows.map(\.shortLabel) == ["5h", "W"],
                "Codex should automatically show a restored 5-hour window")

        let grok = "\u{001B}[2JWeekly limit: 25%\r\nNext reset: July 18, 21:51\r\n"
        let parsedGrok = UsageAPI.parseGrokTerminal(grok)
        require(parsedGrok?.windows.count == 1, "Grok should expose one weekly window")
        require(parsedGrok?.windows.first?.usedPercent == 25, "Grok weekly percentage")
        require(parsedGrok?.windows.first?.shortLabel == "W", "Grok weekly label")

        let claude = AccountProfile.claude("personal")
        let codex = AccountProfile(id: "codex:test", provider: .codex, name: "personal",
                                   homePath: nil, usesCurrentHome: true)
        let grokProfile = AccountProfile(id: "grok:test", provider: .grok, name: "personal",
                                         homePath: nil, usesCurrentHome: true)
        require(claude.supportsSwitching, "Claude accounts should remain switchable")
        require(!codex.supportsSwitching && !grokProfile.supportsSwitching,
                "Codex and Grok accounts should remain usage-only")

        let cachedUsage = ProviderUsage(windows: [UsageWindow(
            label: "Weekly", shortLabel: "W", usedPercent: 18,
            resetsAt: nil, durationMinutes: 10_080
        )], fetchedAt: Date())
        let initialStates = UsageCache.initialStates([codex, grokProfile]) { id in
            id == codex.id ? cachedUsage : nil
        }
        require(initialStates[codex.id]?.usage == cachedUsage,
                "Cached provider usage should be visible as soon as the app launches")
        require(initialStates[grokProfile.id] == nil,
                "Accounts without cached usage should continue to show a loading state")

        print("Usage parser tests passed")
    }
}
