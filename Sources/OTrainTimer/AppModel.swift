import AppKit
import SwiftUI

@MainActor @Observable
final class AppModel {
  var journeys: [Journey] = []
  private(set) var selectedJourneyID: UUID?
  var schedule: Schedule?
  var notices: [ServiceNotice] = []
  var scheduleError: String?
  var noticeError: String?
  var persistenceError: String?
  var noticeCheckedAt: Date?
  var loadingSchedule = false
  var loadingNotices = false
  var now = Date()
  var awake = true
  private var started = false
  private var scheduleAttempt: Date?
  private var noticeAttempt: Date?
  private let repository = FeedRepository()
  private let preferencesKey = "savedJourneys.v1"
  private let selectionKey = "selectedJourney.v1"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: preferencesKey) {
      do { journeys = try JSONDecoder().decode([Journey].self, from: data) } catch {
        persistenceError = "Saved journeys could not be read. The original data remains unchanged."
      }
    }
    let savedID = defaults.string(forKey: selectionKey).flatMap(UUID.init(uuidString:))
    selectedJourneyID = journeys.first(where: { $0.id == savedID })?.id ?? journeys.first?.id
  }

  var selectedJourney: Journey? {
    journeys.first { $0.id == selectedJourneyID }
  }

  var selectedDepartureStatus: DepartureStatus? {
    guard let journey = selectedJourney, let schedule,
      let departure = schedule.departures(for: journey, now: now).first
    else { return nil }
    return DepartureStatus.evaluate(
      secondsUntilDeparture: departure.timeIntervalSince(now),
      walkingMinutes: journey.walkingMinutes)
  }

  func journeyLabel(_ journey: Journey) -> String {
    let station = schedule?.stations.first { $0.id == journey.stationID }?.name ?? journey.stationID
    let service =
      schedule?.services.first { $0.id == journey.serviceID }?.label ?? journey.serviceID
    return
      "\(journey.source) → \(station) · \(service) · \(journey.walkingMinutes.formatted()) min walk"
  }

  var menuBarDescription: String {
    guard let journey = selectedJourney else { return "O-Train Timer: no journey selected" }
    return "\(journeyLabel(journey)): \(selectedDepartureStatus?.title ?? "Schedule unavailable")"
  }

  func selectJourney(_ id: UUID) {
    guard journeys.contains(where: { $0.id == id }) else { return }
    selectedJourneyID = id
    defaults.set(id.uuidString, forKey: selectionKey)
  }

  func start() async {
    guard !started else { return }
    started = true
    schedule = await repository.cachedSchedule()
    await refresh()
  }

  func wake() async {
    awake = true
    now = Date()
    noticeAttempt = nil
    await refresh()
  }

  func save(_ journey: Journey) {
    if let index = journeys.firstIndex(where: { $0.id == journey.id }) {
      journeys[index] = journey
    } else {
      journeys.append(journey)
    }
    if selectedJourney == nil { selectJourney(journey.id) }
    persist()
  }

  func delete(_ journey: Journey) {
    journeys.removeAll { $0.id == journey.id }
    if selectedJourney == nil {
      selectedJourneyID = journeys.first?.id
      if let selectedJourneyID {
        defaults.set(selectedJourneyID.uuidString, forKey: selectionKey)
      } else {
        defaults.removeObject(forKey: selectionKey)
      }
    }
    persist()
  }

  private func persist() {
    do {
      defaults.set(try JSONEncoder().encode(journeys), forKey: preferencesKey)
      persistenceError = nil
    } catch { persistenceError = "Journeys could not be saved." }
  }

  func refresh(force: Bool = false) async {
    guard awake else { return }
    now = Date()
    // Independent refreshes: a large schedule download must not delay service warnings.
    async let scheduleRefresh: Void = refreshSchedule(force: force)
    async let noticeRefresh: Void = refreshNotices(force: force)
    _ = await (scheduleRefresh, noticeRefresh)
  }

  private func refreshSchedule(force: Bool) async {
    let stale = schedule.map { now.timeIntervalSince($0.fetchedAt) >= 86400 } ?? true
    let retryDue = scheduleAttempt.map { now.timeIntervalSince($0) >= 900 } ?? true
    guard !loadingSchedule, force || (stale && retryDue) else { return }
    loadingSchedule = true
    scheduleAttempt = now
    defer { loadingSchedule = false }
    do {
      schedule = try await repository.refreshSchedule()
      scheduleError = nil
    } catch { scheduleError = error.localizedDescription }
  }

  private func refreshNotices(force: Bool) async {
    let due = noticeAttempt.map { now.timeIntervalSince($0) >= 120 } ?? true
    guard !loadingNotices, force || due else { return }
    loadingNotices = true
    noticeAttempt = now
    defer { loadingNotices = false }
    do {
      notices = try await repository.refreshNotices()
      noticeCheckedAt = Date()
      noticeError = nil
    } catch { noticeError = error.localizedDescription }
  }

  var todayNotices: [ServiceNotice] {
    notices.filter { $0.publishedToday(relativeTo: now) }
  }

  func relevantNotices(for journey: Journey) -> [ServiceNotice] {
    guard let schedule else { return [] }
    return todayNotices.filter { $0.relevant(to: journey, in: schedule) }
  }

  var hasWarning: Bool {
    noticeError != nil || scheduleError != nil
      || journeys.contains { !relevantNotices(for: $0).isEmpty }
  }
}

@main
struct OTrainTimerApp: App {
  @State private var model = AppModel()
  private let timer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

  var body: some Scene {
    MenuBarExtra {
      MenuContent(model: model)
    } label: {
      Image(nsImage: MenuBarTrain.image(for: model.selectedDepartureStatus))
        .accessibilityLabel(model.menuBarDescription)
        .help(model.menuBarDescription)
        .task { await model.start() }
        .onReceive(timer) { date in
          guard model.awake else { return }
          model.now = date
          Task { await model.refresh() }
        }
        .onReceive(
          NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
        ) { _ in
          model.awake = false
        }
        .onReceive(
          NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
        ) { _ in
          Task { await model.wake() }
        }
    }
    .menuBarExtraStyle(.window)

    Window("O-Train Timer Settings", id: "settings") {
      SettingsContent(model: model)
    }
    .defaultSize(width: 620, height: 560)
  }
}
