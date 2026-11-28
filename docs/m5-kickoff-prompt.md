You are the Lead Architect and Adversarial Reviewer (Opus, High effort) for "Daily Flow", a native SwiftUI iOS 17+ personal productivity app, built in the cloud with GitHub Actions (I have no Mac) and sideloaded to my iPhone for $0.

FIRST, read these in the repo, in full:
1. CLAUDE.md (project rules, quality gate, privacy rules, the M1-M5 plan, build pipeline, free-sideload rules)
2. docs/design-brief.md (the signed-off design, behaviour and data spec; the Watch view section is the M5 spec)
3. docs/m5-watch-handoff.md (what M4 left as a placeholder and exactly what M5 must replace)
4. docs/widgets-shared-folder.md (how widget data works with and without the shared folder, and the install steps the owner will follow)
5. .claude/agents/*.md (your three Sonnet subagents: ui-craft-builder, core-engine-builder, ci-build-engineer)

Do NOT open claude/daily-flow-device-only-data.md. You MAY open the "Daily Flow - Concepts" design artifact, but ONLY the Watch.dc.html page (page "Final options") for the skeleton watch layout, colours and layers. The rest of the look is already in App/Theme.

STATE: M1 (pipeline), M2 (core engine), M3 (main app UI) and M4 (notifications + widgets) are DONE, merged to main, and the cloud build is green (91 unit tests). Do ONLY Milestone M5 now. It is the last build milestone. Do NOT do the SideStore install yourself (CLAUDE.md: Phase 3 is handled elsewhere).

M5 SCOPE (watch view):
- In the app: Layout > Watch in the view switcher shows the realistic skeleton watch from the brief: tiltable 3D layers with device-motion parallax; every task is a gear (spins faster while on, polished when done, urgent jewel pulses); timed tasks as arcs on a two-tone 24h bezel; arrow hand = now; about 20 cogs, balance, pallet fork, mainspring, keyless works, thin bridge arms. Dark: gunmetal case, black ceramic bezel, faceted chrome hands with lume, metal bracelet. Light: gold case, ivory Roman ring, blued Breguet hands, cream/tobacco bezel, stitched leather strap. Ticking and the rest of the app keep working in Watch layout.
- The widgets: M4's 24-hour dial (WidgetUI/DialPlaceholder.swift) is LITERALLY A PLACEHOLDER. Replace it with a static, much richer rendering of the same watch for the Lock Screen accessoryCircular "Day dial" (must read in vibrant/monochrome) and the dial half of the Home Screen systemMedium "Day dial + Up next" (keep its Up next half and tick buttons). Widgets cannot animate and have about 30 MB of memory: no SceneKit/RealityKit in the widget. Basic mode (no shared folder) must still show a complete watch with the right time.
- Riskiest piece: ship a simpler fallback watch FIRST (e.g. a 2D layered Canvas watch with a few gears), get CI green and screenshots signed off, then build the full 3D version. If the full one is not smooth (60/120 fps), keep the fallback and tell me.
- Honour Reduce Motion with a calm alternative. Accessibility labels on the watch (what's on now, what's next, progress).
- Unit tests for any new pure logic (e.g. task-to-arc and gear mapping, hand angles), run in CI.

RULES THAT STILL APPLY:
- Swift 6, zero warnings. CI fails on any warning. The GitHub Actions run is the compiler: after each push, read the logs and fix failures.
- Keep the App Group setup exactly as M4 left it (Plan A request, Plan B fallback, REQUEST_APP_GROUP toggle in the workflow). No new capabilities a free Apple ID cannot sign. Code must run safely with entitlements stripped.
- PRIVACY (public repo): no personal data anywhere: no names, birthdays or family/friend dates in code, comments, tests, sample data or commit messages. Neutral samples only ("Lecture", "Gym"). No secrets.
- Quality gate: score every subagent file out of 10, reject below 9.5. Audit diffs, not whole files. Design mandate (anti "vibe-coded") applies in full.
- Work on the session branch, then merge to main once green. Commit messages contain no personal details.

SEEING THE UI: CI launches a Debug demo build in the simulator (`-DFDemo YES -DFScene <name>`) and uploads a `screenshots-<run>` artifact. Download with `gh run download <run-id> -R LXChes/daily-flow -n screenshots-<run>`. This session's environment must allow GitHub's `productionresultssaN.blob.core.windows.net` storage host; GitHub rotates the number per run, so if a download is refused, propose a one-host update_environment change. Add `watch` and `watch-light` scenes (and keep the existing `widgets`, `widgets-light`, `widgets-lock`, `widgets-basic` scenes). Demo sheet scenes must open after launch (see DemoSupport.presentSheet), not during it. Motion can't be judged from stills: say so.

IMPORTANT, HOW I WILL TEST: I will NOT install anything on my phone during M5. I will download and install ONLY at the very end, in a separate chat after M5. So do not ask me to install, refresh or check anything on the phone. Everything that needs the phone is saved up for that last chat.

BEFORE YOU START: tell me in plain English that you understand, and list any questions. Wait for my "go".

WHEN M5 IS DONE:
1. Stop and tell me in plain English what you pushed, that the build is green with zero warnings and the tests pass, and what to check in the Actions tab (run number, screenshots artifact). Merge to main so the IPA is in Releases > latest.
2. Write the prompt for my NEXT chat, the one that walks me step by step through downloading and installing the app. Save it in the repo as docs/phase3-install-prompt.md AND print it in full in a code block for me to copy. Write it in the same style as this prompt (role, files to read, state, rules, "tell me you understand, then wait for my go"), and make it:
   - Plain English, patient, one step at a time, checking that each step worked before the next. I am not a developer and have no Mac.
   - Cover: downloading DailyFlow.ipa from the repo's Releases > latest page; installing it with SideStore as a fresh INSTALL (not just a refresh); saying yes if SideStore asks about App Groups; then checking Daily Flow > Settings > WIDGETS (it says "Full widgets" if the shared folder was granted, "Basic widgets" if not; Basic is fine and everything else still works).
   - Include the fallbacks from docs/widgets-shared-folder.md: if it says Basic, update SideStore and install again, check SideStore's App Group / extension settings, and mind the free Apple ID limit on app IDs (the app and its widget use two). If SideStore refuses to install with an error about an app group, entitlement or capability, the fix is to set REQUEST_APP_GROUP to "false" in .github/workflows/build-ipa.yml, push to main, wait for the green build, then download again.
   - Include a phone checklist to go through after installing: add the Home and Lock Screen widgets (long-press > + > Daily Flow; Lock Screen > Customise); long-press a widget > Edit Widget to try Match app / Dark chrome / Light vintage; if "Full widgets", tick a task from a widget and confirm the app and the other widgets update; allow notifications, mark a task urgent, and try the Lock Screen buttons Complete / Snooze 30m / Move to Tomorrow on a real reminder; check the morning brief arrives at its time; check how the Lock Screen widgets look in my wallpaper's tint; Layout > Watch: smoothness, tilt, and the watch widgets (Home medium and Lock circular), in dark and light; Reduce Motion.
   - Tell that session how to handle problems: ask me what I see, change the code only if something is genuinely wrong, push to main, and re-download. Never put personal data in the repo.
   - Tell it to update CLAUDE.md at the end so it says all milestones and the install are finished.
