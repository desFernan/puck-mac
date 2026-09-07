//
//  UpdateChecker.swift
//  Puck
//
//  The part of the update check that talks to the network, and remembers.
//
//  Split from UpdateCheck the way LyricsClient is split from what it parses:
//  the fetching is four lines and the deciding is all of the behaviour, and
//  only one of those is worth testing against a real server.
//

import Foundation

@MainActor
final class UpdateChecker: ObservableObject {
    /// The release worth offering, once one has been found. Published so the
    /// settings window can show it without asking again.
    @Published private(set) var available: Release?
    /// Whether a check is in flight, so the manual button can say so.
    @Published private(set) var isChecking = false

    /// Called the first time a given version is found, and not again for that
    /// version -- the pet says something once, and the settings window is
    /// where it stays afterwards.
    var onFound: ((Release) -> Void)?

    private let preferences: UpdatePreferences
    private let currentVersion: AppVersion?
    private let now: () -> Date
    /// Injected so the tests answer without a network.
    private let data: (URL) async throws -> Data
    private var timer: Timer?
    /// Announced this launch, so a check that runs again while the app is up
    /// does not repeat itself.
    private var announced: AppVersion?

    init(
        preferences: UpdatePreferences = UpdatePreferences(),
        currentVersion: AppVersion? = AppVersion.current(),
        now: @escaping () -> Date = Date.init,
        data: @escaping (URL) async throws -> Data = UpdateChecker.fetch
    ) {
        self.preferences = preferences
        self.currentVersion = currentVersion
        self.now = now
        self.data = data
    }

    static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        // Nobody is waiting on this. A check that cannot be answered quickly
        // is one to abandon and repeat tomorrow.
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Puck (https://github.com/desFernan/puck-mac)", forHTTPHeaderField: "User-Agent")
        return try await URLSession.shared.data(for: request).0
    }

    // MARK: - The clock

    /// How often to look at the clock. Not how often it checks -- that is
    /// `UpdateCheck.interval` -- but how soon after a machine wakes from a
    /// week asleep the day's check happens.
    static let tickInterval: TimeInterval = 60 * 60

    /// Starts checking: once now if one is due, and hourly after that.
    func start() {
        stop()
        Task { await checkIfDue() }
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.checkIfDue() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Checks if the day has turned and the user has not switched this off.
    func checkIfDue() async {
        guard preferences.checksForUpdates else { return }
        guard UpdateCheck.isDue(lastCheckedAt: preferences.lastCheckedAt, now: now()) else { return }
        await check()
    }

    /// Checks now, whatever the clock says.
    ///
    /// The button in Settings calls this, and it deliberately ignores a
    /// version that was skipped: pressing "check now" is asking, and the
    /// answer to a question somebody asked is not "I decided not to tell
    /// you".
    func check(honouringSkip: Bool = true) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        // Written down before the request rather than after it: a GitHub that
        // is down, or a machine with no network, must not turn into a check on
        // every tick for as long as it stays that way.
        preferences.lastCheckedAt = now()
        guard let payload = try? await data(UpdateCheck.releasesURL) else { return }
        let offer = UpdateCheck.offer(
            payload: payload,
            current: currentVersion,
            skipping: honouringSkip ? preferences.skippedVersion : nil
        )
        available = offer
        guard let offer, announced != offer.version else { return }
        announced = offer.version
        onFound?(offer)
    }

    /// Turns down one version. It stays turned down until a newer one than it
    /// appears.
    func skip(_ release: Release) {
        preferences.skippedVersion = release.version.description
        available = nil
    }
}
