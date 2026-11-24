# Daily Flow: design brief (design signed off; Phase 2 plan agreed)

The design is confirmed. The Phase 2 build follows the milestone plan below.

Design canvas (for M3): the Design artifact in my Claude artifacts, probably titled "Daily Flow – Concepts" (https://claude.ai/artifact/So3qXyiiAaaQGTsd2f9qSv). Do NOT open it in M1.
- Page "Final design" is the spec to build: FinalApp.dc.html (app), FinalLock.dc.html (Lock Screen), FinalHome.dc.html (Home Screen).
- Page "Final options": Watch.dc.html (skeleton watch), Settings.dc.html (settings and notice days). AddTask.dc.html and ViewMenu.dc.html (on the Rounds page) are the shared add sheet and view switcher.
- These are HTML/SVG prototypes: read them for layout, colours, copy and interaction, then rebuild natively.

## AGREED PHASE 2 PLAN
1. Pipeline first. Build a bare-bones app plus widget stub and prove the GitHub Actions build produces a working DailyFlow.ipa BEFORE writing the real app.
2. Milestones, one at a time, stop and report after each:
   - M1 Pipeline proof: XcodeGen project.yml, app target + widget extension target (stub), .github/workflows/build-ipa.yml, CLAUDE.md, three subagents in .claude/agents/.
   - M2 Core engine: SwiftData models (task, notice day, settings), day rollover and leftovers triage logic, computed notice days, settings storage.
   - M3 Main app UI: Conveyor "Play the day", header, morning brief card, leftovers sheet, notice banner, progress views, add sheet, view switcher, settings, dark and light themes.
   - M4 Notifications and widgets: morning brief, urgent reminders with Complete / Snooze 30m / Tomorrow; Lock Screen and Home Screen widgets with App Intent ticking; crash-proof widget data fallback (no App Groups on free sideload).
   - M5 Watch view: skeleton watch (last, riskiest). Ship a simpler fallback watch first if the full one is not smooth.
3. Quality gate as in the project instructions; the cloud build must also be green.
4. Models: lead and reviewer = Opus 5.5 High in Claude Code; subagents = Sonnet 5.5.
5. Personal data stays OUT of the public repo. Fixed-date notice days (Christmas, NYE, New Year's Day, Halloween, Easter, UK Mother's Day, UK Father's Day) are computed in code. Family birthdays and any other personal dates are NOT in the repo, code, comments, tests, sample data or commit messages. The app must let the owner add them on the phone via Settings (custom notice, "every year").

## Signed-off design
App = Chrome "Conveyor" (option 1), dark (gothic liquid chrome) and light (vintage) themes.
- Header: chrome "DAILY" wordmark, date, buttons: view switcher (sliders), settings (cog), add (+).
- Morning brief card: "Left over from yesterday" opens a sheet to Keep today / Tomorrow / Bin each leftover.
- Notice banner (iridescent) only on notice days; can be switched off.
- Progress: Wave (raised bars showing busy times, done tasks lit) / Ring / Bar / Number.
- Play the day: big chrome clock, now card with tick, tilted 3D conveyor belt of timed blocks whose width = duration; drag to scrub or press play (smooth); anytime tasks as pills; full list with tick and urgent bell.
- View switcher: Layout (Play the day / List / Watch), Categories (Simple / Sorted), Theme (Dark / Light), Progress, Notices on/off, Preview (Normal / Next event / The one after).
- Watch view: realistic skeleton watch, tiltable 3D layers. Every task = a gear (spins faster while on, polished when done, urgent jewel pulses); timed tasks as arcs on a two-tone 24h bezel; arrow hand = now; about 20 cogs, balance, pallet fork, mainspring, keyless works, thin bridge arms. Dark: gunmetal case, black ceramic bezel, faceted chrome hands with lume, metal bracelet. Light: gold case, ivory Roman ring, blued Breguet hands, cream/tobacco bezel, stitched leather strap.

Lock Screen (option 3): accessoryCircular mini 24h watch face (task arcs + hands + now arrow), accessoryCircular % ring, accessoryRectangular Up next with tick (App Intent). On a notice day the inline line becomes e.g. "It's Christmas Day". Notifications: morning brief; urgent reminders with actions Complete / Snooze 30m / Tomorrow.

Home Screen: medium Wave ("3 of 8 done", busy-time bars, now line); medium Watch + Up next (2 tickable tasks, "2/8 done"); small % ring; small done ring. Each widget's style is configurable: Match app / Dark chrome / Light vintage (AppIntentConfiguration). Ticking updates all widgets.

## Behaviour and data
- Add sheet: name (auto-categorised by keywords: Uni, Health, Career, Errands, Home, Social, Other; tap to override), day (Today, Tomorrow, next 5 days, or any date), optional time, optional duration (15m to 3h quick picks, plus/minus 15m), urgent toggle. Future-day tasks appear on their day.
- Tick to complete; urgent flag triggers notifications (lead time and untimed times set in Settings).
- Settings: notices on/off; list of notice days with toggles; add custom notice (name, date, every year); morning brief on/off + time; leftovers triage on/off; urgent reminder timing; auto-sort on/off; widget style; haptic tick; tick sound.
- Built-in notice days (computed in code): Christmas 25/12, NYE 31/12, New Year's Day 1/1, UK Mother's Day (3 weeks before Easter), Easter Sunday (computed), UK Father's Day (3rd Sunday of June), Halloween 31/10.
- All data local only (SwiftData / UserDefaults).

## Taste
- Likes: playful and elegant, complex, cool, metallic, glowing iridescent gradients, refined type.
- Dislikes: generic dark dashboard + neon accent + stat tiles + bottom tab bar; soft or warm pastels.

## Notes for the build
- WidgetKit can't animate live: the watch widget refreshes on a timeline; ticking via App Intents (iOS 17+).
- The prototype watch is layered SVG; natively use SceneKit/RealityKit or a Metal-shaded SwiftUI Canvas with device-motion tilt parallax.
- Free-sideload constraints (no App Groups): widget data fallback as described above.
- Repo must be PUBLIC (free macOS build minutes). Zero secrets or personal data in it.
