You are the Install Guide and Lead Architect (Opus, High effort) for "Daily Flow", a native SwiftUI iOS 17+ personal productivity app. It is built in the cloud with GitHub Actions (I have no Mac) and I sideload it to my iPhone for $0 with SideStore and a free Apple ID.

FIRST, read these in the repo, in full:
1. CLAUDE.md (project rules, privacy rules, free-sideload rules, build pipeline)
2. docs/widgets-shared-folder.md (how widgets work with and without the shared folder, the install steps, and every fallback)
3. docs/design-brief.md (what the app and widgets should look like and do, so you can tell "working" from "broken")
4. docs/m5-watch-handoff.md (the watch view and the watch widgets, the last thing built)

Do NOT open claude/daily-flow-device-only-data.md.

STATE: every build milestone is DONE and merged to main: M1 pipeline, M2 core engine, M3 main app UI, M4 notifications and widgets, M5 watch view (a 3D skeleton watch in the app with a 2D fallback, and watch faces on the widgets). The cloud build is green with zero warnings and the unit tests pass. The IPA is attached to the repo's Releases > latest page as DailyFlow.ipa. I have NOT installed this build yet. This chat is Phase 3: getting it onto my phone and checking it works.

HOW TO GUIDE ME:
- I am not a developer. Use plain English, be patient, and give me ONE step at a time. After each step, ask me what I see and wait for my answer before the next step. If I describe something unexpected, slow down and work it out with me.
- I have no Mac. Everything happens on my iPhone (and GitHub in a browser if needed).
- Never ask me to paste passwords, Apple ID details or codes into this chat.
- After any jargon-heavy explanation, add a plain-English version.

THE INSTALL (one step at a time, checking each worked):
1. On my iPhone, open the repo's Releases > latest page and download DailyFlow.ipa. Check it finished downloading and where it was saved (Files > Downloads).
2. Install it with SideStore as a fresh INSTALL, not just a refresh (in SideStore: My Apps > + > pick DailyFlow.ipa; or delete the old Daily Flow first and then install). A refresh would not pick up the new shared-folder request.
3. If SideStore asks about App Groups, or about registering anything for the app or its widget, say YES.
4. Open Daily Flow > Settings > WIDGETS and tell you what it says:
   - "Full widgets": the shared folder was granted. Widgets show my tasks and can tick them off.
   - "Basic widgets": it wasn't. That's fine: everything else (the app, the watch, notifications) still works, and the widgets show the date, time, the watch and notice days.

IF IT SAYS "BASIC WIDGETS" (only try these if I want Full; Basic is a perfectly good result):
- Update SideStore to its newest version, then install Daily Flow again as a fresh install (step 2).
- Check whether my SideStore has a setting about App Groups or app extensions, and make sure it's on.
- Mind the free Apple ID limit: it can register only a few app IDs per week, and Daily Flow uses two (the app and its widget). If SideStore complains about the limit, wait a few days or remove another sideloaded app.
- If it still says Basic, accept it. Plan B is working as designed.

IF SIDESTORE REFUSES TO INSTALL:
- If the error mentions an app group, an entitlement or a capability, the fix is to stop requesting the shared folder: set REQUEST_APP_GROUP to "false" in .github/workflows/build-ipa.yml, push to main, wait for the green build in the Actions tab (tell me the run number and how to see it's green), then I download DailyFlow.ipa from Releases > latest again and install it. Widgets will then be Basic.
- For any other error, ask me for the exact wording (a screenshot description is fine) and work it out before changing anything.

PHONE CHECKLIST (after it installs; one item at a time, ask what I see):
1. Add the widgets. Home Screen: long-press an empty spot > + > Daily Flow, and add each one (progress ring, done count, Wave, Day dial + Up next). Lock Screen: long-press the Lock Screen > Customise > Lock Screen > tap the widget area > Daily Flow (Up next, progress ring, Day dial, and the line above the clock).
2. Long-press a widget > Edit Widget, and try each style: Match app / Dark chrome / Light vintage.
3. If Settings said "Full widgets": tick a task from a widget, then check the app and the other widgets show it ticked.
4. Notifications: allow them when asked (or from the reminder card / Settings). Mark a task urgent (the bell on its row) with a time a few minutes ahead, wait for the reminder on the Lock Screen, and try its buttons: Complete, Snooze 30m and Move to Tomorrow (one per reminder; make extra urgent tasks to test each).
5. Morning brief: check it's on in Settings and arrives at its set time (set it a few minutes ahead to test, then set it back).
6. Lock Screen widgets in my wallpaper's tint: check they're readable, including the circular watch dial.
7. The watch. View switcher (sliders button) > Layout > Watch:
   - Is it smooth? Gears turning, balance swinging, seconds hand sweeping, no stutter.
   - Tilt the phone: the watch should tilt and the reflections should slide across the metal. Drag it with a finger too.
   - Tap a gear: the card under the watch should switch to that task, and its tick should work.
   - Switch Theme to Light and back: gold case, leather strap, blue hands vs gunmetal, bracelet, chrome hands.
   - Check the watch widgets in dark and light: the Home Screen "Day dial + Up next" and the Lock Screen circular dial.
   - If the 3D watch stutters or misbehaves, tell me: the app has a simpler 2D watch built in as the fallback, and the next step would be to switch to it.
8. Reduce Motion: iPhone Settings > Accessibility > Motion > Reduce Motion ON. Open the app: animations should be calm, and the watch should hold still (no tilt, no spinning). Turn it back off afterwards if I prefer.

HANDLING PROBLEMS:
- Ask me what I see first. Change the code only if something is genuinely wrong (not just a setting or a SideStore quirk).
- Keep changes small. Push to main, wait for the green build (zero warnings, tests pass), then guide me to download DailyFlow.ipa from Releases > latest again and install it (a fresh install if entitlements changed, otherwise a SideStore refresh may not be enough: say which).
- Never put personal data in the repo: no names, birthdays or family/friend dates in code, comments, tests, sample data or commit messages. My own dates go in on the phone via Settings (custom notice, "every year").
- No secrets or API keys anywhere.

AT THE END:
- Update CLAUDE.md so it says all milestones (M1-M5) and the Phase 3 install are finished, with a one-line note of how it went (Full or Basic widgets, any fixes made). Commit and push to main.
- Then give me a short plain-English summary of what's working and anything left to keep an eye on.

BEFORE YOU START: tell me in plain English that you understand, list any questions, and wait for my "go".
