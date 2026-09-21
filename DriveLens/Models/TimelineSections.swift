import Foundation

struct TimelineSection: Identifiable, Equatable {
    let id: String
    let items: [MediaItem]
}

struct TimelineSectionInput: Equatable {
    let items: [MediaItem]
    let sort: TimelineSortOption
}

enum TimelineSections {
    /// Formats once per day rather than once per media item; safe to run off the main actor.
    static func make(_ input: TimelineSectionInput) -> [TimelineSection] {
        let items = input.items
        switch input.sort {
        case .fileName:
            return Dictionary(grouping: items) { item -> String in
                guard let first = item.filename.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "#" }
                return first.isLetter ? String(first).uppercased() : "#"
            }.map { key, values in
                TimelineSection(id: key, items: values.sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending })
            }.sorted {
                if $0.id == "#" { return false }
                if $1.id == "#" { return true }
                return $0.id < $1.id
            }
        case .largestFile:
            return [TimelineSection(id: "Largest Files", items: items.sorted {
                $0.fileSize == $1.fileSize ? $0.captureDate > $1.captureDate : $0.fileSize > $1.fileSize
            })]
        default:
            let calendar = Calendar.current
            let added = input.sort == .recentlyAdded
            let ascending = input.sort == .captureOldest
            var days: [Date: [MediaItem]] = [:]
            var interval: DateInterval?
            for (index, item) in items.enumerated() {
                if index.isMultiple(of: 256), Task.isCancelled { return [] }
                let date = added ? item.addedAt : item.captureDate
                // Catalogue pages are date ordered. Reuse the current calendar interval;
                // comparing Dates is much cheaper than resolving a calendar day per item.
                if interval == nil || date < interval!.start || date >= interval!.end {
                    interval = calendar.dateInterval(of: .day, for: date)
                }
                days[interval?.start ?? calendar.startOfDay(for: date), default: []].append(item)
            }
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            return days.keys.sorted(by: ascending ? (<) : (>)).map { day in
                TimelineSection(id: (added ? "Added " : "") + formatter.string(from: day), items: days[day]!.sorted {
                    let left = added ? $0.addedAt : $0.captureDate
                    let right = added ? $1.addedAt : $1.captureDate
                    return ascending ? left < right : left > right
                })
            }
        }
    }
}
