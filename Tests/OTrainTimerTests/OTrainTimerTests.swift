import Foundation
import Testing

@testable import OTrainTimer

@Test func statusBoundaries() {
  #expect(DepartureStatus.evaluate(secondsUntilDeparture: 721, walkingMinutes: 10) == .early)
  #expect(DepartureStatus.evaluate(secondsUntilDeparture: 720, walkingMinutes: 10) == .leave)
  #expect(DepartureStatus.evaluate(secondsUntilDeparture: 600, walkingMinutes: 10) == .leave)
  #expect(DepartureStatus.evaluate(secondsUntilDeparture: 599, walkingMinutes: 10) == .tight)
  #expect(DepartureStatus.evaluate(secondsUntilDeparture: 540, walkingMinutes: 10) == .tight)
  #expect(DepartureStatus.evaluate(secondsUntilDeparture: 539, walkingMinutes: 10) == .late)
}

@Test func csvQuotesAndNewlines() {
  var records: [[String: String]] = []
  CSV.read("\u{feff}id,name\r\n1,\"Bayview, Station\"\r\n2,\"A \"\"quoted\"\"\nname\"\r\n") {
    records.append($0)
  }
  #expect(records.count == 2)
  #expect(records[0]["name"] == "Bayview, Station")
  #expect(records[1]["name"] == "A \"quoted\"\nname")
}

private func date(_ value: String) -> Date {
  ISO8601DateFormatter().date(from: value)!
}

private func fixture() -> Schedule {
  Schedule(
    fetchedAt: Date(), stations: [Station(id: "s", name: "Bayview")],
    services: [RailService(id: "r", line: "2", headsign: "Limebank", stationIDs: ["s"])],
    stops: [ScheduledStop(stationID: "s", serviceID: "r", calendarID: "c", seconds: 25 * 3600)],
    calendars: [
      "c": ServiceCalendar(
        start: "20260101", end: "20261231", weekdays: Array(repeating: true, count: 7))
    ],
    exceptions: [:])
}

@Test func overnightAndCalendarExceptions() {
  var schedule = fixture()
  let journey = Journey(source: "Home", stationID: "s", serviceID: "r", walkingMinutes: 10)
  let now = date("2026-02-03T05:30:00Z")  // 00:30 Ottawa.
  #expect(schedule.departures(for: journey, now: now).first == date("2026-02-03T06:00:00Z"))
  schedule.exceptions["c"] = ["20260202": false]
  #expect(schedule.departures(for: journey, now: now).first == date("2026-02-04T06:00:00Z"))
  schedule.calendars = [:]
  schedule.exceptions["c"] = ["20260202": true]
  #expect(schedule.departures(for: journey, now: now).count == 1)
}

@Test func expiredCalendarHasNoDepartures() {
  let journey = Journey(source: "Home", stationID: "s", serviceID: "r", walkingMinutes: 10)
  #expect(fixture().departures(for: journey, now: date("2027-02-03T05:30:00Z")).isEmpty)
}

@Test func rssCDATAAndDuplicates() throws {
  let item =
    "<item><guid>a</guid><pubDate>Tue, 08 Sep 2026 19:08:00 EDT</pubDate><category>affectedRoutes-2</category><title>Line 2 delay</title><description><![CDATA[<p>Train &amp; platform</p>]]></description><link>https://www.octranspo.com/en/alerts/</link></item>"
  let notices = try RSS.parse(Data("<rss><channel>\(item)\(item)</channel></rss>".utf8))
  #expect(notices.count == 1)
  #expect(notices[0].detail == "Train & platform")
  #expect(notices[0].url?.scheme == "https")
  #expect(notices[0].published == date("2026-09-08T23:08:00Z"))
  #expect(notices[0].affectedLines == ["2"])
  #expect(throws: (any Error).self) { try RSS.parse(Data("<html>Forbidden</html>".utf8)) }
}

@Test func noticesUseOttawaPublicationDay() {
  let now = date("2026-09-09T02:00:00Z")  // September 8, 22:00 in Ottawa.
  var notice = ServiceNotice(id: "a", title: "Line 2 delay", detail: "", url: nil)
  #expect(!notice.publishedToday(relativeTo: now))
  notice.published = date("2026-09-08T03:59:59Z")
  #expect(!notice.publishedToday(relativeTo: now))
  notice.published = date("2026-09-08T04:00:00Z")
  #expect(notice.publishedToday(relativeTo: now))
  notice.published = date("2026-09-09T01:00:00Z")
  #expect(notice.publishedToday(relativeTo: now))
  #expect(!notice.publishedToday(relativeTo: date("2026-09-09T04:00:00Z")))
  notice.published = date("2026-09-09T04:00:00Z")
  #expect(!notice.publishedToday(relativeTo: now))
}

@Test @MainActor func oldNoticesDoNotTriggerJourneyWarnings() {
  let model = AppModel()
  model.journeys = [Journey(source: "Home", stationID: "s", serviceID: "r", walkingMinutes: 10)]
  model.schedule = fixture()
  model.now = date("2026-09-09T02:00:00Z")
  model.notices = [
    ServiceNotice(
      id: "a", title: "Line 2 delay", detail: "", url: nil,
      published: date("2026-09-07T12:00:00Z"))
  ]
  #expect(model.todayNotices.isEmpty)
  #expect(!model.hasWarning)
  model.notices[0].published = date("2026-09-08T12:00:00Z")
  #expect(model.hasWarning)
  model.now = date("2026-09-09T04:00:00Z")
  #expect(!model.hasWarning)
  model.noticeError = "HTTP 403"
  #expect(model.hasWarning)
}

@Test func noticeLineBoundaries() {
  let journey = Journey(source: "Home", stationID: "s", serviceID: "r", walkingMinutes: 10)
  var notice = ServiceNotice(id: "a", title: "Line 20 delay", detail: "", url: nil)
  #expect(!notice.relevant(to: journey, in: fixture()))
  notice.title = "Line 2 service suspended"
  #expect(notice.relevant(to: journey, in: fixture()))
  notice.title = "Bayview elevator unavailable"
  #expect(notice.relevant(to: journey, in: fixture()))
}

@Test func scheduleParseFiltersRailAndNoPickup() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let files = [
    "routes.txt": "route_id,route_short_name,route_type\nr,2,0\nb,10,3\n",
    "stops.txt": "stop_id,stop_name,parent_station\np,Bayview Platform,s\ns,Bayview,\n",
    "trips.txt":
      "route_id,service_id,trip_id,direction_id,trip_headsign\nr,c,t,0,Limebank\nb,c,bus,0,Downtown\n",
    "stop_times.txt":
      "trip_id,departure_time,stop_id,pickup_type\nt,25:10:00,p,0\nt,25:20:00,p,1\nbus,10:00:00,p,0\n",
    "calendar_dates.txt": "service_id,date,exception_type\nc,20260908,1\n",
  ]
  for (name, content) in files {
    try content.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
  }
  let schedule = try FeedRepository.parse(directory: directory)
  #expect(schedule.stops.count == 1)
  #expect(schedule.stops[0].seconds == 90600)
  #expect(schedule.stations == [Station(id: "s", name: "Bayview")])
  #expect(schedule.services[0].line == "2")
}
