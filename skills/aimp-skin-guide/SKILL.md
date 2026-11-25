---
name: aimp-skin-guide
description: AIMP skin family (.acs5, .acs4, .acs3 — AIMP 4 forms and AIMP 3.0's main.ini skins —, .acs4proj; AIMP 2's .acs is decoded but not read yet) — the decoded containers, ACLIMG32/ASEIMG32 images, SXML/BXML documents, layout and binding rules, FastScript scripts, the test-target harness and load gate, and the backlog. Use before AIMP skin work, when an AIMP skin looks or behaves wrong, or when reading an AIMP skin.
---

# AIMP skins

Read this before AIMP skin work. The family pattern is `skin-subsystem-blueprint`; the phase order
for testing and fixing one skin is `skin-triage`; the backlog is `tasks/AIMP_TASKS.md`.
`skin-triage`'s per-family tables have no AIMP row (shared docs stay as upstream has them); for
AIMP read them as: evidence is the skin's own artwork, markup and scripts and its catalog
screenshot, so a diff is unclassified; the sweeps are `AIMPRenderDumpTests` and
`AIMPCorpusLoadTests`; the inventory dump is `AIMP_RENDER_ITEMS=1` and `AIMP_RENDER_TARGETS=1`;
controls are driven by `AIMP_RENDER_LIVE=1`, then `AIMP_RENDER_CLICK`, `AIMP_RENDER_WHEEL`,
`AIMP_RENDER_HOVER` and `AIMP_RENDER_PAGES`/`COUNTERS` per state (`reference/harness.md`).

- **Engine:** loader, model, scripts and renderer in `Sources/NullPlayer/AIMPSkin/`. Forms are read
  once into typed items and controls (`AIMPSkinIndex`); each frame is laid out (`AIMPSkinLayout`),
  then painted (`AIMPSkinPainter`), and its click targets are read from the layout
  (`reference/layout.md` § *How a frame is made*).
