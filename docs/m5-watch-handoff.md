# M5 hand-off: the watch (read this before starting M5)

M4 shipped a **placeholder** 24-hour dial for the two watch-style widgets. It's deliberately plain:
flat chrome ring, task arcs, one hand, a now arrow. **It is not the design.** M5 must replace it with
the rich skeleton watch from the brief, in the app *and* in the widgets.

## What is a placeholder today

| Where | File | State |
|-------|------|-------|
| Widget: Lock Screen `accessoryCircular` "Day dial" | `WidgetUI/DialPlaceholder.swift` | Placeholder, replace |
| Widget: Home Screen `systemMedium` "Day dial + Up next" (dial half) | `WidgetUI/DialPlaceholder.swift` | Placeholder, replace (keep the Up next half and its tick buttons) |
| App: Layout → **Watch** in the view switcher | `AppModel.layout` maps `.watch` to Play the day | Not built yet |

## What M5 must build (from `docs/design-brief.md`)

- **In the app (Layout → Watch):** a realistic skeleton watch with tiltable 3D layers (device-motion
  parallax). Every task is a gear: it spins faster while on, is polished when done, and an urgent
  task's jewel pulses. Timed tasks are arcs on a two-tone 24-hour bezel. An arrow hand shows now.
  About 20 cogs, plus a balance, pallet fork, mainspring, keyless works and thin bridge arms.
  - Dark: gunmetal case, black ceramic bezel, faceted chrome hands with lume, metal bracelet.
  - Light: gold case, ivory Roman ring, blued Breguet hands, cream/tobacco bezel, stitched leather strap.
  - Native rendering: SceneKit / RealityKit, or a Metal-shaded SwiftUI `Canvas` with `TimelineView`.
    Keep 60/120 fps and honour Reduce Motion with a calm alternative.
- **In the widgets:** a *static* rendering of the same watch, scaled for `accessoryCircular`
  (vibrant / monochrome on the Lock Screen: shapes must read without colour, key mark
  `.widgetAccentable()`) and for the left half of `systemMedium` (full colour, both themes).
  - Widgets cannot animate: no `TimelineView`, no motion. The hand moves by timeline entries, which
    M4 already supplies every 15 minutes and at task boundaries (`Core/Sharing/WidgetTimeline.swift`).
  - Widget extensions have about **30 MB** of memory. No SceneKit/RealityKit in the widget; draw with
    `Canvas`/`Shape`s, or a small pre-rendered image layer plus vector arcs and hands.
  - Basic mode (`entry.day.source == .basic`) has no tasks: the watch must still look complete (case,
    bezel, hands at the right time, no task arcs).
- Use the same inputs the placeholder uses: `DFWidgetEntry` (`snapshot.tasks`, `minute`, `theme`,
  `palette`), so nothing in `Widget/` or `Core/` needs to change.

## Fallback rule (from CLAUDE.md)

The watch is the riskiest piece. **Ship a simpler fallback watch first** (for example, a 2D layered
Canvas watch with a few gears), get CI green and screenshots signed off, then go for the full 3D
version. If the full one is not smooth, keep the fallback.

## How to check it

CI screenshots: the scenes `widgets`, `widgets-light`, `widgets-lock` and `widgets-basic` show every
widget face. Add a `watch` and a `watch-light` scene for the in-app watch.
