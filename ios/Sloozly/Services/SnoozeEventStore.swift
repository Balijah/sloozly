import Foundation

/// File-backed persistent store for snooze events.
///
/// Events are stored as a JSON array in the app's Application Support directory.
/// This survives app restarts and enables offline retry.
final class SnoozeEventStore {

    static let shared = SnoozeEventStore()

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.sloozly.snooze-store", qos: .utility)
    private var cachedEvents: [SnoozeEvent]?

    private var storeURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Sloozly", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("snooze_events.json")
    }

    private init() {}

    /// Convenience init for testing — accepts a custom file URL.
    init(fileURL: URL) {
        self._testFileURL = fileURL
    }

    private var _testFileURL: URL?
    private var effectiveURL: URL { _testFileURL ?? storeURL }

    // MARK: - Read

    func loadEvents() -> [SnoozeEvent] {
        if let cached = cachedEvents { return cached }

        guard let data = try? Data(contentsOf: effectiveURL) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let events = (try? decoder.decode([SnoozeEvent].self, from: data)) ?? []
        cachedEvents = events
        return events
    }

    // MARK: - Write

    func save(_ events: [SnoozeEvent]) {
        cachedEvents = events
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(events) else { return }
        try? data.write(to: effectiveURL, options: .atomic)
    }

    // MARK: - Convenience

    func append(_ event: SnoozeEvent) {
        var events = loadEvents()
        events.append(event)
        save(events)
    }

    func update(_ event: SnoozeEvent) {
        var events = loadEvents()
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
            save(events)
        }
    }

    func pendingEvents() -> [SnoozeEvent] {
        loadEvents().filter { $0.status == .pending || $0.status == .failed }
    }

    func eventsForOccurrence(_ occurrenceId: String) -> [SnoozeEvent] {
        loadEvents().filter { $0.occurrenceId == occurrenceId }
    }

    func snoozeCount(for occurrenceId: String) -> Int {
        eventsForOccurrence(occurrenceId).count
    }

    func hasEvent(occurrenceId: String, snoozeNumber: Int) -> Bool {
        loadEvents().contains {
            $0.occurrenceId == occurrenceId && $0.snoozeNumber == snoozeNumber
        }
    }

    /// Remove events older than the given number of days.
    func pruneOldEvents(olderThanDays days: Int = 30) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let events = loadEvents().filter { $0.timestamp > cutoff }
        save(events)
    }

    func clearAll() {
        save([])
    }
}
