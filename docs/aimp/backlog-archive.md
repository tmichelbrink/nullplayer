# AIMP skins backlog archive

Closed entries moved out of [`AIMP_TASKS.md`](../../tasks/AIMP_TASKS.md) so the live backlog stays a
list of work that is still open. Every row below is preserved **verbatim**, including the evidence it
was closed on.

## Issuing a number

**The next free number is A45.** A1–A28 closed 2026-10-31 to 2026-11-03 (the family's build-up and
three pre-PR review rounds); A29–A38 closed 2026-11-04 in review round 4 (the maintainer's
review of ad-repo/nullplayer#691); A39–A44 closed 2026-11-27, each measured in AIMP 5.40 under Wine. Check this file before reusing any number: the live backlog is a
list of *open* work and says nothing about which numbers are spent.

## Closed

- A1 Loader and model: `.acs5`, `.acs4`, `.acs4proj`; `ACLIMG32`; `SXML`/`BXML`/text XML; bounded by
  `AIMPSkinPolicy` (`AM0001`–`AM0011`).
- A2 Static renderer: item docking and flow, `PlaceInfo`, nine-slice, buttons, captions, sliders,
  filmstrip sliders, visibility bindings with expressions.
- A3 In-app probe: census and render (`reference/harness.md`). Kanono and Vega MP-120 render close
  to their screenshots; Soot does not (script-driven).
- A4 Deck corpus (2026-10-31): 45 non-4K deck skins from the aimp.ru catalog with their screenshots
  (kept outside the repo). 12 `.acs5` and 18 `.acs4` installed in the corpus
  folder; 16 `.acs3` set aside. 27 of 30 render.
- A5 The mode: `PlayerUIMode.aimp` / `PlayerUIControllerFamily.aimp` (single canvas, own runtime);
  `AIMPSkinMainWindowController` (a `SingleCanvasMainWindow`) and `AIMPSkinMainView`; hover and
  pressed frames; actions mapped to NullPlayer (`AIMPSkinAudioEngineHost`); volume and seek drags;
  `.acs5`/`.acs4`/`.zip` import; the Skins › AIMP submenu. Auxiliary windows: the shared
  controllers in the neutral style, as Audion's.

- A6 Skin state and scripts: tab pages turned by keys, `Schema.xml` providers evaluated
  (`AIMPSkinDataflow`), `DigitsDisplay`, text templates, resource aliases, and a first FastScript
  interpreter (`AIMPSkinScript`). Vega: cassette stickers change with the tape-type keys, the song
  shows on the cassettes that print it, and the tape counter runs.

- A7 Corpus batch (2026-10-31), ranked by how many skins each item reached:
  - all 30 decks render (`.myimg`, AM0005/AM0007 measured, zero-size docked items);
  - control types: `TimeDisplay`, `SpectrumDisplay`, `Gauge`, `Animator`, nested controls;
  - interaction: hit masks (the frame left after whole `FramesPerState` runs), tab selectors,
    script event handlers, script counters, skin timers (`LogicalOperatorTimer`);
  - FastScript: scopes, nested routines, `with`, loops, `exit`, `const`, arrays, sets, math,
    `Delete`, indexed properties (`Data.Spectrum[ch, i]`). Every corpus script runs
    (`AIMP_RENDER_SCRIPTS=1`);
  - scripts drive the EQ (`BandValueN`, `PreampValue`), balance, speed, effects; handlers run on
    track start/finish and on bound values; visualization handlers kick speaker cones and fade
    color-music lamps;
  - companion windows (speakers, amplifiers, EQ units, remotes, color music) beside the deck;
  - `EqualizerDisplay`, `CoverArtDisplay`, `IsActive` (pointer over), tooltips from `Hint`;
  - actions: open files, DSP/EQ window, seek, speed, stay on top, track info.

- A8 `.acs3` (2026-11-01): the container (keys from the name when there is no preview) and
  `ASEIMG32` images; 15 of the 16 corpus decks render close to their screenshots. Panels docked
  side by side size the window (Sony ES-Style Silver 2).

- A14 Scripts the crawl stopped on (2026-11-02): a counter's state parameter under any name,
  units without `Execute`, `var` initializers and parameter defaults (Soot's started at 0),
  `BindingsGetDataAsText3`, neutral `ExecuteColorPicker`/`ApplySkin`/`Randomize`. Crawled scripts:
  3,231 → 3,238 of 3,250 run; the 12 left are docking (`Next` 6).

- A12 The skin's own playlist and library windows (2026-11-02): companions over NullPlayer's
  windows, sizable, maximizable; quick search, playlist and library menus, tabs, vertical scroll
  bars, formatted totals; `AIMPSkinLibrary` groups NullPlayer's library by AIMP's presets for the
  `MLGroupingTree` and `MLTable`. `reference/layout.md` § *Playlist and library windows*.

- A11 Draw order and dynamics (2026-11-01): items' pictures first, then every control, an item's
  own before its children's (the Mayaks' level bars over their meter glass; GX-77's PLM key,
  AIMP-Cassette's keys, Pioneer's cassette title show); unanchored controls with no margins
  centre (every cassette's reel hubs); gauges ease at their `ReactionSpeedLevelUp`/`Down` (Denon
  Classic Style's peak bars); `Checked` reads an action's state (Denon's mute held).
  `PlaylistTabs` draw one lit "Playlist" tab (Sony ES-Style Silver 2's column, GX-77's paper tab).
  Regression renders must compare RGB: `ImageChops.difference(...).getbbox()` on RGBA images
  looks only at alpha.

- A17 AIMP 2 skins (2026-11-02): the `ACSP` package (`.acs`, versions 2 and 3), its Windows bitmaps
  (magenta key, straight alpha), and `main.ini` (both versions' sections, `MainLayout.xml`,
  `PlaylistLayout.xml`) read into the AIMP 3.0 model `AIMPSkinLegacy` builds forms from: the player
  over the docked playlist, all-in-one equalizers in the window, the others a window right of it
  that `EQBtn` opens. 165 of the catalog's 166 render (was 0); the last is a scrambled version
  (`0x20`). The 168 AIMP 3.0 skins render unchanged. `reference/format.md` § *AIMP 2*. Left: AIMP's
  default pictures for objects a skin leaves out (Strong's NEXT and EQ keys show the red
  placeholders under them), the effect sliders (echo, reverb, flanger, chorus), the sleep timer,
  the detached playlist window (`PlsTopDock`), the tray control and quick file info.

- A10 AIMP 3.0 skins (2026-11-01): the `ACS3 02` container, `MySknImg` images, and `MainFrame.xml` +
  `main.ini` read into the form tree (`AIMPSkinLegacy`). Vega AIO v1.01, an all-in-one player with
  its own playlist, renders close to its screenshot. Its window sizes from its right and bottom
  edges; wider, the info panel shows the EQ curve, preamp and EQ switch, then the file details.
  Left: quick search, the second playlist line, `QFI`/`TrayControl`/`DropWheel` frames.

- A9 Polish pass (2026-11-01), from a corpus census of every binding, popup, class and pin:
  skin playlists (embedded and GX-77's window) with scroll bar; popup menus by name (EQ presets,
  Add); held keys (`ActionOnHold`, `ActionOnLongClick`) and release handlers; disabled keys;
  right-click `ContextMenu` values; track details, text providers and template functions; digit
  boxes; selector spreads; masked-slider masks; flat-frame key masks; cover windows as companions;
  oscilloscopes; ratings; `PLWin`/`InfoBox`/`Menu` window names.

- A13 Dock sites and a polish pass from the user's 96 installed skins (2026-11-03): `LayoutDockSite`
  holds the form it names, and scripts dock, undock and move items at run time (`AIMPSkinDockSites`; Bliss Compact Dark, DEFIX Hi-End, KibTech, New.VK,
  Arctur, M.Jukebox, A4's playlists); animators with no `AnimationInterval` hold their first frame
  (RealPlayer 11's VU meter flashed white 20 times a second); one-digit number labels grow left to
  hold the number ("44 kHz", "320 kbps"); `BitRate` read either case; `prvPlayingFileInfo.Duration`;
  Tahoma for unnamed fonts ("M.Library" fits its key); `[COLOR]`/`[B]`/`[I]`/`[U]` text markup;
  `StringOperatorConcatenatorNotificator`, a concatenator with no `Expression`, `%UserTemplateN`;
  playlist fonts given as one value per state (W10's and New.VK's rows were white on white).

- A15 Containers read by their own fields (2026-11-02): the `.acs4`/`.acs3` key comes from the
  scrambled `3SCA` marker in the header, the body from the metadata block's `u32` length, and the
  strings are UTF-16LE (Cyrillic names and descriptions past 255 characters read whole). Every
  `.acs4` and `.acs3` of the crawl opens, with no key search: 61 skins more load (`.acs3` keys 50,
  `.acs4` zlib 7, `.acs5` counts 4); `.acs3` kinds 1/3/5/6 in `reference/format.md` § *Containers*.

- A16 Pictures decode when drawn, within a resident budget, and AIMP 3.0 BMP skins (2026-11-02):
  `AIMPSkinPixelBudget` holds at most `decodedPixels` decoded per skin, letting the least recently
  drawn go; AM0007 now refuses only one image over it. Frames are views into one buffer (a
  side-by-side strip repacked), not copies beside the strip. `.acs3` kind 1's `.bmp` pictures decode
  (`AIMPSkinBitmap`) and take their frames from `main.ini`. 9 of the 10 over-budget decks load
  (Mayak-203: 1.1 Gpx of pictures, ~240 Mpx resident, peak RSS 2.4 GB in the probe, as Technics
  SL-1200's 2.2 GB); the 23 BMP skins render.

- A18 Tab pages, hidden windows, declared placement (2026-11-03): a tabbed group starts on its first
  page not saved hidden, else its first, and a page shows by being active (Unsquareable's playlist
  view, RealPlayer 10–15's equalizer window, Kantaris-Teyp's transport); a window whose items all
  start hidden is sized by them (K-2's open glass lid, LX-tix's equalizer and settings); `Schema.xml`'s
  `Placement` opens a window left of, above, right of or below the deck (K-2's lid and speakers,
  Sharp GF-777's handle and antenna, 27 skins' equalizers); a dock site shows while its form does
  (Telos's transport panel no longer lies under its hidden equalizer) and an empty one is hidden;
  several `laClient` siblings share their parent side by side (Office 2016's ribbon, Red Bias,
  Play Music AIO's header; 134 corpus skins); an unbound `TextDisplay` shows its `Template` (window
  titles and labels: 4,874 displays in 279 skins); `[COLOR=rrggbb]` without `#`, `[URL]` markup.

- A19 Modern-skin layout (2026-11-03): each edge docks its items by `AlignmentLevel` (Denon Classic
  Style's playlist tool bar under its captions, TASCAM CD-RW750's running line inside its frame);
  undocked items run down from the top; several `laClient` items share the row (`ldHorizontal` by
  default, at least what they hold needs); pictureless items are as big as their children laid out;
  key captions centre in
  their content margins; FLAT DARK's caption and
  menu, Red Bias's columns and Soot's transport row lay out. Pictures fill as their `draw` chunk
  says (stretched, tiled, centred: glyphs on flat keys); `BlendingModeOpacity` is a control's
  opacity; tabbed groups follow their `ActivePage` binding (Soot's playlist page). Colours inline
  and through resource chains; `NightMode` from the Mac's appearance (the automatic themes);
  sizable main forms open at their `InitialSize` or docked minimum (Unsquareable, Office 2016,
  Pandemic's playlist); displays wrap (`WordWrap`, `MultiLine`) and size to their text;
  `BlurredGlass` blurs what is under it inside its mask; AIMP's own `@Lng:Section\Key;` strings
  read as words; shared clients hold at least what their children need (LX-tix's info panel);
  `AutoHide` by `AutoHideParentSizeThreshold`, read back by bindings on the next frame; controls
  clip themselves and their children to their `MaskFrame` (A4's glyph keys); a commutator with no
  `Expression` passes its first value; language strings inside bound templates; sizeless tab pages
  fill their group; `CoverArtDisplay` `BlurLevel`; `AutoHide` items show whenever they fit (Soot
  turns all-in-one at 550 px); a provider's `Action` pin is an event, not run at load (Soot's
  volume ring); masks made once per frame and size.

- A20 Fifth review round (behaviour kept, renders unchanged): docking by `Alignment` is one model,
  `AIMPSkinAlignment` (participants, sizes added up, level order, client shares), that the painter's
  layout and item sizes, the renderer's natural and least sizes and AIMP 3.0's translator all
  measure by; `AutoHide` is a docking rule there, no longer a reading of `Visible`; a colour is read
  one way (`AIMPSkin.color(of:)`), AIMP 3.0's and AIMP 2's Delphi colours turned ARGB as their forms
  are read; a frame lays its items out once; blurred covers are made once; Night Mode follows the
  Mac's appearance as it changes; companions open beside the deck by one function.

- A21 Pre-PR quality review, findings 2, 4, 11 and 12 (behaviour kept, renders unchanged on the
  745-skin catalogue): forms, controls and providers read once into typed models
  (`AIMPSkinItem`, `AIMPSkinControl`, `AIMPSkinIndex.Provider`, `AIMPSkinLink`); AIMP actions one
  enum (`AIMPAction`); a frame laid out (`AIMPSkinLayout`), then painted one explicit layer at a
  time, its click targets, tooltips and named rects read from the layout; each item measured once
  a frame; `naturalSize` a plain search with its thresholds in `AIMPSkinPolicy`.

- A22 Pre-PR quality review, findings 7, 8, 9, 14, 15 and 17 (behaviour kept, renders unchanged
  on the 745-skin catalogue): the skin state in three parts (`script`, `animation`, `lists`), a
  layout move any change outside `animation`; the host state split into the engine's
  `AIMPSkinPlayerSnapshot` (its playlist compared by build), the window's `AIMPSkinFrameFeedback`
  and the runtime's match cache, the probe's sample player in the test target; the engine host's
  snapshot a pure read, track starts and finishes counted on the engine's events; the shared types
  `Sendable`, the caches behind `OSAllocatedUnfairLock` but the pixel budget's; node readers
  scoped to AIMP types; `AIMPSkinAlignment` and `AIMPSkinDockSites` named apart; one seek clamp.

- A23 Pre-PR quality review round 2, findings 2–6, 36, 37, the expressions of 9 and the scripts'
  part of 38 (renders unchanged on the 745-skin catalogue, scripts 3,489 of 3,489): each script
  compiled once as the skin loads into a typed tree (`AIMPSkinScript+Syntax`), a tree it does not
  take an `AM0008` warning; one `AIMPSkinScript.Engine` per tick or event owns the state, actions,
  budget and guards (a counter's script that moves its own counter only moves it, in `settle` too;
  AIMP's EQ bands asked for once per NullPlayer band, at the mean of their latest values); a run
  that stops undoes itself; `Unsupported` passes through a skin's `except`, one `finally`;
  `FindObject` resolved once into a `HostObject` and `Set`/`Get` into a `Property`; `prvPitch`'s
  `Set('Position')` moves the speed as its knob does (it was dropped); the built-ins one table;
  `Arguments`, `Data`, `EventData` and `TASEBindings` typed values; binding sets hold
  `AIMPSkinLink`s; `AIMPSkinStep` sorted on the compiled expression, whose operators are enums;
  the harness's dry run in the test target.

- A24 Pre-PR quality review round 2, findings 9 (INI), 10, 11, 12, 29, 30, 32, 33, 34, 39, the
  loader's part of 38 and the cue part of 22 (2026-11-03; renders unchanged on the 745-skin
  catalogue but for seven AIMP 2 spectrums): one byte cursor (`AIMPSkinBytes`), one inflater
  (`AIMPSkinZlib`), one INI reader (`AIMPSkinINI`, case-insensitive: AIMP 2's `[Skin_OPtions]`
  now gives seven skins their declared spectrum colour and bar count); the legacy readers give typed
  `Object`s to one `Translator`; every document read through `AIMPSkinDocuments`, so a malformed
  legacy form is its `AM0009` and a version 3 `.acs` never gets version 2's layout; one
  `AIMPSkinImage` initializer, typed stretch columns, decodes outside the budget's lock, frame
  flags read once when a picture is first laid out (not at load: that cost 25% of load time); `.zip` imports bounded (`AM0012`); the library source apart from the
  engine host, lookups from its build, `LibraryTrack` sorted by `LibraryTextSorter`; dropped cue
  sheets read off main.

- A25 Pre-PR quality review round 2, findings 1, 7, 8, 9 (colour and font), 13, 16 (AIMP's part),
  17, 18, 19, 20, 23 (in part), 24 (in part), 25, 26, 27, 28, 31 (margins), 35 and 38 (menus): the
  frame scheduler keeps one pending input and takes frames by generation; a skin switch stops,
  tears down, installs, then starts; the meter runs with the clock; controls have an identity the
  pointer and gauges key by; the control's class carries its settings and the layout resolves one
  `Look` the painter switches on, over `AIMPSkinCanvas`; bindings resolved once into
  `AIMPSkinSource`; docking and text alignment typed; one colour and one font reader (26 catalogue
  equalizer displays now draw the curve their `ColorCurve` gives as its own value);
  `AIMPSkinCompanionWindows`; form names and popups typed. Renders otherwise unchanged on the
  745-skin catalogue.

- A26 Pascal ranges in `case` labels and sets (`0..9:`, `X in [1..20]`) hold everything between
  their ends, as Pascal's do; they matched their two ends only. 58 scripts in 15 catalogue skins:
  the level meters of Pioneer RT-909, Ода-102, Dual C828 and Orbita-002 stayed dark while playing.

- A27 AIMP apart from shared code (2026-11-03, the owner's choice): other families' code back to
  upstream, AIMP carrying its own copies (`AIMPSkinArtworkLoader`, the EQ popup's preset apply,
  `AIMPSkinMenuItem`, `AIMPSkinDroppedMedia`, `AIMPSkinImporter`'s catalogue). `WindowManager`
  routes the skin's own playlist and library through one AIMP hook (`SkinDrawnLists`); Sonique's
  `SkinDrawnEqualizer` is upstream's. Behaviour and the 745-skin catalogue renders unchanged.
- A28 Review round 3 (2026-11-03, the owner's choice: real defects and speed now, structure deferred):
  one resource resolver for images, colours and fonts (fonts follow `ID` aliases and script
  repoints, keeping their own settings on top); one `@Lng:` expander (an unknown key reads empty);
  display text by the link's typed source (list totals, sleep-timer times); concatenators compared
  by their inputs and read as their text; one operator core for scripts and bindings (bitwise on
  whole numbers, division by zero raises in scripts); item sizes parsed once and measured with
  child and page margins; a main form opens with room for the form docked in it (65 catalogue
  windows no longer cut their playlist); `AIMPSkinCache` computing outside its lock; scripts
  `@MainActor` with a 20,000-step budget. Hit masks measured at 0.6% of draw time and left.
- A29 Scripts off the main thread (review round 4, blocker 4): every script job (a tick, the load, a
  click's or a pointer's handlers, a counter key) runs on the AIMP queue the frames draw on
  (`AIMPSkinScriptScheduler`), over a copy of the state and the player's snapshot, and hands the
  main actor back only what it changed (`AIMPSkinState.Changes`, key by key, applied over the state
  as it stands then) and the `AIMPSkinCommand`s it asked for. One request is out at a time, so each
  starts from what the last left; ticks waiting give way to the latest. A held key's handler answers
  whether it did anything when it lands (the Onkyos' remote panels then drag the window). The probe
  runs them inline, so renders, script counts and live-run actions are unchanged. The main thread's
  CPU per playing frame (`AIMP_RENDER_MAIN=1`, debug build) went from 1.30 ms to 0.34 ms on average
  over the gate corpus, and from 6.47 ms to 0.22 ms on its busiest (Technics Audio System).
- A30 Shared helpers in place of AIMP's copies (review round 4, blocker 2): the cover-art loader
  (`TrackArtworkLoader`), the EQ popup's preset apply (`EQPreset.apply(to:)`), `ClosureMenuItem` for
  `AIMPSkinMenuItem`, the meter level through `PeppyMeterLevels.dbfs`, `PlaylistDrop` for
  `AIMPSkinDroppedMedia`, `INIFile` for `AIMPSkinINI`, `BMPParser.Header` in `AIMPSkinBitmap`,
  `SkinFileCatalogue` and `SkinZipExtraction` under `AIMPSkinImporter`, the Skins menu's actions
  (`SkinFileFamilyActions`). Each shared change landed first with its own tests and the
  other families' corpora unchanged; AIMP's gate unchanged.
- A31 A multi-window family (review round 4, blocker 3): `.aimp` is no longer `isSingleCanvas`. The
  skin's form windows join `WindowManager`'s managed windows, raise order and Snap To Default through
  branches gated on `.aimp`, as `.wmz`'s views do; the deck is a centre-stack member as a `.wmz`
  player is. `SkinAuxiliaryWindows` is gone.
- A32 Form windows through a materializer (review round 4, blocker 3): `AIMPSkinFormWindowMaterializer`
  replaces `AIMPSkinCompanionWindows`. Views are made with the skin, windows lazily when a form is
  first wanted; placement is once, the user's stored place over the skin's declared one, always
  through `WindowManager.rescuedOrigin`; the deck growing in place carries what is docked under it
  through `WindowManager.carryWindowsDockedBelow` (NullPlayer's windows too, which
  `followBottomEdge` left behind). Per skin, `SkinWindowStore` keeps each form window's place and
  whether each form other than the playlist and library was last shown. A form placed where the
  skin says is kept wholly on the deck's screen and, where that covers another of its windows (or,
  moved up onto the screen, the deck), goes beside it (`clearOf`): Tascam Fireone's playlist and
  library, both below a deck near the screen's foot, opened part off screen and on top of each other.
- A33 The shared surface route (review round 4, blocker 3): the controller is a `SkinSurfaceRouter`
  for the playlist and library, docked or windowed; `SkinDrawnList(s)`, `routeSkinDrawnList`,
  `deferUntilSkinDrawnListsLoad`, `skinDrawnListVisibility`, `isNativeWindowVisible` and
  `closeNativeWindow` are gone. A skin switch carries the routed answer and closes NullPlayer's
  windows the skin draws through `dismissFallbackSurfacesTheSkinProvides`.
- A34 No second library (review round 4, blocker 1, engine half): a `MLGroupingTree` or `MLTable`
  lays out as `Look.libraryArea` (the list's fill) with a `.libraryArea` target carrying the list's
  colours. `AIMPSkinLibrary`, `AIMPSkinLibrarySource`, the library state in `AIMPSkinState.Lists`,
  the tree and table drawing, `AIMPSkinCommand.playLibraryTrack`, `AIMPSkinIndex.showsLibrary`, the
  library's row clicks, wheel, Return and menus, and `AIMPSkinLibraryTests` are gone.
  `acMusicLibraryAddFiles` and `pmMLMisc` keep adding files or folders and rescanning
  (`AIMPSkinAudioEngineHost.addFilesOrFoldersToLibrary`). Renders: library list areas show their
  fill instead of rows.
- A35 The real library browser in the skin's lists (review round 4, blocker 1): `AIMPSkinLibraryHost`
  keeps one `EmbeddedLibraryBrowserSurface` per skin and mounts it over the union of the lists'
  areas in whichever view shows them (the library window, the deck, a docked site), at the view's
  scale, in the lists' colours through `SkinnedSurfaceStyle`; the view's `hitTest` gives it its
  clicks. Every source NullPlayer's library window has (local, Plex, Jellyfin, Emby, Subsonic,
  radio) shows in the skin's library window.
- A36 The skin playlist's menu and File Info are NullPlayer's (review round 4, follow-up 11): the
  playlist selects several rows (`AIMPSkinState.Lists.playlistSelection` and `playlistAnchor`: click,
  Shift for a range, Command to add or take out; Delete removes them all, Return plays the first).
  `AIMPSkinPlaylistMenuTarget` answers `PlaylistMenuBuilder`: its menu on a right-click and behind
  `pmPlaylistMain`/`pmMisc`, `removeMenu` behind `pmDelete`, `miscMenu` behind `pmSorting`, and
  `promptAddURL/Directory/Files` behind `pmAdd`. File Info is `fileInfoAlert` (with the EQ line),
  for the one selected row, else the playing track; `AIMPSkinAudioEngineHost.showTrackInfo` is gone.
- A37 One typed record per object (review round 4, item 6): 18 name-keyed dictionaries and sets
  (13 of `AIMPSkinState.Script`'s parts, all five of `Animation`'s) are one `AIMPSkinState.Object` (page, counter,
  shown, auto-hidden, restyled properties, expression, docked, parent, timer switch, interval and
  gate, margins, text) and one `Motion` (timer fired, script inputs, frame, stepped, opacity) per
  object name; resource aliases, variables and config stay keyed as they belong to no object.
  `AIMPSkinState.Changes` merges part by part of each record, so a page main turned and a counter
  the scripts moved on the same object both stay. Renders, scripts and live-run actions unchanged.
- A38 One value command (review round 4, item 6): `AIMPSkinCommand`'s `.volume`, `.balance`,
  `.speed`, `.equalizerBand(dB:)`, `.preamp(dB:)`, `.position` and `.setValue` are one
  `.set(AIMPSkinProvider, Double)`, 0–1 as a control bound to the provider reads it back. Scripts'
  AIMP units (−1…1, dB, multipliers) are turned into it where they are set
  (`AIMPSkinProvider.value(script:)`, its inverse for `Get`); `AIMPSkinAudioEngineHost` alone turns
  0–1 into the engine's units. A script's seek stays `.seek(seconds:)`, a transport move held a
  second short of the end. A script's speed now snaps to 1× within ±3% of it, as the knob and the
  pitch script always did (open point 5). The probe's live run now sets its player's volume from a
  script's ask as the host always did (it took only sliders' before): Sony TC-MR2's volume script
  reads it back and asks once more, 17 → 18 actions; the commands asked are otherwise the same.
- A39 A form's `Visibility` bound to a counter (part of open row 9): a companion form whose
  `Schema.xml` entry binds its `Visibility` to a counter's `Position` follows the counter as it turns
  (`AIMPSkinIndex.windowCounters`, applied in `movingCounter`), never at load. AIMP 5.40 on TASCAM
  CD-RW750: the playlist opens shown with `PL_Counter` at 0, PLST's first press turns the counter to
  1 with nothing to change, the second hides it; EQUALIZER shows the EQ docked above the deck.
- A40 AIMP 3's short template fields, as AIMP 5.40 shows them on a test skin: `%TN` the track number
  (empty untagged), `%TC` the clock `HH:mm:ss`, `%DC` today `yyyy.MM.dd`, `%RT` and `%Rating` `-` (no
  play statistics), `%IN` two digits ("01" of 1 and of 101; Mutter's `01.MP3`). A `FileInfo` link with
  an `Expression` reads its text as a number (Sony Media Tower's `%IN` through `Value MOD 10000`: 1).
- A41 `LogicalOperatorMultiplexer`: `Result` is the `ValueN` its 1-based `Switch` picks (7 corpus
  skins: FLAT DARK's length/remaining read-out, the Elfa and Jupiter reels, Electronica's needle).
- A42 `PageSelector` (M5, Red Bias, A4, Soot): a cell a frame wide per page of the group its `Action`
  link's `Pages` names, from the control's top left, the shown page lit (frame 1); a click on a cell
  shows its page. Matched AIMP 5.40's pixels on a Tunes test skin carrying M5's dots.
- A43 `SpectrogramDisplay` (27 corpus skins): 33.5 px a second right to left, AIMP's frequency scale
  (100 Hz 1.8% up, 1 kHz 17.4%, 10 kHz 75.5%), `ColorBackground` toward `ColorContent` by level,
  flips; its link makes no difference. Measured with tones, 1-s bursts and 6 dB steps.
- A44 Library row spacing (BECHA's `clfRowContentOffsetsMode`, about 24 skins): the counter script's
  `Style.RowContentOffsets` on `MLTable` (8, 4, 2 a side) grows the embedded browser's rows by what
  passes 2 + 2.
