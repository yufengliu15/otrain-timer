import Foundation
import Testing

@testable import OTrainTimer

@Test @MainActor func selectionPersistsAndHandlesDeletion() {
  let suite = "OTrainTimerTests.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }
  let model = AppModel(defaults: defaults)
  let first = Journey(source: "Home", stationID: "s", serviceID: "r", walkingMinutes: 10)
  let second = Journey(source: "Work", stationID: "s", serviceID: "r", walkingMinutes: 20)
  #expect(model.selectedJourney == nil)
  #expect(model.selectedDepartureStatus == nil)
  model.save(first)
  model.save(second)
  #expect(model.selectedJourneyID == first.id)
  model.selectJourney(second.id)
  #expect(model.selectedJourneyID == second.id)
  model.selectJourney(UUID())
  #expect(model.selectedJourneyID == second.id)
  let restored = AppModel(defaults: defaults)
  #expect(restored.selectedJourneyID == second.id)
  restored.delete(first)
  #expect(restored.selectedJourneyID == second.id)
  restored.save(first)
  restored.delete(second)
  #expect(restored.selectedJourneyID == first.id)
  restored.delete(first)
  #expect(restored.selectedJourneyID == nil)
  #expect(AppModel(defaults: defaults).selectedJourneyID == nil)
}

@Test @MainActor func menuBarUsesOnlySelectedJourneyTiming() {
  let suite = "OTrainTimerTests.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }
  let model = AppModel(defaults: defaults)
  let first = Journey(source: "Home", stationID: "s", serviceID: "r", walkingMinutes: 10)
  let second = Journey(source: "Work", stationID: "s", serviceID: "r", walkingMinutes: 20)
  model.save(first)
  model.save(second)
  let start = ISO8601DateFormatter().date(from: "2026-09-08T12:00:00Z")!
  model.schedule = Schedule(
    fetchedAt: start, stations: [Station(id: "s", name: "Bayview")],
    services: [RailService(id: "r", line: "2", headsign: "Limebank", stationIDs: ["s"])],
    stops: [
      ScheduledStop(stationID: "s", serviceID: "r", calendarID: "c", seconds: 8 * 3600 + 720)
    ],
    calendars: [:], exceptions: ["c": ["20260908": true]])
  model.now = start.addingTimeInterval(-1)
  #expect(model.selectedDepartureStatus == .early)
  model.now = start
  #expect(model.selectedDepartureStatus == .leave)
  model.selectJourney(second.id)
  #expect(model.selectedDepartureStatus == .late)
  model.selectJourney(first.id)
  model.noticeError = "HTTP 403"
  model.scheduleError = "Offline; cached schedule in use"
  #expect(model.selectedDepartureStatus == .leave)
  model.now = start.addingTimeInterval(121)
  #expect(model.selectedDepartureStatus == .tight)
  model.now = start.addingTimeInterval(181)
  #expect(model.selectedDepartureStatus == .late)
  model.now = start.addingTimeInterval(721)
  #expect(model.selectedDepartureStatus == nil)
  model.schedule = nil
  #expect(model.selectedDepartureStatus == nil)
}

@Test @MainActor func legacyJourneysSelectFirstWhenSavedSelectionIsMissing() throws {
  let suite = "OTrainTimerTests.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }
  let journey = Journey(source: "Home", stationID: "s", serviceID: "r", walkingMinutes: 10)
  defaults.set(try JSONEncoder().encode([journey]), forKey: "savedJourneys.v1")
  #expect(AppModel(defaults: defaults).selectedJourneyID == journey.id)
  defaults.set(UUID().uuidString, forKey: "selectedJourney.v1")
  #expect(AppModel(defaults: defaults).selectedJourneyID == journey.id)
}
