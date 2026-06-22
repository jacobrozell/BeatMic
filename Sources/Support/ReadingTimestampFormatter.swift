import Foundation

enum ReadingTimestampFormatter {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    static func string(for date: Date) -> String {
        formatter.string(from: date)
    }
}
