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

Milestone M1 (pipeline proof): a placeholder app and widget that prove the build and packaging pipeline.
