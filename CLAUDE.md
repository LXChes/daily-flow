# Daily Flow: rules for every session

Native SwiftUI iOS 17+ productivity app: day-to-day interactive tasks, upcoming events, rich Lock Screen
notifications, Home and Lock Screen widgets. Built in the cloud by GitHub Actions (no Mac) and sideloaded
for free (Phase 3, SideStore, is handled elsewhere: never do it here).

- Full design and behaviour spec: [`docs/design-brief.md`](docs/design-brief.md). Read it before any work.
- Visual spec for M3: the owner's "Daily Flow – Concepts" Design artifact (link in the brief). Open it from M3 only.

## Current milestone

**M1 Pipeline proof and M2 Core engine: done (cloud build green). M3 Main app UI: current.** Do one milestone at a time, then stop and
report to the owner in plain English. Never start the next milestone without the owner's go-ahead.

| # | Milestone | Scope |
|---|-----------|-------|
| M1 | Pipeline proof | `project.yml`, app + widget stub targets, `build-ipa.yml`, this file, `.claude/agents/` |
| M2 | Core engine | SwiftData models (task, notice day, settings), day rollover + leftovers triage, computed notice days, settings storage |
| M3 | Main app UI | Conveyor "Play the day", header, morning brief, leftovers sheet, notice banner, progress views, add sheet, view switcher, settings, dark + light themes |
| M4 | Notifications + widgets | Morning brief, urgent reminders (Complete / Snooze 30m / Tomorrow), Lock + Home widgets with App Intent ticking, crash-proof data fallback |
| M5 | Watch view | Skeleton watch (riskiest, last). Ship a simpler fallback first if the full one is not smooth |

## How to work (efficiency rules)
- Delegate big chunks only. Use the named subagents (model: sonnet) for large, self-contained pieces (M3 screens, M4 widgets, M5 watch). Do small edits yourself: a helper starts cold and costs more than it saves.
- Short briefs. The role files in .claude/agents/ already hold the rules. Brief a helper with the task, the files it owns and the acceptance check, not a copy of the rules.
- Audit diffs, not whole files. Spend review effort on what a compiler cannot catch: free-sideload safety, architecture, correctness of logic, design originality. Reject and rewrite below 9.5/10.
- CI is the compiler and the warning checker. It fails on any compile error or warning. Read the logs after every push and fix failures. Do not re-check by eye what CI already checks.
- Test pure logic. Date, rollover and notice-day logic is pure and injectable, with unit tests run in CI.
- See the UI, don't score it blind (M3, M5). Try having CI launch the app in the iOS simulator, take screenshots and upload them as an artifact, then download and look at them. Untested idea: if it is unreliable on the runner, say so and fall back to asking the owner to check on device.
- Runner: CI uses macos-26-intel. macos-latest (arm64) had capacity problems. Switch back only if it recovers.
- Explain simply. The owner is not a developer. After any jargon-heavy explanation, add a plain-English version.
- One milestone at a time. Confirm understanding first, do only the named milestone, then stop and report in plain English: what was pushed, where to check the build in the Actions tab, how to download the IPA.

## Roles

- **Lead Architect + Adversarial Reviewer:** Opus (High effort). Plans, delegates, audits every file.
- **Subagents** (`.claude/agents/`, model `sonnet`):
  - `ui-craft-builder`: SwiftUI views, custom gestures, spring animations, themes, typography.
  - `core-engine-builder`: SwiftData storage, smart day rollover, interactive `UNUserNotificationCenter` notifications, WidgetKit Home + Lock Screen widgets.
  - `ci-build-engineer`: deterministic XcodeGen `project.yml` and `.github/workflows/build-ipa.yml`.

## Quality gate (every file, every milestone)

The lead scores each subagent file out of 10 and rejects anything below **9.5**, forcing a rewrite, on:

1. **Visual originality and animation smoothness** (UI files).
2. **Zero compiler warnings and zero deprecated APIs** for the pinned Xcode and the iOS 17 deployment target.
3. **Free-sideload compatibility**: no entitlement or capability a free Apple ID cannot sign (no App Groups,
   push, iCloud, HealthKit, Siri, associated domains, etc.). Code must run safely when entitlements are stripped.

A milestone is done only when the gate passes **and** the GitHub Actions build is green.

## Design mandate (anti "vibe-coded")

- **Banned:** plain vertical checklists with default system-blue checkboxes, generic white rounded cards with
  heavy drop shadows, cluttered bottom tab bars, stiff linear transitions, walls of unstyled text, generic dark
  dashboard + neon accent + stat tiles, soft or warm pastels.
- **Required:** an original cohesive interaction paradigm, bespoke type hierarchy, intentional colour tokens,
  fluid spring physics (`interpolatingSpring`, `.snappy`, `matchedGeometryEffect`), crafted micro-interactions.
- Signed-off look: Chrome "Conveyor", dark = gothic liquid chrome, light = vintage. Metallic, iridescent, refined.

## Privacy (public repo)

- **No personal data anywhere:** no names, birthdays or dates of family or friends in code, comments, tests,
  sample data, docs or commit messages. Owner-specific dates are added on the phone via Settings (custom notice, "every year").
- Built-in notice days are **computed in code**: Christmas, NYE, New Year's Day, Halloween, Easter Sunday,
  UK Mother's Day (3 weeks before Easter), UK Father's Day (3rd Sunday of June).
- **No secrets or API keys.** No network services. All user data stays on the device (SwiftData / UserDefaults).
- Bundle IDs stay generic: `com.example.dailyflow` and `com.example.dailyflow.widget`.

## Free-sideload engineering

- Free Apple IDs strip App Group entitlements. Widgets must never crash without them: try the shared container,
  fall back to a timeline snapshot or standard `UserDefaults`, then to a safe placeholder.
- WidgetKit can't animate live: timelines + App Intents (iOS 17+) for ticking.
- Notification actions: Complete / Snooze 30m / Move to Tomorrow, all local.

## Build pipeline

- `project.yml` (XcodeGen) is the source of truth. The `.xcodeproj` is generated in CI and never committed.
- `.github/workflows/build-ipa.yml`:
  - Runs on `macos-26-intel` with **Xcode 26.6** and **XcodeGen 2.48.0**, both pinned. (`macos-latest`
    is arm64 and kept going unassigned because of GitHub capacity limits. Move back when that recovers.)
  - Archives unsigned (`CODE_SIGNING_ALLOWED=NO`) and zips `Payload/DailyFlow.app` into `DailyFlow.ipa`.
  - Uploads the IPA as an Actions artifact for every branch. Pushes to `main` also replace the rolling `latest` GitHub Release.
- No local Mac, so the CI run is the compiler. After pushing, read the run logs and fix any failure.
- Swift 6 language mode (full concurrency checking). `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`, so any warning fails the CI build.

## Git

- Push to `main` is allowed (solo repo). Never commit secrets, personal data or generated `.xcodeproj` / build output.
