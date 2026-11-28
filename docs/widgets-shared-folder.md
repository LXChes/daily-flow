# Widgets and the shared folder (Plan A, with Plan B built in)

## In plain English

The app and its widgets live in separate locked boxes on the iPhone. For a widget to show your tasks,
the two need a **shared folder** (Apple calls it an *App Group*).

- **Plan A (what the build does now):** the app asks for a shared folder when it's installed.
  SideStore may grant it to your free Apple ID. If it does, the widgets show your real tasks and you
  can tick them off from the Home and Lock Screens.
- **Plan B (the automatic safety net):** if the shared folder isn't granted, nothing breaks. The
  widgets switch to **basic mode**: they still show the date, the time, the 24-hour dial and notice
  days like "It's Christmas Day", plus a small "Open Daily Flow" hint. Notifications (the morning brief
  and urgent reminders with Complete / Snooze 30m / Tomorrow) work fully either way: they don't need
  the shared folder.

Nobody can promise SideStore will grant the shared folder on a free account, so the app is built to
work both ways.

## What you need to do

1. **Install the new build** with SideStore as usual, using the IPA from the repo's
   **Releases → latest** page. Use SideStore's *install* (or delete the old copy and install again),
   not just *refresh*, so SideStore sees the new request.
2. **If SideStore asks about App Groups** or registering anything for the app, say yes.
3. **Check whether it worked:** open Daily Flow → **Settings** → **WIDGETS**.
   - **Full widgets** means the shared folder was granted. 🎉
   - **Basic widgets** means it wasn't. Everything else still works.
4. **Add the widgets:** long-press the Home Screen → **+** → *Daily Flow*. For the Lock Screen,
   long-press the Lock Screen → **Customise** → Lock Screen → tap the widget area → *Daily Flow*.
   Long-press any widget → **Edit Widget** to give it its own style (Match app / Dark chrome /
   Light vintage).

### If you see "Basic widgets"

- Update SideStore to its newest version, then install Daily Flow again (step 1).
- If your SideStore has a setting about App Groups or app extensions, make sure it's on.
- Free Apple IDs can register only a few app IDs per week. Daily Flow uses two (the app and its
  widget). If SideStore complains about the limit, wait a few days or remove another sideloaded app.
- If it still says Basic, that's fine: Plan B is working as designed. Tell the next session and it
  can investigate.

### If SideStore refuses to install the app at all

If the error mentions an **app group**, an **entitlement** or a **capability**, the request itself is
the problem. Tell the next Claude session:

> Set `REQUEST_APP_GROUP` to `"false"` in `.github/workflows/build-ipa.yml` and push.

That one-line change removes the request. The next build installs like before, and the widgets run
in basic mode.

---

## Technical notes (for future sessions)

- **Request:** `Signing/DailyFlow.entitlements` and `Signing/DailyFlowWidget.entitlements` hold
  `com.apple.security.application-groups = [group.com.example.dailyflow]`. The Xcode archive stays
  unsigned (`CODE_SIGNING_ALLOWED=NO`). A CI step then **ad-hoc signs** (`codesign --sign -`, no
  certificate or team) the framework, the widget and the app with those files. That only records the
  request in the binaries, where a sideloading tool reads it. CI fails if the request is missing.
  The step is gated by the `REQUEST_APP_GROUP` env in the workflow.
- **Discovery at runtime:** `Core/Sharing/SharedContainer.swift`. Sideloading tools rename groups for
  free accounts (usually by appending the team id) and list the real names under `ALTAppGroups` in the
  installed Info.plist. The code tries those names (from its own bundle and, in the widget, from the
  containing app), then the requested name. It keeps the first that
  `containerURL(forSecurityApplicationGroupIdentifier:)` returns *and* that accepts a probe write.
  Nothing is force-unwrapped, and with no group everything returns nil.
- **Fallback order for widgets** (`Core/Sharing/WidgetData.swift`, unit-tested):
  shared snapshot for today → the widget's own cached copy in its standard `UserDefaults` (read-only)
  → basic mode, with the date and built-in notice days computed in the widget → placeholder.
- **Ticks from widgets:** `ToggleTaskIntent` queues the tick in the shared folder and patches the
  shared snapshot, so every widget updates at once. It also removes that task's pending reminder. The
  app applies the queue (`DeviceOutputs.applyWidgetTicks`) at the start of every reload. Tick buttons
  only appear when the source is `.shared`.
- **The SwiftData store stays in the app's own container**, so data never moves and nothing depends
  on the group. Widgets only ever see `DaySnapshot`.
