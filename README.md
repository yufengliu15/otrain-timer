# O-Train Timer

A native macOS menu bar app for **scheduled** O-Train departures and official service notices. Requires macOS 14 or later. No API key, account, location permission, or third-party Swift dependencies.

## Build and open

Install Xcode Command Line Tools with `xcode-select --install` if needed. Use Swift 6 or later.

```sh
./scripts/build-app.sh
open "dist/O-Train Timer.app"
```

To create a disk image in the repository root:

```sh
./scripts/build-dmg.sh
```

Open `O-Train Timer.dmg` and drag the app to the Applications shortcut. The generated disk image is excluded from Git.

Click the tram icon in the menu bar. Open **Settings**, then add a source label, station, line and direction, and walking time. Include the walk to the platform. You can add, edit, and delete any number of journeys. Decimal walking minutes are supported.

The app does not send macOS notifications. It does not start automatically at login. To enable that, copy the app to Applications and add it under macOS **System Settings → General → Login Items**.

## Departure states

`t` is seconds until scheduled departure; `x` is walking time in seconds.

| Condition | Colour | Status |
| --- | --- | --- |
| `t > x + 120` | Neutral | Too early; shows when to leave |
| `x ≤ t ≤ x + 120` | Green | Leave now |
| `x − 60 ≤ t < x` | Yellow | Tight timing; you may miss it |
| `t < x − 60` | Red | Too late for this train |

The menu also shows the next catchable departure when the first train leaves before the full walking time permits. All displayed clock times use Ottawa time, independent of the Mac's time zone.

## Data and refresh policy

- **Schedule:** [OC Transpo GTFS ZIP](https://oct-gtfs-emasagcnfmcgeham.z01.azurefd.net/public-access/GTFSExport.zip). Refreshes after 24 hours; failed refreshes retry after 15 minutes. Cached data remains available offline.
- **Service notices:** [Official English RSS](https://www.octranspo.com/feeds/updates-en/). Checks every two minutes while awake. Rechecks after wake. A manual refresh checks both sources.
- **Display:** Recalculates every 15 seconds locally. This does not fetch the schedule every 15 seconds.
- No new polling starts during sleep. An in-flight request may finish or time out. Normal timers resume after wake.
- Schedule parsing handles rail types, direction and headsign, parent stations, boarding restrictions, calendar exceptions, times beyond 24:00, and Ottawa daylight-saving time.

### Important limits

These are **not live arrival predictions**. The app cannot detect a stuck train itself. It shows notices only after OC Transpo publishes them. It does not adjust departure times from notice text.

Notice matching uses affected-route RSS categories, line names, station names, and general O-Train references. Broad O-Train notices can appear for multiple lines. Matching can miss ambiguous notices, so the menu also exposes all notices published today and the official alerts page. Notices can describe planned work, station facilities, or restored service; a notice is not proof of an active train delay. The menu and journey warnings include only notices with a publication date on the current Ottawa calendar day. Older, future-day, and undated notices are hidden. This can hide ongoing disruptions announced earlier. The filter updates at midnight on the next display tick, or after wake.

Select a saved pair with the **Menu bar journey** picker at the top of the menu. The train icon always remains a train. Its colour shows the selected pair's next scheduled departure status: neutral, green, yellow, or red, using the table above. It is also neutral when no departure or schedule is available. The menu explains the current state in text. Service notices and download errors appear inside the menu; they do not change the icon.

The selected pair persists after restart. The first pair is selected automatically on initial setup. Deleting the selected pair selects the first remaining pair. The app icon in Finder and the DMG is a large red O.

Feed access can fail even when a browser works. The app shows **Service status unavailable** and labels retained notices as old. An empty feed does not establish normal service.

If a schedule export changes a saved station or direction identifier, edit that journey in Settings. If no applicable service exists in the next two days, the app reports that instead of inventing a departure.

## Local storage and privacy

- Journeys: macOS UserDefaults, bundle ID `ca.local.otrain-timer`.
- Schedule cache: `~/Library/Application Support/OTrainTimer/schedule.json`.
- Source locations are labels only. The app does not collect coordinates or addresses.
- Network requests go to the public schedule and RSS endpoints, including their redirects. Opening a notice uses the default browser.
- The app never reads `.env` and does not use `API_KEY`.

The build script makes a locally ad-hoc-signed `.app`. It is not notarized for public distribution.

## Development checks

```sh
# Format
swift format format --in-place --recursive Sources Tests Package.swift scripts/generate-icon.swift

# Strict format lint, build, and unit tests
./scripts/check.sh

# Optional public-feed integration test; downloads data and populates the schedule cache
OTRAIN_LIVE_TESTS=1 swift test --filter livePublicFeeds
```

Manual checks: add two journeys; edit and delete one; check direction choices; disconnect the network and refresh; restore the network; sleep and wake the Mac; verify the selected journey's train colour and the service-notice source links. Automated tests do not replace these UI and sleep checks.
