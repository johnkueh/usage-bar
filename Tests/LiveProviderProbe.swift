import Foundation

@main
enum LiveProviderProbe {
    static func main() {
        let providerName = CommandLine.arguments.dropFirst().first ?? ""
        guard let provider = Provider(rawValue: providerName), provider != .claude else {
            FileHandle.standardError.write(Data("usage: LiveProviderProbe codex|grok|kimi\n".utf8))
            exit(2)
        }
        let profile = AccountProfile(id: "probe:\(provider.rawValue)", provider: provider,
            name: "Current", homePath: AccountStore.defaultHome(provider).path, usesCurrentHome: true)
        let executable = CommandLine.arguments.dropFirst(2).first
        let (usage, error) = provider == .codex && executable != nil
            ? ProviderClient.fetchCodex(profile, executable: executable)
            : ProviderClient.fetch(profile)
        guard let usage else {
            FileHandle.standardError.write(Data("\(provider.title): \(error)\n".utf8))
            exit(1)
        }
        for window in usage.windows {
            print("\(provider.title) \(window.label): \(window.usedPercent)%")
        }
    }
}
