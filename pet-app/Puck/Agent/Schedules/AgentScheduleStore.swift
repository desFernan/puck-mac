//
//  AgentScheduleStore.swift
//  Puck
//
//  The schedules, kept between launches, and the clock that fires them.
//
//  Beside `workspaces.json` and `chats.json`, for the same reason and in the
//  same shape: a schedule that did not survive a restart would be one nobody
//  could rely on, which is the whole of what a schedule is for.
//

import Foundation

@MainActor
final class AgentScheduleStore: ObservableObject {
    @Published private(set) var schedules: [AgentSchedule] = []

    /// Called when one is due, with the prompt to run and where to run it.
    /// The store never runs anything itself -- what an agent turn is belongs
    /// to AgentHost, and a store that could start one would be a second place
    /// that knows how.
    var onDue: ((AgentSchedule) -> Void)?

    private let storageURL: URL
    private var timer: Timer?
    /// How often the clock looks. A minute, because the finest schedule
    /// anyone can express is minutes -- checking every second would be
    /// fifty-nine wasted looks out of sixty.
    static let tickInterval: TimeInterval = 60

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        load()
    }

    static func defaultStorageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Puck/schedules.json")
    }

    // MARK: - The clock

    /// Starts looking. Also looks once now, which is what runs a schedule
    /// whose time passed while the app was shut.
    func start(now: @escaping () -> Date = Date.init) {
        stop()
        tick(now: now())
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(now: now()) }
        }
        // `.common`, so a schedule still fires while a menu is open or
        // something is being dragged -- the same reason the notch's own timer
        // is on it.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Fires everything that is due, and writes down that it did.
    ///
    /// Marked as fired before the callback rather than after: `onDue` starts
    /// an agent turn, and a turn that throws -- or an app that quits during
    /// one -- must not leave the schedule looking due forever, firing again
    /// on every tick.
    func tick(now: Date) {
        let due = schedules.filter { $0.isDue(at: now) }
        guard !due.isEmpty else { return }
        for schedule in due {
            guard let index = schedules.firstIndex(where: { $0.id == schedule.id }) else { continue }
            schedules[index].lastFiredAt = now
        }
        save()
        for schedule in due { onDue?(schedule) }
    }

    // MARK: - Keeping them

    func add(_ schedule: AgentSchedule) {
        schedules.append(schedule)
        save()
    }

    func remove(id: String) {
        schedules.removeAll { $0.id == id }
        save()
    }

    func setEnabled(_ isEnabled: Bool, id: String) {
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { return }
        schedules[index].isEnabled = isEnabled
        save()
    }

    /// Drops every schedule belonging to a workspace that has gone -- it
    /// names a project that no longer exists, so it can never run again.
    func removeAll(inWorkspace workspaceId: String) {
        let before = schedules.count
        schedules.removeAll { $0.workspaceId == workspaceId }
        if schedules.count != before { save() }
    }

    // MARK: - The file

    private struct Persisted: Codable {
        let version: Int
        let schedules: [AgentSchedule]
    }

    private static let storeVersion = 1

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let parsed = try? JSONDecoder().decode(Persisted.self, from: data),
              parsed.version == Self.storeVersion
        else {
            // Starting empty loses schedules, never work -- unlike the chat
            // archive there is nothing here that cannot be said again, so
            // this does not go to the lengths of backing the file up.
            return
        }
        schedules = parsed.schedules
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(Persisted(version: Self.storeVersion, schedules: schedules))
            try data.write(to: storageURL, options: .atomic)
        } catch {
            AppLogger.shared.log(.error, "could not save schedules: \(error)")
        }
    }
}
