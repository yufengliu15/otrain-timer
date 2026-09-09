import Foundation
import Testing

@testable import OTrainTimer

// Explicit opt-in: these tests access public feeds and populate the app's schedule cache.
@Test(.enabled(if: ProcessInfo.processInfo.environment["OTRAIN_LIVE_TESTS"] == "1"))
func livePublicFeeds() async throws {
  let repository = FeedRepository()
  let schedule = try await repository.refreshSchedule()
  let lines = Set(schedule.services.map(\.line))
  #expect(lines.isSuperset(of: ["1", "2", "4"]))
  #expect(!schedule.stations.isEmpty)
  let now = Date()
  let service = try #require(schedule.services.first)
  let station = try #require(service.stationIDs.first)
  let journey = Journey(
    source: "Integration test", stationID: station, serviceID: service.id, walkingMinutes: 10)
  let departures = schedule.departures(for: journey, now: now)
  #expect(!departures.isEmpty)
  let notices = try await repository.refreshNotices()
  print(
    "Live feed check: \(schedule.stations.count) stations; \(schedule.stops.count) scheduled stops; \(departures.count) upcoming departures for test journey; \(notices.count) RSS notices."
  )
  #expect(notices.allSatisfy { !$0.title.isEmpty })
  #expect(notices.allSatisfy { $0.published != nil })
}
