import Foundation

enum Provider: String, Codable, CaseIterable {
    case claude
    case codex
    case grok

    var title: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .grok: return "Grok Build"
        }
    }

    var statusMark: String {
        switch self {
        case .claude: return "C"
        case .codex: return "O"
        case .grok: return "X"
        }
    }

    var homeVariable: String? {
        switch self {
        case .claude: return nil
        case .codex: return "CODEX_HOME"
        case .grok: return "GROK_HOME"
        }
    }
}

struct AccountProfile: Codable, Hashable {
    let id: String
    let provider: Provider
    var name: String
    let homePath: String?
    let usesCurrentHome: Bool

    static func claude(_ name: String) -> AccountProfile {
        AccountProfile(id: "claude:\(name)", provider: .claude, name: name,
                       homePath: nil, usesCurrentHome: true)
    }
}

struct UsageWindow: Codable, Equatable {
    let label: String
    let shortLabel: String
    let usedPercent: Double
    let resetsAt: Date?
    let durationMinutes: Int?
}

struct ProviderUsage: Codable, Equatable {
    let windows: [UsageWindow]
    let fetchedAt: Date
}

enum UsageState {
    case fresh(ProviderUsage)
    case stale(ProviderUsage, String)
    case unavailable(String)

    var usage: ProviderUsage? {
        switch self {
        case .fresh(let usage), .stale(let usage, _): return usage
        case .unavailable: return nil
        }
    }

    var isStale: Bool {
        if case .stale = self { return true }
        return false
    }
}
