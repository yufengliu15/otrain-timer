import Foundation

/// Streaming rows from a CSV string avoids retaining the full stop_times table.
enum CSV {
  static func read(_ text: String, row: ([String: String]) -> Void) {
    var headers: [String]?
    var fields: [String] = []
    var field = ""
    var quoted = false
    var iterator = text.makeIterator()
    var current = iterator.next()
    func emit() {
      fields.append(field)
      field = ""
      if let headers {
        var record: [String: String] = [:]
        for (key, value) in zip(headers, fields) { record[key] = value }
        if fields.contains(where: { !$0.isEmpty }) { row(record) }
      } else {
        headers = fields.map { $0.replacingOccurrences(of: "\u{feff}", with: "") }
      }
      fields = []
    }
    while let character = current {
      current = iterator.next()
      if character == "\"" {
        if quoted && current == "\"" {
          field.append("\"")
          current = iterator.next()
        } else {
          quoted.toggle()
        }
      } else if character == "," && !quoted {
        fields.append(field)
        field = ""
      } else if (character == "\n" || character == "\r\n" || character == "\r") && !quoted {
        emit()
      } else {
        field.append(character)
      }
    }
    if !field.isEmpty || !fields.isEmpty { emit() }
  }
}

enum FeedError: LocalizedError {
  case http(Int)
  case invalidSchedule, extraction, invalidRSS
  var errorDescription: String? {
    switch self {
    case .http(let status): "The server returned HTTP \(status)."
    case .invalidSchedule: "The schedule contains no usable rail departures."
    case .extraction: "The schedule archive could not be opened."
    case .invalidRSS: "The server did not return a valid RSS feed."
    }
  }
}

actor FeedRepository {
  static let scheduleURL = URL(
    string: "https://oct-gtfs-emasagcnfmcgeham.z01.azurefd.net/public-access/GTFSExport.zip")!
  static let alertsURL = URL(string: "https://www.octranspo.com/feeds/updates-en/")!
  private let cacheURL: URL

  init() {
    let directory = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("OTrainTimer", isDirectory: true)
    cacheURL = directory.appendingPathComponent("schedule.json")
  }

  func cachedSchedule() -> Schedule? {
    guard let data = try? Data(contentsOf: cacheURL) else { return nil }
    return try? JSONDecoder().decode(Schedule.self, from: data)
  }

  func download(_ url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.timeoutInterval = 60
    request.setValue(
      "OTrainTimer/1.0 (macOS; personal transit schedule)", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw FeedError.http(0) }
    guard (200..<300).contains(http.statusCode) else { throw FeedError.http(http.statusCode) }
    return data
  }

  func refreshSchedule() async throws -> Schedule {
    let data = try await download(Self.scheduleURL)
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    let archive = temp.appendingPathComponent("schedule.zip")
    let extracted = temp.appendingPathComponent("gtfs")
    try data.write(to: archive)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-x", "-k", archive.path, extracted.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw FeedError.extraction }
    let schedule = try Self.parse(directory: extracted)
    try FileManager.default.createDirectory(
      at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(schedule).write(to: cacheURL, options: .atomic)
    return schedule
  }

  static func parse(directory: URL) throws -> Schedule {
    func read(_ filename: String, optional: Bool = false, row: ([String: String]) -> Void) throws {
      let url = directory.appendingPathComponent(filename)
      if optional && !FileManager.default.fileExists(atPath: url.path) { return }
      CSV.read(try String(contentsOf: url, encoding: .utf8), row: row)
    }
    var routes: [String: String] = [:]
    try read("routes.txt") { r in
      if let id = r["route_id"], let type = r["route_type"], ["0", "1", "2", "12"].contains(type) {
        routes[id] = r["route_short_name"] ?? id
      }
    }
    var names: [String: String] = [:]
    var parents: [String: String] = [:]
    try read("stops.txt") { r in
      guard let id = r["stop_id"] else { return }
      names[id] = r["stop_name"] ?? id
      if let parent = r["parent_station"], !parent.isEmpty { parents[id] = parent }
    }
    var trips: [String: (service: String, calendar: String)] = [:]
    var services: [String: RailService] = [:]
    try read("trips.txt") { r in
      guard let route = r["route_id"], let line = routes[route],
        let trip = r["trip_id"], let calendar = r["service_id"]
      else { return }
      let headsign =
        r["trip_headsign"].flatMap { $0.isEmpty ? nil : $0 }
        ?? "Direction \(r["direction_id"] ?? "?")"
      // Do not save versioned route IDs: they can change with each schedule export.
      let service = [line, r["direction_id"] ?? "", headsign].joined(separator: "|")
      services[service] = RailService(id: service, line: line, headsign: headsign, stationIDs: [])
      trips[trip] = (service, calendar)
    }
    var stops: [ScheduledStop] = []
    var stationIDs: Set<String> = []
    try read("stop_times.txt") { r in
      guard let tripID = r["trip_id"], let trip = trips[tripID], let stop = r["stop_id"],
        r["pickup_type"] != "1", let time = r["departure_time"]
      else { return }
      let parts = time.split(separator: ":").compactMap { Int($0) }
      guard parts.count == 3, parts[0] >= 0, (0..<60).contains(parts[1]),
        (0..<60).contains(parts[2])
      else { return }
      let station = parents[stop] ?? stop
      stationIDs.insert(station)
      services[trip.service]?.stationIDs.insert(station)
      stops.append(
        ScheduledStop(
          stationID: station, serviceID: trip.service, calendarID: trip.calendar,
          seconds: parts[0] * 3600 + parts[1] * 60 + parts[2]))
    }
    var calendars: [String: ServiceCalendar] = [:]
    try read("calendar.txt", optional: true) { r in
      guard let id = r["service_id"], let start = r["start_date"], let end = r["end_date"] else {
        return
      }
      calendars[id] = ServiceCalendar(
        start: start, end: end,
        weekdays: ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"].map
        { r[$0] == "1" })
    }
    var exceptions: [String: [String: Bool]] = [:]
    try read("calendar_dates.txt", optional: true) { r in
      guard let id = r["service_id"], let date = r["date"], let type = r["exception_type"],
        ["1", "2"].contains(type)
      else { return }
      exceptions[id, default: [:]][date] = type == "1"
    }
    guard !stops.isEmpty, !calendars.isEmpty || !exceptions.isEmpty else {
      throw FeedError.invalidSchedule
    }
    return Schedule(
      fetchedAt: Date(),
      stations: stationIDs.map { Station(id: $0, name: names[$0] ?? $0) }.sorted {
        $0.name < $1.name
      },
      services: services.values.filter { !$0.stationIDs.isEmpty }.sorted { $0.label < $1.label },
      stops: stops, calendars: calendars, exceptions: exceptions)
  }

  func refreshNotices() async throws -> [ServiceNotice] {
    try RSS.parse(await download(Self.alertsURL))
  }
}
