import AppKit

enum Render {
    static func color(_ percent: Double) -> NSColor {
        if percent >= 90 { return .systemRed }
        if percent >= 70 { return .systemOrange }
        return .systemGreen
    }

    private static func drawBar(_ percent: Double, in rect: NSRect) {
        let radius = rect.height / 2
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        let clamped = min(max(percent, 0), 100)
        let width = max(rect.height, rect.width * CGFloat(clamped) / 100)
        color(clamped).setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: width,
                                       height: rect.height).intersection(rect),
                     xRadius: radius, yRadius: radius).fill()
    }

    static func countdown(_ date: Date?) -> String {
        guard let date else { return "" }
        let difference = Int(date.timeIntervalSinceNow)
        if difference <= 0 { return "now" }
        if difference >= 86_400 { return "\((difference + 43_200) / 86_400)d" }
        if difference >= 1_800 { return "\((difference + 1_800) / 3_600)h" }
        return "\(max(1, difference / 60))m"
    }

    /// Visible empty-state glyph for first run / no accounts — template so it follows menu-bar tint.
    static func emptyStatusIcon() -> NSImage {
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let text = NSAttributedString(string: "Usage", attributes: [
            .font: font,
            .foregroundColor: NSColor.black,
        ])
        let size = text.size()
        let image = NSImage(size: NSSize(width: ceil(size.width) + 2, height: 18), flipped: false) { rect in
            text.draw(at: NSPoint(x: 1, y: (rect.height - size.height) / 2))
            return true
        }
        image.isTemplate = true
        return image
    }

    static func statusText(usage: ProviderUsage?, stale: Bool) -> NSImage {
        let windows = usage?.windows.prefix(2).map { $0 } ?? []
        if windows.isEmpty {
            return emptyStatusIcon()
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let dim: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]

        func line(_ window: UsageWindow) -> NSAttributedString {
            let result = NSMutableAttributedString()
            let label = window.durationMinutes == 300 ? "S" : window.shortLabel
            result.append(NSAttributedString(string: "\(label):", attributes: dim))
            let valueColor: NSColor = window.usedPercent >= 90 ? .systemRed
                : window.usedPercent >= 70 ? .systemOrange : .labelColor
            result.append(NSAttributedString(string: String(format: "%.0f%%", window.usedPercent),
                attributes: [.font: font, .foregroundColor: valueColor]))
            let reset = countdown(window.resetsAt)
            if !reset.isEmpty { result.append(NSAttributedString(string: "/\(reset)", attributes: dim)) }
            if stale { result.append(NSAttributedString(string: "~", attributes: dim)) }
            return result
        }

        let lines = windows.map(line)
        let textWidth = ceil(lines.map { $0.size().width }.max() ?? 8) + 1
        let image = NSImage(size: NSSize(width: textWidth, height: 21), flipped: false) { _ in
            if lines.count == 1 {
                lines[0].draw(at: NSPoint(x: 0, y: 5.5))
            } else {
                lines[0].draw(at: NSPoint(x: 0, y: 10.5))
                lines[1].draw(at: NSPoint(x: 0, y: 0.5))
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    static func gaugeImage(_ percent: Double) -> NSImage {
        let image = NSImage(size: NSSize(width: 36, height: 7), flipped: false) { rect in
            drawBar(percent, in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }

    static func resetText(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        let nearTerm = date.timeIntervalSinceNow < 22 * 3_600
        formatter.dateFormat = nearTerm ? "h:mma" : "EEE ha"
        return formatter.string(from: nearTerm ? date : date.addingTimeInterval(1_800)).lowercased()
    }

    static func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func accountTitle(profile: AccountProfile, state: UsageState?) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        result.append(NSAttributedString(string: profile.name, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
        ]))

        let regular: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
        ]
        let dim: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph,
        ]

        func gauge(_ window: UsageWindow) -> NSAttributedString {
            let label = window.durationMinutes == 300 ? "5h"
                : window.durationMinutes == 10_080 ? "wk" : window.shortLabel.lowercased()
            let line = NSMutableAttributedString(string: "\(label) ", attributes: dim)
            let attachment = NSTextAttachment()
            attachment.image = gaugeImage(window.usedPercent)
            attachment.bounds = CGRect(x: 0, y: 0.5, width: 36, height: 7)
            line.append(NSAttributedString(attachment: attachment))
            line.append(NSAttributedString(string: String(format: " %.0f%%", window.usedPercent), attributes: regular))
            let reset = resetText(window.resetsAt)
            if !reset.isEmpty { line.append(NSAttributedString(string: " \(reset)", attributes: dim)) }
            return line
        }

        result.append(NSAttributedString(string: "\n", attributes: dim))
        switch state {
        case .fresh(let usage), .stale(let usage, _):
            for (index, window) in usage.windows.enumerated() {
                if index > 0 { result.append(NSAttributedString(string: "   ·   ", attributes: dim)) }
                result.append(gauge(window))
            }
            if case .stale(_, let reason) = state {
                let note = reason == "Token expired" ? "Token expired — refreshing…" : reason
                result.append(NSAttributedString(string: "\n\(note)", attributes: dim))
            }
        case .unavailable(let reason):
            result.append(NSAttributedString(string: reason, attributes: dim))
        case nil:
            result.append(NSAttributedString(string: "Loading…", attributes: dim))
        }
        return result
    }
}
