import AppKit

@main
enum RenderTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        require(Render.countdown(now.addingTimeInterval(-1), now: now) == "due",
                "Past status-bar resets should be marked due")
        require(Render.resetText(now.addingTimeInterval(-1), now: now) == "refresh due",
                "Past menu resets should ask for a refresh")

        let profile = AccountProfile(id: "kimi:test", provider: .kimi, name: "Kimi",
            homePath: "/tmp/kimi", usesCurrentHome: false)
        let usage = ProviderUsage(windows: [UsageWindow(label: "5 hours", shortLabel: "5h",
            usedPercent: 100, resetsAt: now.addingTimeInterval(-1), durationMinutes: 300)], fetchedAt: now)
        let rendered = Render.accountTitle(profile: profile,
            state: .stale(usage, "Sign in to Kimi Code again")).string
        require(rendered.contains("Cached data — Sign in to Kimi Code again"),
                "Stale usage should be clearly labelled as cached")

        print("Render tests passed")
    }
}
