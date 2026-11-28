# AIMP loading: what is tolerated, what stays fatal

`AIMPSkinLoader.load` (`AIMPSkin.swift`) reads one archive into an `AIMPSkin`. The limits are
`AIMPSkinPolicy`; the codes are `AIMPSkinDiagnosticCode`, stable once written. A fatal finding is
thrown; a warning rides on `skin.findings`. Never relax a limit to make a skin load: argue the threat.

Every document is read through one `AIMPSkinDocuments` per load, which keeps what does not read as
a finding: nothing is dropped with `try?`. Missing is nil; there and unreadable is nil and a finding;
the caller decides whether that is fatal (`throwing`, for the main form). Every binary read goes
through one bounds-checked cursor (`AIMPSkinBytes`), every inflate through `AIMPSkinZlib` (the zlib
header checked), every `.lng` through `INIFile` (`INIFile+AIMP`).

## The codes

| Code | Fatal | Raised when |
|---|---|---|
| `AM0001` | yes | not an AIMP archive: too short, no header, no zlib body where the metadata length says |
| `AM0002` | yes | the file is over `fileBytes` (1 GB), or a `.zip` entry inflates past its declared size on import |
| `AM0003` | yes | more than `entries` (32,768) entries |
| `AM0004` | yes | an entry or header field lies past the end of the file |
| `AM0005` | yes | one entry, or a whole `.acs4` body, declares or inflates past `inflatedBytes` (1 GB); or a skin's pictures and scripts declare more than `loadInflatedBytes` (2 GB) together, counted before any is inflated |
| `AM0006` | yes | an image's *frame* side is over `imageSide` (16,384 px); a filmstrip's full width is not |
| `AM0007` | yes | one image alone is over `decodedPixels` (256 Mpx), from its header. Pictures decode when first drawn, and a skin keeps at most `decodedPixels` decoded at once (`AIMPSkinPixelBudget`): a decode that would pass it lets the least recently drawn pictures go, to decode again if drawn again |
| `AM0008` | **no** | an entry does not inflate, is truncated, or is not an image; or a compiled script (`FSXMLBIN`) does not decode, or has a tree the script compiler does not take: it is skipped |
| `AM0009` | if the main form | malformed or over-deep XML (`xmlDepth` 256, `xmlNodes` 1,000,000) |
| `AM0010` | yes | no `AIMPMainForm.xml` |
| `AM0011` | yes | a container this engine does not read: an `ACSP` version other than 2 or 3 (Dark Lagoon's scrambled `0x20`), or an unknown header kind |
| `AM0012` | yes (import) | a `.zip` import past `SkinZipLimits.aimpSkins` (`SkinZipExtraction`; entries, total bytes, a ratio past 200:1 above 1 MiB), or a skin in it failing its CRC or size. A skin over the file limit in a zip is `AM0002` |

## Limits past loading

Not codes: what a loaded skin is held to while it runs, each tested by an input crafted past it
(`AIMPSkinHostileInputTests`, `AIMPSkinScriptTests`, `AIMPSkinModelTests`).

| Limit | What it bounds |
|---|---|
| `Budget.stepLimit` (20,000), `depthLimit` (32), `byteLimit` (4 MiB) | one tick's or event's script work: steps, call depth, and the bytes of text its `+`, `Insert`, `Format` and string built-ins read and make |
| `Run.textLimit` (64 KiB), `formatWidthLimit` (1,024), `expressionDepthLimit` (256) | one text a script makes, one `Format` field, one expression's nesting (refused at compile) |
| `storedTextLimit` (4 KiB), `storedKeyLimit` (256), `longestPropertyPath` (256), `deepestPropertyPath` (8) | what scripts keep: `ConfigSet`'s store and one object's properties; a `Set` on a name the skin has no object of is ignored |
| `frameSide` (32,768 px) | the frame `AIMPSkinRenderer.frame` draws, each side, and at most `decodedPixels` in all |
| `AIMPSkinWorker.stackSize` (16 MB) | the stack layout and scripts run on, asserted in debug builds (`hasDeepStack`) |

## Tolerated

| Input | What the loader does |
|---|---|
| `Schema.xml` missing or malformed | loads without providers or resources; the parse failure is a warning |
| An image entry unreadable | skipped with `AM0008` when its header is; pixels that do not decode draw nothing. A picture of several frames is read, the first time it is laid out, for whether its first frame is blank and its last a flat mask (`AIMPSkinPixels.flags`), and that is kept after its pixels are let go |
| An AIMP 2 bitmap whose pixel offset overshoots (1,024 bytes too far in some of the catalog's) | read from the end of the file, where its pixels are |
| DPI variants (`-120`, `-144`, `-168`, `-192`) | never decoded; the 96-DPI image is used |
| `.myimg` (older skins, Sony TC-MR2) | filed as `.img`; an `.img` of the same name wins |
| `.lng` files | `@Lng:N;` captions read the Mac's first preferred language the skin has a file for (`AIMPSkinLanguage`, AIMP's file names), then `English.lng` caption by caption; a key neither has reads as empty (Delphi's `ReadString` default), never as raw `@Lng:` text |
| No form documents, a `main.ini` (AIMP 3.0, AIMP 2) | read by `AIMPSkinAIMP3` from `MainFrame.xml` and `main.ini`, or by `AIMPSkinAIMP2` from `main.ini` (version 3 also its `MainLayout.xml`); no layout is `AM0010` |
| A compiled script that does not decode or compile | left out with `AM0008`; `AIMP_RENDER_SCRIPTS` counts it as one that stops (`skin.scripts.unreadable`) |
| A script stored as Pascal source (some `.acs4` `.script`s) | not run, and not counted: the engine runs FastScript's compiled tree only |
| A dock site's frame document (`PlaylistFrame.xml`) malformed | an `AM0009` warning; the site is built as if it had none |
| A `.zip` holding two skins of one name (another folder or extension) | the first is installed, the rest left |
| A companion form missing or malformed | that window is left out; a malformed one is a warning |

## Confirm a change kept the gate

```bash
swift test --filter AIMPCorpusLoadTests
```

Confirm it took: `AIMP corpus: <n>/<n> loaded` and `0 failures`. A recorded `ok` skin that now throws
fails the suite by name (`reference/harness.md` § *The load gate and the census*).
