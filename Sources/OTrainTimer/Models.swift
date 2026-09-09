import Foundation

struct Journey: Codable, Identifiable, Equatable {
  var id = UUID()
  var source: String
  var stationID: String
  var serviceID: String
  var walkingMinutes: Double
}

struct Station: Codable, Identifiable, Hashable {
  var id: String
  var name: String
}

struct RailService: Codable, Identifiable, Hashable {
  var id: String
  var line: String
  var headsign: String
  var stationIDs: Set<String>
  var label: String { "Line \(line) → \(headsign)" }
}

struct ScheduledStop: Codable {
  var stationID: String
  var serviceID: String
  var calendarID: String
  var seconds: Int
}

struct ServiceCalendar: Codable {
  var start: String
  var end: String
  var weekdays: [Bool]  // Sunday first.
}

struct Schedule: Codable {
  var fetchedAt: Date
  var stations: [Station]
  var services: [RailService]
  var stops: [ScheduledStop]
  var calendars: [String: ServiceCalendar]
  var exceptions: [String: [String: Bool]]

  static var ottawaCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Toronto")!
    return calendar
  }

  static func dateKey(_ date: Date) -> String {
    let components = ottawaCalendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d%02d%02d", components.year!, components.month!, components.day!)
  }

  func active(_ id: String, on date: Date) -> Bool {
    let key = Self.dateKey(date)
    if let exception = exceptions[id]?[key] { return exception }
    guard let rule = calendars[id], key >= rule.start, key <= rule.end else { return false }
    return rule.weekdays[Self.ottawaCalendar.component(.weekday, from: date) - 1]
  }

  func departures(for journey: Journey, now: Date) -> [Date] {
    let relevant = stops.filter {
      $0.stationID == journey.stationID && $0.serviceID == journey.serviceID
    }
    let calendar = Self.ottawaCalendar
    var dates: Set<Date> = []
    // Include previous service days for GTFS times beyond 24:00.
    let daysBack = max(1, (relevant.map(\.seconds).max() ?? 0) / 86400)
    for offset in (-daysBack)...2 {
      guard let day = calendar.date(byAdding: .day, value: offset, to: now),
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)
      else { continue }
      // GTFS defines service-day zero as noon minus twelve hours, including DST days.
      let zero = noon.addingTimeInterval(-43200)
      for stop in relevant where active(stop.calendarID, on: day) {
        let departure = zero.addingTimeInterval(Double(stop.seconds))
        if departure > now { dates.insert(departure) }
      }
    }
    return dates.sorted()
  }
}

enum DepartureStatus: String {
  case early, leave, tight, late

  static func evaluate(secondsUntilDeparture: Double, walkingMinutes: Double) -> Self {
    let walk = walkingMinutes * 60
    if secondsUntilDeparture > walk + 120 { return .early }
    if secondsUntilDeparture >= walk { return .leave }
    if secondsUntilDeparture >= walk - 60 { return .tight }
    return .late
  }

  var title: String {
    switch self {
    case .early: "Too early"
    case .leave: "Leave now"
    case .tight: "Tight timing — you may miss it"
    case .late: "Too late for this train"
    }
  }
}

struct ServiceNotice: Identifiable, Sendable {
  var id: String
  var title: String
  var detail: String
  var url: URL?
  var published: Date?
  var affectedLines: Set<String> = []

  func publishedToday(relativeTo now: Date) -> Bool {
    guard let published else { return false }
    return Schedule.ottawaCalendar.isDate(published, inSameDayAs: now)
  }

  func relevant(to journey: Journey, in schedule: Schedule) -> Bool {
    let text = (title + " " + detail).lowercased()
    if text.contains("o-train") || text.contains("otrain") { return true }
    if let station = schedule.stations.first(where: { $0.id == journey.stationID }),
      text.contains(station.name.lowercased())
    {
      return true
    }
    guard let service = schedule.services.first(where: { $0.id == journey.serviceID }) else {
      return false
    }
    if affectedLines.contains(service.line) { return true }
    let pattern = "\\blines?\\s*" + NSRegularExpression.escapedPattern(for: service.line) + "\\b"
    return text.range(of: pattern, options: .regularExpression) != nil
      || (service.line == "1" && text.contains("confederation"))
      || (service.line == "2" && text.contains("trillium"))
  }
}
