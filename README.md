# Daily Flow

A native SwiftUI iOS 17+ productivity app for day-to-day tasks, upcoming events, Lock Screen
notifications and Home / Lock Screen widgets. It is built entirely in the cloud, with no Mac required.

## Build

The Xcode project is generated from `project.yml` with XcodeGen and archived unsigned by the
**Build IPA** GitHub Actions workflow (`.github/workflows/build-ipa.yml`) on every push.

## Download the IPA

- Latest build from `main`: **Releases -> latest** (`DailyFlow.ipa`).
- Any branch: open the run under **Actions -> Build IPA** and download the `DailyFlow-ipa-<run number>` artifact.

The IPA is unsigned and is intended for sideloading.

## Status

- M1 (pipeline proof): done.
- M2 (core engine): `Core/` is the `DailyFlowCore` framework (SwiftData models, day rollover and
  leftovers triage, computed notice days, settings, widget snapshot). `CoreTests/` holds its unit tests,
  which CI runs on an iOS simulator after packaging the IPA.
- M3 (main app UI): `App/` holds the SwiftUI app: the Conveyor "Play the day" belt, list view, leftovers
  triage, notice banner, four progress styles, add sheet, view switcher, settings, dark and light themes.
  CI also launches a demo build in the simulator and uploads screenshots of each screen.
