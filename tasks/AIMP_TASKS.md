# AIMP skin family — backlog

The only backlog for the AIMP skin family. Read `skills/aimp-skin-guide/SKILL.md` before picking
anything up; the family pattern is `skills/skin-subsystem-blueprint`.

- **Done** rows are numbered `A<n>` in the order they landed and moved, verbatim, to
  [`docs/aimp/backlog-archive.md`](../docs/aimp/backlog-archive.md); the next free number is
  A39 (the archive keeps the count).
- **Next** is ranked by how many corpus skins a row reaches, measured by the census
  (`reference/harness.md`); a row moves to the archive, numbered, in the change that closes it.

## Open for the maintainer (review round 4)

Behaviour the round-4 rework gave up or changed, listed for the maintainer to accept or reject; none
is decided here.

1. **The skin's library controls with no stand-in** (blocker 1). The library lists are NullPlayer's
   browser, which has its own tabs, search and row menus. These skin controls are left inert:
   - `pmMLGroupingPresets` (AIMP's grouping presets) and `pmMLDelete` (remove from library), and the
     tree's and table's own right-click menus (`pmMLGroupingTree`, `pmMLTable`): a key naming one
     is dimmed, shows the "Not available in NullPlayer" tooltip, and opens nothing;
   - a skin search box bound to `MLTable` or `MLGroupingTree`: drawn empty, takes no click;
   - read-outs of `MLTable` `Count`/`Duration`/`Size` and of `GroupingPresets`: read nothing, so
     a library window's status line shows `0 / 0:00:00 / 0.00 MB` and its grouping caption is
     empty (every gate skin's `MusicLibraryFrame`). The browser shows its own counts; hiding the
     skin's, or feeding them from the browser's current list, is the maintainer's call;
   - skin keys drawn over a list (Chroma's add/remove/sort buttons on its table) sit under the
     opaque browser and cannot be reached; a glass layer over the list (Alchemy) blurs only the
     fill.
3. **Behaviour changes in the skin playlist's menus** (follow-up 11): `pmSorting` now opens the
   builder's Misc section (Sort ▸, File Info, EQ profile, row fields) instead of AIMP's flat sort
   list (which had By Duration and Shuffle); `pmAdd` uses the builder's URL / folder / files prompts.
4. **The deck growing carries NullPlayer's windows too:** `carryWindowsDockedBelow` moves every snap
   target docked under the deck (NullPlayer's playlist or EQ under it), where AIMP's own
   `followBottomEdge` moved only the skin's forms.
2. **The library browser's tab is not kept across launches in AIMP mode.**
   `WindowManager.plexBrowserBrowseMode` reads `.wal`'s embedded surface only; the routing series
   skipped S3 (`embeddedLibrary` on `SkinSurfaceRouter`), which would let AIMP's host answer too.
5. **A script's speed snaps to 1× near it** (item 6, one value command): the host's 1× detent
   (±3%) now applies to `prvSpeed`/`prvTempo` set by a script too, as it did to the knob and to
   `prvPitch` scripts. A script's EQ and preamp writes are clamped to ±12 dB at 0–1, as the engine
   clamped them already.
6. **AIMP 3.0 and AIMP 2: removed, a direct reader to come** (item 6, decided 2026-11-25). Their
   forms were built by translating `main.ini` into generated AIMP 4 XML, the design the 691 review
   flagged. The engine PR reads AIMP 4 and 5 only and refuses these as `AM0011`. Next: a reader that
   builds `AIMPSkinItem`/`AIMPSkinControl` straight from `main.ini` (AIMP 3.0, kinds 1 and 2) and
   `ACSP` (AIMP 2), its own PR before AIMP is turned on. Weight: 356 of the 742 catalogue skins that
   loaded, and 10 of the 13 tier-A matches, are AIMP 3.0. `format.md` keeps what was decoded.
7. **The skin playlist follows the playing track by the shared rule** (upstream #718,
   `PlayingRowPlacement`): the least scroll that shows the row, or the row centred under shuffle,
   as Classic, Original, `.wal` and `.wmz` do; a skin just loaded follows it too. It used to put the
   playing row two rows from the top on every track change. Not checked against AIMP itself.

## Corpus survey (2026-11-02)

A locally collected copy of the aimp.ru PC-skins catalog (819 records; the downloader is kept outside the repository): 740 new skins
beside the 46 installed, plus 46 duplicates, 67 non-skin records, 3 RAR, 3 failed downloads.
By format: 175 `.acs4`, 169 `.acs3`, 168 AIMP 3.0 `.acs3` (`ACS3 02`), 67 `.acs5`, **166 `ACSP`**.

Load + script census of the 579 AIMP 3–5 skins (probe, no render): **508 load (88%)**, scripts
**3,044 of 3,250 run (93.7%)**. Ranked gaps:

1. ~~**`ACSP` (166, 21% of the catalog): AIMP 2's package.**~~ Done (A17): 165 of 166 render.
2. ~~**`.acs3` keys (50)**~~: done (A15).
3. ~~**Image budget (10 `.acs5`)**~~: 9 done (A16). Left: Reloop RP-7000 GLD 4K,
   whose tone-arm strip alone is 493 Mpx (299,625 × 1,646, frames side by side); it would need
   frames decoded one at a time.
4. ~~**`.acs4` without a zlib stream after the preview (7)**, **`.acs5` entry counts read as garbage
   (4)**~~: done (A15): the metadata length, and UTF-16LE strings.
5. ~~**Scripts (206 failures at the census)**~~: all run (A14; docking verbs with A13). Were: `try` statements 19,
   `StrToInt64` 18, `TASEBindings.Create` 17, `IsLoaded` 17, `Copy` 11, `ColorToARGB` 10, `Now` 8,
   `Self` 6, `ExecuteAction(ActionOnHold)` 6, `PLDock.Parent` 6.

Not yet measured: renders of the crawled corpus (sizes run to 600 MB a skin).

Re-census after A13–A19 (2026-11-03, all 745 crawled skins incl. AIMP 2): **742 load**, scripts
**3,489 of 3,489 run**. Left: Reloop RP-7000 GLD 4K (one 493-Mpx strip), JD_Vifaru (an 85,536-px
slider frame, AM0006), Dark Lagoon (ACSP version byte 0x20).

## Next

1. **Actions with no NullPlayer equivalent:** record (`acPlayerRadioCapture`, 28 skins), A–B repeat
   (8), tag editor, converter, the TrueBass/reverb/echo/chorus/flanger/enhancer knobs. Stay
   no-ops unless NullPlayer gains them.
2. **The skin's own info and lyrics frames**: they open NullPlayer's windows. TC-MR2's skin-drawn
   `Menu` popup likewise. Playlist and library windows are done (A12; the library is NullPlayer's
   browser since review round 4); left there: bookmarks, the playlist manager, several playlists.
3. **Modern skins** (Soot): `AutoHide`, `LayoutSplitView`, `BlurredGlass`, colouration.
4. ~~**Streaming sources in the skin's library window**~~: done by hosting NullPlayer's library
   browser (review round 4).
5. **Scripts moving controls** (`PlaceInfo.Margins.*`: Technics' music-light lamps shuffle,
   speakers' `MagnetRectOffsets`), `RunningLine` scrolling.
6. **Docking at run time:** sites are mounted at load (A13); scripts that move forms between sites
   and windows (`Dock`, `Undock`, `Parent()`: A4 3.2's layouts, Telos, Fantasy, M5, Red Bias) are
   not followed.
7. **Corpus gaps** (`Corpus survey` above): AIMP's own dialogs (`ApplySkin` and
   `ExecuteColorPicker` finish as no-ops: a colour picker and switching to another AIMP skin by name).
 8. **Code-quality follow-ups** (thermo-nuclear review, 2026-11-02; none blocks merge):
    - form names classified once: `AIMPFormRole` is case-sensitive AIMP names, while
      `AIMPSkinLoader.title(ofForm:)` and `Companion.placement` read skin-chosen names (`EQForm`);
    - `AIMPSkinAudioEngineHost.snapshot()` counting track starts by sampling (belongs in
      `updateTrackInfo`);
    - round 2 left: a picture's `stretchColumns` as a type (in `AIMPSkinImage`), a non-optional
      runtime for the skinned view. (The skin playlist's menu through `PlaylistMenuBuilder`, finding
      14, is done: review round 4.)
9. **A form's own `Visibility` binding** (`Schema.xml`, 41 forms: Dark v1.7's four windows on
    counters, Romantik 304's playlist on a tab page, Denon Classic Style's units on commutators) is
    not read: those windows follow their `Visible` keys only. AIMP's evidence (RealPlayer's EQ key
    opens a form bound to a page index that stays 0) says the binding sets `Visible` when its value
    changes rather than gating it.
10. **`MagnetRectOffsets`** on the main form: Dual C 846 & CV 1460's window is 608 px tall with its
    top half transparent until the amplifier key shows the amplifier there; AIMP snaps windows to the
    deck's edge 304 px down (the amplifier script moves it). NullPlayer snaps to the frame, so docked
    windows stand clear of the empty half; needs `WindowManager` to take a snap inset.
11. **Counter scripts at load:** a `ScriptableOperatorCounter`'s script runs only when its input
    moves, so the state it sets up for position 0 is never set (LX-tix's `DownPanelView` hides its
    second info panel at 0; both now show side by side). AIMP runs it as the skin loads.
12. **Script leftovers from review round 2:** a script's `ExecuteAction` on a link
    (`AIMPSkinScript+Bindings.swift`, `perform`) is a second "what a link press does" beside
    `AIMPSkinControl+Input`'s `press`; a lamp's `Value = N` (`AIMPSkinControl.selectedPosition`)
    still reads the expression's text, where it could match the compiled tree as `AIMPSkinStep` does;
    animators that keep their own frame are stepped by the script engine (`Engine.visualize`)
    although no script owns them.
13. **Texture tint by `ColorID`:** a texture resource can name a theme colour that AIMP tints it with;
    NullPlayer draws it untinted. M5 (1246) shows its light panels behind its dark-theme text, so the
    info window's title and the bottom bar's icons vanish.
14. **Captions a script sets:** Telos's options form shows `@Lng:48;`, `@Lng:49;`, `@Lng:1;`; text a
    script assigns does not go through the `@Lng:` expander. Bliss AIO's status line lacks its
    `%Bitrate` (a template field not resolved).
15. **Sizing left from review round 3 (C1):** `AIMPSkinRenderer`'s natural-size search, the AIMP 3.0
    translator's synthetic `SizeMinimal` and the list-growth loop are still separate from the one
    measure; Arctur (×3) leaves the natural size before a docked form's minimum is applied.
16. **Structural findings from review round 3** (deferred by the owner, listed in the
    AIMP PR's description): the window layer's frame feedback,
    clock and list interaction (A3–A8, A10); the index built from a half-built copy of itself (B1);
    one value command in one unit (B2, B3); typed property accessors and state records (B7, B9,
    B11–B14, B16); the legacy loader's string round trips and the script decoder (C2, C3); the
    layout's `Look`, key-frame rules, settle loops, raw geometry and painter boilerplate (C5–C11,
    C14, C15).
