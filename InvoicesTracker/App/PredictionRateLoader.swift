import Foundation

/// Loads daily prediction conversions through the same declaration rule used by stored payments.
@MainActor
final class PredictionRateLoader {
    private weak var scopedDatabase: Database?
    private var scopedDay: CivilDate?
    private var scope = UUID()
    private var completedYears: Set<Int> = []
    private var inFlight: [Int: Fetch] = [:]
    private var latestLoadID = 0
    private var failedThroughLoad: [Int: Int] = [:]

    /// A retrieval's identity keeps an older completion from changing a newer scope's bookkeeping.
    private struct Fetch {
        let id: UUID
        let task: Task<Bool, Never>
    }

    /// Resolves the original keys, capping future dates at today and using a provisional rate only for today.
    func load(
        keys: Set<PredictionRateKey>, database: Database, today: CivilDate,
        fetchYears: @escaping @MainActor ([Int]) async -> Bool
    ) async throws -> [PredictionRateKey: StoredRate] {
        try Task.checkCancellation()
        if scopedDatabase !== database || scopedDay != today {
            scopedDatabase = database
            scopedDay = today
            scope = UUID()
            completedYears = []
            inFlight = [:]
            failedThroughLoad = [:]
        }
        latestLoadID += 1
        let loadID = latestLoadID
        let loadScope = scope
        var years: Set<Int> = []
        for key in keys {
            let day = min(key.day, today)
            let lookup = try await database.cnbRate(key.currency, on: day)
            try checkCurrent(loadScope)
            if lookup == .notYetAvailable {
                let expected = CzechCalendar.rateDeclarationDay(for: day)
                let previous = CzechCalendar.previousBusinessDay(onOrBefore: expected.adding(days: -1))
                let next = CzechCalendar.nextBusinessDay(onOrAfter: day.adding(days: 1))
                years.formUnion([day.year, expected.year, previous.year, next.year].filter { $0 <= today.year })
            }
        }
        for year in years.sorted() {
            guard !completedYears.contains(year), loadID > (failedThroughLoad[year] ?? 0) else { continue }
            let fetch: Fetch
            if let existing = inFlight[year] {
                fetch = existing
            } else {
                let id = UUID()
                let task = Task { @MainActor [weak self] in
                    let stored = await fetchYears([year])
                    if let self, self.scope == loadScope, self.inFlight[year]?.id == id {
                        self.inFlight[year] = nil
                        if stored {
                            self.completedYears.insert(year)
                            self.failedThroughLoad[year] = nil
                        } else {
                            // Loads already reading the database share this failure; a later load may retry.
                            self.failedThroughLoad[year] = self.latestLoadID
                        }
                    }
                    return stored
                }
                fetch = Fetch(id: id, task: task)
                inFlight[year] = fetch
            }
            _ = await fetch.task.value
            try checkCurrent(loadScope)
        }
        var rates: [PredictionRateKey: StoredRate] = [:]
        for key in keys {
            let day = min(key.day, today)
            let lookup = try await database.cnbRate(key.currency, on: day)
            try checkCurrent(loadScope)
            switch lookup {
            case .declared(let rate, let declaredOn):
                rates[key] = StoredRate(rate: rate, declaredOn: declaredOn)
            case .notYetAvailable where day == today:
                rates[key] = try await database.latestCNBRate(key.currency, onOrBefore: today)
            case .notYetAvailable, .notPublished:
                break
            }
        }
        try checkCurrent(loadScope)
        return rates
    }

    /// A canceled caller or a superseded vault/day cannot publish rates or modify the current attempt state.
    private func checkCurrent(_ loadScope: UUID) throws {
        try Task.checkCancellation()
        guard scope == loadScope else { throw CancellationError() }
    }
}
