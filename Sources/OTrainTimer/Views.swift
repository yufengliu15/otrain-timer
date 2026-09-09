import AppKit
import SwiftUI

extension DepartureStatus {
  var color: Color {
    switch self {
    case .early: .secondary
    case .leave: .green
    case .tight: .yellow
    case .late: .red
    }
  }
  var symbol: String {
    switch self {
    case .early: "clock"
    case .leave: "figure.walk"
    case .tight: "exclamationmark.circle"
    case .late: "xmark.circle"
    }
  }
}

func ottawaTime(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.timeZone = TimeZone(identifier: "America/Toronto")
  formatter.dateFormat = "EEE h:mm a"
  return formatter.string(from: date)
}

struct MenuContent: View {
  @Bindable var model: AppModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Label("O-Train Timer", systemImage: "tram.fill").font(.headline)
        Spacer()
        if model.loadingSchedule || model.loadingNotices { ProgressView().controlSize(.small) }
      }
      Text("SCHEDULED · OTTAWA TIME").font(.caption).foregroundStyle(.secondary)
      if !model.journeys.isEmpty {
        Picker(
          "Menu bar journey",
          selection: Binding(
            get: { model.selectedJourneyID },
            set: { if let id = $0 { model.selectJourney(id) } }
          )
        ) {
          ForEach(model.journeys) { journey in
            Text(model.journeyLabel(journey)).tag(Optional(journey.id))
          }
        }
        Text("Train colour: \(model.selectedDepartureStatus?.title ?? "No scheduled departure")")
          .font(.caption).foregroundStyle(model.selectedDepartureStatus?.color ?? .secondary)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if model.journeys.isEmpty {
            ContentUnavailableView(
              "Add your first journey", systemImage: "figure.walk",
              description: Text(
                "Choose a source, station, direction, and walking time in Settings."))
          }
          if let error = model.persistenceError { Text(error).foregroundStyle(.orange) }
          if let error = model.scheduleError {
            Label("Schedule refresh failed", systemImage: "exclamationmark.triangle")
              .foregroundStyle(.orange)
            Text(error).font(.caption)
            if model.schedule != nil {
              Text("Cached schedule in use. It may be outdated.").font(.caption)
            }
          }
          ForEach(model.journeys) { journey in
            JourneyRow(journey: journey, model: model)
            Divider()
          }
          alerts
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxHeight: 480)
      Divider()
      HStack {
        Button("Settings…") {
          openWindow(id: "settings")
          NSApp.activate(ignoringOtherApps: true)
        }
        Button("Refresh") { Task { await model.refresh(force: true) } }
          .disabled(model.loadingSchedule || model.loadingNotices)
        Spacer()
        Button("Quit") { NSApp.terminate(nil) }
      }
      .controlSize(.small)
    }
    .padding(18)
    .frame(width: 410)
  }

  private var alerts: some View {
    let notices = model.todayNotices
    return VStack(alignment: .leading, spacing: 8) {
      Label("Today’s official service notices", systemImage: "exclamationmark.bubble").font(
        .headline)
      Text("Published today in Ottawa. Older ongoing issues are hidden.")
        .font(.caption2).foregroundStyle(.secondary)
      if let error = model.noticeError {
        Text("Service status unavailable").foregroundStyle(.orange)
        Text(error).font(.caption).foregroundStyle(.secondary)
        if !notices.isEmpty {
          Text("The notices below are from the last successful check.").font(.caption)
        }
      } else if model.noticeCheckedAt == nil {
        Text("Checking service notices…").foregroundStyle(.secondary)
      } else if notices.isEmpty {
        Text("No notices published today. This does not confirm normal service.").font(.caption)
      }
      let relevant = notices.filter { notice in
        guard let schedule = model.schedule else { return false }
        return model.journeys.contains { notice.relevant(to: $0, in: schedule) }
      }
      ForEach(relevant) { notice in NoticeRow(notice: notice) }
      if relevant.isEmpty && !notices.isEmpty {
        Text(
          "No notices matched your saved journeys. Check today’s other notices for network-wide issues."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      if notices.count > relevant.count {
        DisclosureGroup("All notices published today (\(notices.count))") {
          ForEach(notices) { notice in NoticeRow(notice: notice).padding(.vertical, 5) }
        }
      }
      if let checked = model.noticeCheckedAt {
        Text("Last checked: \(ottawaTime(checked))").font(.caption2).foregroundStyle(.secondary)
      }
      Link(
        "Open OC Transpo service alerts ↗",
        destination: URL(string: "https://www.octranspo.com/en/alerts/")!
      )
      .font(.caption)
    }
  }
}

struct JourneyRow: View {
  let journey: Journey
  var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let schedule = model.schedule {
        let station = schedule.stations.first { $0.id == journey.stationID }
        let service = schedule.services.first { $0.id == journey.serviceID }
        HStack {
          Text("\(journey.source) → \(station?.name ?? "Unknown station")").font(.headline)
          if model.selectedJourneyID == journey.id {
            Image(systemName: "menubar.rectangle").help(
              "This journey controls the menu bar train colour")
          }
        }
        Text(
          "\(service?.label ?? "Direction unavailable") · \(journey.walkingMinutes.formatted()) min walk"
        )
        .font(.caption).foregroundStyle(.secondary)
        if station == nil || service == nil {
          Text("The schedule changed. Edit this journey in Settings.").foregroundStyle(.orange)
        } else {
          let departures = schedule.departures(for: journey, now: model.now)
          if let next = departures.first {
            let seconds = next.timeIntervalSince(model.now)
            let status = DepartureStatus.evaluate(
              secondsUntilDeparture: seconds, walkingMinutes: journey.walkingMinutes)
            Label(status.title, systemImage: status.symbol)
              .font(.title3.weight(.semibold)).foregroundStyle(status.color)
            Text("Departs \(ottawaTime(next)) · in \(Int(ceil(seconds / 60))) min")
              .monospacedDigit()
            if status == .early {
              Text("Leave in \(Int(ceil((seconds - journey.walkingMinutes * 60 - 120) / 60))) min")
                .font(.caption)
            }
            if let catchable = departures.first(where: {
              $0.timeIntervalSince(model.now) >= journey.walkingMinutes * 60
            }),
              catchable != next
            {
              Text("Next catchable: \(ottawaTime(catchable))").font(.caption)
            }
          } else {
            Text("No scheduled departures in the next two days.").foregroundStyle(.secondary)
            Text("Service may be finished, or the schedule may have expired.").font(.caption)
          }
        }
        if !model.relevantNotices(for: journey).isEmpty {
          Label(
            "Service notice — schedule may be unreliable",
            systemImage: "exclamationmark.triangle.fill"
          )
          .font(.caption).foregroundStyle(.orange)
        }
      } else {
        Text(journey.source).font(.headline)
        Text("Schedule unavailable").foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct NoticeRow: View {
  let notice: ServiceNotice
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(notice.title).font(.subheadline.weight(.semibold))
      Text(notice.detail).font(.caption).textSelection(.enabled)
      if let published = notice.published {
        Text("Published: \(ottawaTime(published))").font(.caption2).foregroundStyle(.secondary)
      }
      if let url = notice.url { Link("Read official notice ↗", destination: url).font(.caption) }
    }
  }
}

struct SettingsContent: View {
  @Bindable var model: AppModel
  @State private var editingID: UUID?
  @State private var source = ""
  @State private var stationID = ""
  @State private var serviceID = ""
  @State private var walkingMinutes = 10.0
  @State private var pendingDelete: Journey?

  private var availableServices: [RailService] {
    model.schedule?.services.filter { $0.stationIDs.contains(stationID) } ?? []
  }
  private var valid: Bool {
    !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && availableServices.contains { $0.id == serviceID }
      && walkingMinutes.isFinite && walkingMinutes > 0 && walkingMinutes <= 240
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Your journeys").font(.largeTitle.bold())
      Text(
        "Walking time must include the walk to the platform. All departure times use Ottawa time."
      )
      .foregroundStyle(.secondary)
      List {
        ForEach(model.journeys) { journey in
          HStack {
            VStack(alignment: .leading) {
              Text(journey.source).font(.headline)
              Text(
                model.schedule?.stations.first { $0.id == journey.stationID }?.name
                  ?? journey.stationID)
              Text(
                "\(model.schedule?.services.first { $0.id == journey.serviceID }?.label ?? journey.serviceID) · \(journey.walkingMinutes.formatted()) min"
              )
              .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Edit") {
              editingID = journey.id
              source = journey.source
              stationID = journey.stationID
              serviceID = journey.serviceID
              walkingMinutes = journey.walkingMinutes
            }
            Button("Delete", role: .destructive) { pendingDelete = journey }
          }
        }
      }
      .frame(minHeight: 110)
      Form {
        TextField("Source label", text: $source, prompt: Text("Home, Office…"))
        Picker("Station", selection: $stationID) {
          Text("Choose a station").tag("")
          ForEach(model.schedule?.stations ?? []) { station in Text(station.name).tag(station.id) }
        }
        Picker("Line and direction", selection: $serviceID) {
          Text("Choose a direction").tag("")
          ForEach(availableServices) { service in Text(service.label).tag(service.id) }
        }
        TextField("Walking minutes (0–240)", value: $walkingMinutes, format: .number)
        Text(
          "Leave-now buffer: 2 minutes. Yellow begins when less than the full walking time remains."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      .onChange(of: stationID) { _, _ in
        if !availableServices.contains(where: { $0.id == serviceID }) { serviceID = "" }
      }
      HStack {
        Button(editingID == nil ? "Add journey" : "Save journey") {
          model.save(
            Journey(
              id: editingID ?? UUID(),
              source: source.trimmingCharacters(in: .whitespacesAndNewlines),
              stationID: stationID, serviceID: serviceID, walkingMinutes: walkingMinutes))
          editingID = nil
          source = ""
        }
        .buttonStyle(.borderedProminent).disabled(!valid)
        if editingID != nil {
          Button("Cancel edit") {
            editingID = nil
            source = ""
          }
        }
        Spacer()
        if model.loadingSchedule { ProgressView().controlSize(.small) }
        Button("Refresh data") { Task { await model.refresh(force: true) } }
          .disabled(model.loadingSchedule || model.loadingNotices)
      }
      if let error = model.scheduleError { Text(error).font(.caption).foregroundStyle(.orange) }
      if let error = model.persistenceError { Text(error).font(.caption).foregroundStyle(.orange) }
      if let schedule = model.schedule {
        Text("Schedule downloaded: \(ottawaTime(schedule.fetchedAt))").font(.caption)
          .foregroundStyle(.secondary)
      } else {
        Text("Download the schedule to select a station.").font(.caption)
      }
    }
    .padding(24)
    .frame(minWidth: 560, minHeight: 540)
    .confirmationDialog(
      "Delete this journey?",
      isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    ) {
      Button("Delete journey", role: .destructive) {
        if let journey = pendingDelete {
          model.delete(journey)
          if editingID == journey.id {
            editingID = nil
            source = ""
          }
        }
        pendingDelete = nil
      }
    }
  }
}
