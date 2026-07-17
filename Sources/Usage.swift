import Foundation

enum UsageAPI {
    static func parseDate(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        guard let string = value as? String else { return nil }
        if let seconds = Double(string) { return Date(timeIntervalSince1970: seconds) }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    private static func get(_ urlString: String, token: String, headers: [String: String] = [:]) -> (Data?, Int, String?) {
        guard let url = URL(string: urlString) else { return (nil, 0, "bad URL") }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.timeoutInterval = 10
        var result: (Data?, Int, String?) = (nil, 0, "timed out")
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            result = (data, (response as? HTTPURLResponse)?.statusCode ?? 0,
                      error?.localizedDescription)
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 15)
        return result
    }

    static func fetchClaude(token: String) -> (ProviderUsage?, String) {
        let headers = ["anthropic-beta": "oauth-2025-04-20"]
        let (data, status, error) = get("https://api.anthropic.com/api/oauth/usage", token: token, headers: headers)
        if status == 401 { return (nil, "Token expired") }
        if let error, data == nil { return (nil, error) }
        guard status == 200, let data,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["seven_day"] != nil else {
            return (nil, status == 0 ? "Offline" : "HTTP \(status)")
        }

        func window(_ key: String, label: String, short: String, minutes: Int) -> UsageWindow? {
            guard let value = json[key] as? [String: Any] else { return nil }
            let percent = (value["utilization"] as? NSNumber)?.doubleValue ?? 0
            return UsageWindow(label: label, shortLabel: short, usedPercent: percent,
                               resetsAt: parseDate(value["resets_at"]), durationMinutes: minutes)
        }
        let windows = [
            window("five_hour", label: "5 hours", short: "5h", minutes: 300),
            window("seven_day", label: "Weekly", short: "W", minutes: 10_080),
        ].compactMap { $0 }
        return (ProviderUsage(windows: windows, fetchedAt: Date()), "")
    }

    static func fetchClaudeEmail(token: String) -> String? {
        let headers = ["anthropic-beta": "oauth-2025-04-20"]
        let (data, status, _) = get("https://api.anthropic.com/api/oauth/profile", token: token, headers: headers)
        guard status == 200, let data,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        if let account = json["account"] as? [String: Any], let email = account["email"] as? String {
            return email
        }
        return json["email"] as? String
    }

    static func fetchKimi(token: String) -> (ProviderUsage?, String) {
        let (data, status, error) = get("https://api.kimi.com/coding/v1/usages", token: token)
        if status == 401 { return (nil, "Token expired") }
        if let error, data == nil { return (nil, error) }
        guard status == 200, let data,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["usage"] as? [String: Any] != nil else {
            return (nil, status == 0 ? "Offline" : "HTTP \(status)")
        }
        guard let usage = parseKimiAPI(json) else {
            return (nil, "Couldn’t parse Kimi usage")
        }
        return (usage, "")
    }

    static func parseKimiAPI(_ json: [String: Any]) -> ProviderUsage? {
        guard let usage = json["usage"] as? [String: Any],
              let limitString = usage["limit"] as? String,
              let usedString = usage["used"] as? String,
              let limit = Double(limitString),
              let used = Double(usedString) else { return nil }

        var windows: [UsageWindow] = []
        let weeklyPercent = limit > 0 ? (used / limit) * 100 : 0
        windows.append(UsageWindow(label: "Weekly", shortLabel: "W",
                                   usedPercent: weeklyPercent,
                                   resetsAt: parseDate(usage["resetTime"]),
                                   durationMinutes: 10_080))

        if let limits = json["limits"] as? [[String: Any]] {
            for limitObj in limits {
                guard let window = limitObj["window"] as? [String: Any],
                      let duration = (window["duration"] as? NSNumber)?.doubleValue,
                      duration == 300,
                      (window["timeUnit"] as? String) == "TIME_UNIT_MINUTE",
                      let detail = limitObj["detail"] as? [String: Any],
                      let detailLimitString = detail["limit"] as? String,
                      let detailUsedString = detail["used"] as? String,
                      let detailLimit = Double(detailLimitString),
                      let detailUsed = Double(detailUsedString) else { continue }
                let percent = detailLimit > 0 ? (detailUsed / detailLimit) * 100 : 0
                windows.append(UsageWindow(label: "5 hours", shortLabel: "5h",
                                           usedPercent: percent,
                                           resetsAt: parseDate(detail["resetTime"]),
                                           durationMinutes: 300))
            }
        }

        return windows.isEmpty ? nil : ProviderUsage(windows: windows, fetchedAt: Date())
    }