- **Window:** `Sources/NullPlayer/Windows/AIMPSkin/`; `PlayerUIMode.aimp` routes it.
  - One `AIMPSkinRuntime` per skin owns its state, its one clock (30 fps while playing and seen)
    and each window's eased gauges (`AIMPSkinGauges`). Skin scripts are untrusted input and never
    run on main: a tick, the load, a click's or pointer's handlers and a counter key are each an
    `AIMPSkinScript.Job`, run by `AIMPSkinScriptScheduler` on the AIMP queue
    (`AIMPSkinFrameScheduler.queue`, the one the frames draw on) over a copy of the state and the
    player's snapshot, on one `AIMPSkinScript.Budget` per request (a tick; the load; one event,
    `asOneEvent`). What lands on main is an `AIMPSkinScript.Outcome` per job: its
    `AIMPSkinState.Changes` (part by part of each object's record, applied over the state as it
    stands then, so a list scrolled meanwhile stays) and its `AIMPSkinCommand`s. Main never waits
    on that queue. One request is out at a time, so each starts from what the last left; requests
    made meanwhile wait in order and go out together, a waiting tick giving way to a later one. A
    held key's handler answers whether it did anything when it lands (nothing: the press becomes a
    window drag). When a tick's outcome lands, each form's view draws its frame on the same queue
    (`AIMPSkinFrameScheduler`: one frame at a time; requests made meanwhile wait as one, the
    latest, measuring if any asked to) and shows it when ready. A frame is taken by the view's
    `Generation` (its skin, and which change of what shows), not the skin's name; the content stays
    to be measured until a measured frame of the latest change shows. The level meter runs with the
    clock; while the clock runs, a change waits for its next tick. A skin switch stops the outgoing
    runtime and closes its windows before the incoming one is installed and its load scripts run.
    The probe sets the frame scheduler's timing to
    `.probe(clock:)`: it draws synchronously, at its own clock; and the script scheduler's to
    `.inline`: each job runs before the call that asked for it returns. Everything a frame reaches is
    declared `Sendable`, so the compiler checks that boundary; the skin's caches keep their state
    behind an `OSAllocatedUnfairLock` (the pixel budget, whose one lock spans every picture, says
    why it cannot), and make a value outside it (`AIMPSkinCache`).
  - Each form's `AIMPSkinMainView` draws and takes the pointer; its state is in collaborators: the
    press under way (`AIMPSkinPress`: held target, drag hand-over, hold timer), the form's size and
    the user's sizing (`AIMPSkinSizing`), and the quick search's text field (`AIMPSkinSearchField`).
    What it hovers and holds, and each gauge it eases, is keyed by the control's identity
    (`AIMPSkinControl.ID`, numbered by the index), never its name. The skin's other windows are
    `AIMPSkinFormWindowMaterializer`'s, on `WMPViewWindowMaterializer`'s pattern: a view per form
    made with the skin (so `hasContent` is known), a window only once the form is visible, undocked
    and drawing while the deck shows; placed once, where the user last left it (`SkinWindowStore`,
    family `aimp`), else where the skin declares (`Companion.origin`) kept wholly on the deck's
    screen and beside, not over, the skin's other windows (`clearOf`), then
    `WindowManager.rescuedOrigin` (`AIMP_PLACE_TRACE=1` logs it); a docked form has no window. The
    store also keeps, per skin, whether each form other than the playlist and library was last
    shown, seeded before the load scripts run. When the deck grows in place,
    `WindowManager.carryWindowsDockedBelow` moves what hangs under it. The controller presents skins
    and wires them. Popup menus are `AIMPSkinPopup`.
  - One `AIMPSkinAudioEngineHost` per window controller maps AIMP actions and providers to the
    player and is stopped with the mode. Its `snapshot` only reads (`AIMPSkinPlayerSnapshot`); track
    starts and finishes are counted, and background fetches begun, on the engine's events. The
    skin's library lists keep no library model: they are NullPlayer's library browser, one per skin
    (`AIMPSkinLibraryHost` over `EmbeddedLibraryBrowserSurface`), mounted over the lists' area in
    whichever view reports one (`AIMPSkinMainView.onLibraryArea`), the view's `hitTest` giving it its
    clicks (`reference/layout.md` § *Playlist and library windows*).
  - A frame reads `AIMPSkinHostState`: the player's snapshot (the runtime's latest), the drawing
    window's feedback (`AIMPSkinFrameFeedback`: clock, meters, pointer, last frame's rows and
    gauges) and the quick search's matches (the runtime's cache). A script run outside a frame (a
    click's handler) reads no window's feedback. The runtime compares snapshots by value, the
    playlist by its build (`Playlist.generation`).
  - What a press, drag or wheel notch does is the target's (`AIMPSkinTarget`): `Kind.isDraggable`,
    `Kind.passesDragsThrough`, and `AIMPSkinStep`, a counter key's or tab selector's `Expression`
    compiled once and sorted by what the wheel does with it (`ScrollDelta` is the notches, a click one). The
    view's mouse code (`AIMPSkinMainView+Mouse.swift`) dispatches on them; it reads no expression text.
  - The skin's own playlist and library forms, in a window or docked in the deck, answer the app's
    through the shared surface route: the controller is a `SkinSurfaceRouter`, as Sonique's is
    (`drawsSurface` where the skin has a form of that role; NullPlayer's EQ window serves beside every
    skin). On a skin switch the carry reads the routed answer before the outgoing skin stops, sets
    the incoming skin's forms to it, opens NullPlayer's window for a surface it has none of, and
    closes NullPlayer's beside the skin's own (`dismissFallbackSurfacesTheSkinProvides`). Its other
    windows join docking, snapping, the raise order and Snap To Default through `WindowManager`'s
    AIMP branches (`materializedAuxiliaryWindows`): AIMP is a multi-window family, not a single
    canvas, so its deck is a centre-stack member as a `.wmz` player is. Whether they are open is the
    session's; a launch's restore of the playlist or library waits for the first skin
    (`deferUntilSkinLoads`).
- **Skins:** Skins › AIMP lists `Application Support/NullPlayer/AIMPSkins` (`AIMPSkinImporter`,
  selection key `aimpSkinName`). A `.zip` is bounded before it is written (`AIMPSkinZipLimits`,
  `AM0012`). A name is one skin: installing `X.acs4` replaces `X.acs5`, of two left from before
  `.acs5` lists, and removing the name removes every file of it.

## Shared code

AIMP calls the helpers the other families share instead of keeping its own copies (review round 4:
isolation means leaving the other families' behaviour as it is, not forking their helpers). Each was
made shareable in its own change, naming the families it touches:
- `TrackArtworkLoader` (`Utilities/`, WMP's loader moved there) for the cover-art displays;
- `EQPreset.apply(to:)` (WMP's `eq.currentPreset`) for the EQ popup's presets;
- `ClosureMenuItem` (`Utilities/`, as `TrackVerb`'s menu) for the popups and context menu;
- `PeppyMeterLevels.dbfs(fromVolume:floor:)` for the meters' level, so the host no longer re-derives
  PeppyMeter's mapping;
- `PlaylistDrop` (`Utilities/`, the classic and Modern windows') for dropped files, cue sheets read
  off the main thread;
- `INIFile` (`Utilities/`, Sonique's reader) with `repeatedSections: .continued` for `.lng` files
  (`INIFile+AIMP`);
- `SkinFileCatalogue` (Sonique's catalogue) and `SkinZipExtraction` (Audion's zip reader) under
  `AIMPSkinImporter`;
- `SkinFileMainWindow+SkinsMenu` (Sonique's and Audion's) for the Skins menu's AIMP entries.

Outside AIMP's folders the branch adds only what the family cannot run without: its
`PlayerUIMode`/`PlayerUIControllerFamily` case in the exhaustive switches, its menu entries, and
`WindowManager`'s branches gated on `controllerFamily == .aimp` (docking, raise order, Snap To
Default). The playlist and library route through the shared `SkinSurfaceRouter`, with no AIMP hook.

## The rule that outranks everything

**AIMP work must never change Classic, Original, `.wal`, `.wmz`, Audion or Sonique behaviour.**
Shared code gates on `controllerFamily == .aimp`. `skin-subsystem-blueprint` § *The rule that
outranks everything*.

## What kind of engine this is

- **Markup plus script, reverse-engineered.** Forms are trees of layout items and controls; behaviour
  is bindings with expressions, providers, and FastScript (Pascal) scripts.
- **Bitmap skins** (tape decks) are layout and state; **modern skins** (Soot) depend on scripts,
  `AutoHide` and cover art.
- **No oracle.** AIMP is Windows-only. The reference is the skin's catalog screenshot; a diff against
  it is evidence, not ground truth (blueprint § *A sweep diff is unclassified*).

## Symptom → file

| Symptom | Read |
|---|---|
| A skin fails to load, or an `AM####` code | `reference/loading.md` |
| A container, image or document decodes wrong | `reference/format.md` |
| Something drawn in the wrong place or not at all | `reference/layout.md` |
| Any measurement: a probe flag, the load gate, the census | `reference/harness.md` |
| An engine-wide change, or a named skin | `reference/skins/README.md` |
| What to build next | `tasks/AIMP_TASKS.md` |

## Debugging a live defect

Applies to anything that only reproduces on screen. Route to `skills/live-ui-testing` for the
method and `skills/app-control` for the mechanics; this is the AIMP half.

1. Reproduce it headless first: the window draws exactly what the probe renders
   (`AIMPSkinRenderer.frame`). A defect that shows in the probe's PNG is a renderer defect.
2. A key, timer or script that seems to do nothing: run the app with `AIMP_ACTION_TRACE=1` and read
   whether the action reached the player. An unmapped one logs
   `AIMPSkin: no NullPlayer action for '<action>'` once.
3. A loop or flood only the window shows: `AIMP_RENDER_LIVE=1` (`reference/harness.md`).
4. Launch the debug build on the skin:

```bash
skills/app-control/scripts/launch.sh aimp:28_Kenwood_KX-800 --no-play
```

**Confirm it took:** `LAUNCH PASS: aimp skin '<name>'`. The launcher writes `aimpSkinName` in the
debug domain (`NullPlayer`); it quits any running `NullPlayer` first, the installed app included.
