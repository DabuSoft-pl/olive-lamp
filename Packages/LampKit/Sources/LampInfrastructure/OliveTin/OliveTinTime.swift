import Foundation

/// OliveTin writes times as "2006-01-02 15:04:05" in the server's time zone, without an offset, and the zero time
/// ("0001-01-01 …") for "not yet". The Mac is assumed to share the server's zone, as the web page does.
enum OliveTinTime {
    static func parse(_ text: String?, timeZone: TimeZone = .current) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty, !text.hasPrefix("0001") else { return nil }
        if let date = try? Date(text, strategy: .iso8601) { return date }
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "T" })
        guard parts.count >= 2 else { return nil }
        let day = parts[0].split(separator: "-").compactMap { Int($0) }
        let time = parts[1].split(separator: ":").compactMap { Int(Double($0) ?? -1) }
        guard day.count == 3, time.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: day[0], month: day[1], day: day[2], hour: time[0], minute: time[1], second: time[2]))
    }
}