    static func windowLabel(minutes: Int) -> (String, String) {
        if minutes == 300 { return ("5 hours", "5h") }
        if minutes == 10_080 { return ("Weekly", "W") }
        if minutes % 10_080 == 0 { return ("\(minutes / 10_080) weeks", "\(minutes / 10_080)w") }
        if minutes % 1_440 == 0 { return ("\(minutes / 1_440) days", "\(minutes / 1_440)d") }
        if minutes % 60 == 0 { return ("\(minutes / 60) hours", "\(minutes / 60)h") }
        return ("\(minutes) minutes", "\(minutes)m")
    }

    static func parseCodexRateLimits(_ object: [String: Any]) -> ProviderUsage? {
        let result = (object["result"] as? [String: Any]) ?? object
        var candidates: [[String: Any]] = []
        if let rateLimits = result["rateLimits"] as? [String: Any] {
            if let primary = rateLimits["primary"] as? [String: Any] { candidates.append(primary) }
            if let secondary = rateLimits["secondary"] as? [String: Any] { candidates.append(secondary) }
        }
        if let buckets = result["rateLimitsByLimitId"] as? [String: Any] {
            let preferred = (buckets["codex"] as? [String: Any]) ?? buckets.values.compactMap { $0 as? [String: Any] }.first
            if let preferred {
                if let primary = preferred["primary"] as? [String: Any] { candidates.append(primary) }
                if let secondary = preferred["secondary"] as? [String: Any] { candidates.append(secondary) }
            }
        }

        var seen = Set<Int>()
        let windows = candidates.compactMap { value -> UsageWindow? in
            guard let duration = (value["windowDurationMins"] as? NSNumber)?.intValue,
                  let percent = (value["usedPercent"] as? NSNumber)?.doubleValue,
                  seen.insert(duration).inserted else { return nil }
            let labels = windowLabel(minutes: duration)
            return UsageWindow(label: labels.0, shortLabel: labels.1, usedPercent: percent,
                               resetsAt: parseDate(value["resetsAt"]), durationMinutes: duration)
        }.sorted { ($0.durationMinutes ?? 0) < ($1.durationMinutes ?? 0) }
        return windows.isEmpty ? nil : ProviderUsage(windows: windows, fetchedAt: Date())
    }

    static func parseGrokTerminal(_ raw: String) -> ProviderUsage? {
        let stripped = raw.replacingOccurrences(of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
                                                 with: "", options: .regularExpression)
        guard let range = stripped.range(of: #"Weekly limit:\s*([0-9]+(?:\.[0-9]+)?)%"#,
                                         options: .regularExpression) else { return nil }
        let match = String(stripped[range])
        guard let percentString = match.split(separator: ":").last?.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "%", with: ""),
              let percent = Double(percentString) else { return nil }

        var reset: Date?
        if let resetRange = stripped.range(of: #"Next reset:\s*[^\r\n]+"#, options: .regularExpression) {
            let line = String(stripped[resetRange])
            let value = line.replacingOccurrences(of: "Next reset:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMMM d, HH:mm"
            if let partial = formatter.date(from: value) {
                let calendar = Calendar.current
                var components = calendar.dateComponents([.month, .day, .hour, .minute], from: partial)
                components.year = calendar.component(.year, from: Date())
                reset = calendar.date(from: components)
                if let candidate = reset, candidate < Date().addingTimeInterval(-86_400) {
                    components.year = (components.year ?? 0) + 1
                    reset = calendar.date(from: components)
                }
            }
        }
        return ProviderUsage(windows: [UsageWindow(label: "Weekly", shortLabel: "W",
            usedPercent: percent, resetsAt: reset, durationMinutes: 10_080)], fetchedAt: Date())
    }
}

enum UsageCache {
    private static func key(_ id: String) -> String { "provider-usage-cache-\(id)" }

    static func save(_ id: String, _ usage: ProviderUsage) {
        if let data = try? JSONEncoder().encode(usage) {
            UserDefaults.standard.set(data, forKey: key(id))
        }
    }

    static func load(_ id: String) -> ProviderUsage? {
        guard let data = UserDefaults.standard.data(forKey: key(id)) else { return nil }
        return try? JSONDecoder().decode(ProviderUsage.self, from: data)
    }

    static func initialStates(
        _ profiles: [AccountProfile],
        loader: (String) -> ProviderUsage? = { UsageCache.load($0) }
    ) -> [String: UsageState] {
        var states: [String: UsageState] = [:]
        for profile in profiles {
            if let cached = loader(profile.id) {
                states[profile.id] = .fresh(cached)
            }
        }
        return states
    }
}
