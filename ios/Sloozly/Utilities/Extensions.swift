import Foundation
import SwiftUI

// MARK: - Date Extensions

extension Date {
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
    
    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }
    
    var isTomorrow: Bool {
        Calendar.current.isDateInTomorrow(self)
    }
    
    var relativeString: String {
        if isToday {
            return "Today"
        } else if isYesterday {
            return "Yesterday"
        } else if isTomorrow {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: self)
        }
    }
    
    func timeAgoString() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - String Extensions

extension String {
    var isNotEmpty: Bool {
        !isEmpty
    }
    
    func truncated(to length: Int, trailing: String = "...") -> String {
        if count > length {
            return String(prefix(length)) + trailing
        }
        return self
    }
}

// MARK: - Int Extensions (Currency)

extension Int {
    var centsToUSD: String {
        String(format: "$%.2f", Double(self) / 100.0)
    }
}

// MARK: - View Extensions

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Color Extensions

extension Color {
    static let sloozlyPrimary = Color("PrimaryColor")
    static let sloozlySecondary = Color("SecondaryColor")
    static let sloozlyAccent = Color("AccentColor")
    static let sloozlyBackground = Color("BackgroundColor")
    
    // Fallback colors if assets not defined
    static let primaryBlue = Color(red: 0.0, green: 0.48, blue: 1.0)
    static let warningOrange = Color(red: 1.0, green: 0.58, blue: 0.0)
    static let successGreen = Color(red: 0.2, green: 0.78, blue: 0.35)
    static let errorRed = Color(red: 1.0, green: 0.27, blue: 0.23)
}

// MARK: - Optional Extensions

extension Optional where Wrapped == String {
    var orEmpty: String {
        self ?? ""
    }
    
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}

// MARK: - Array Extensions

extension Array where Element == Int {
    var asDayOfWeekSet: Set<DayOfWeek> {
        Set(compactMap { DayOfWeek(rawValue: $0) })
    }
}

extension Set where Element == DayOfWeek {
    var asIntArray: [Int] {
        map { $0.rawValue }.sorted()
    }
}
