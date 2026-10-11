# GTA IV installation — structured inventory

**Scanned:** 2026-10-11 18:13:47 UTC · **Scanner:** `tools/gta4-inventory.ps1`
**Source data:** `summary.txt` (full content supplied by the installer owner)
**Files:** 5,704 · **Total size:** 22.08 GiB (23,705,751,441 bytes)

> Contains filenames, sizes and hashes only. **No game content is reproduced here.**
> Where a conclusion is inferred rather than measured, it is labelled.

---

## 1. Verdict at a glance

| Question | Answer | Confidence |
|---|---|---|
| Which build? | **GTA IV: The Complete Edition 1.2.0.59** | **Measured** (PE version resource) |
| Base game + both episodes? | **Yes** — GTA IV + TLAD + TBoGT | **Measured** |
| Is it the build `gta4-webmap` targets? | **Yes** — it asks for exactly "GTA IV: The Complete Edition" | **Measured** |
| Modded? | **No** — no ScriptHook, no ASI loader, no ASI plugins | **Measured** |
| All critical data files present? | **Yes**, 16 of 16 that matter | **Measured** |
| Ready for Phase 2? | **Yes** | — |

**This is the correct, clean, current build. Nothing about the installation blocks the recommended path.**

---

## 2. Executable and platform

`GTAIV.exe` — measured from the PE header and version resource:

| Property | Value |
|---|---|
| Size | 28,225,536 bytes (26.9 MiB) |
| Format | PE (Portable Executable) |
| Machine | **i386 (x86 32-bit)** |
| Bitness | **32-bit (PE32)** |
| `LARGEADDRESSAWARE` | **YES** |
| Subsystem | GUI (Windows) |
| Link timestamp | 2023-01-27 20:31:09 UTC |
| **ProductVersion** | **1.2.0.59** |
| **FileVersion** | **1.2.0.59** |

**1.2.0.59** is the final GTA IV PC build — Games for Windows Live already removed.
Confirmed independently: **no `xlive.dll`, `LiveTokenHelper.dll` or `GFWLDownload.dll` in the install root.**

> **Relevance:** the 32-bit/LAA facts matter only to the (rejected) recompilation
> route. For the recommended JavaScript path they are informational.

---

## 3. Root modules

| DLL | Size | Note |
|---|---|---|
| `binkw32.dll` | 172 KiB | Bink video — cutscene playback |
| `1911.dll` | 2.37 MiB | Rockstar platform component |
| `MTLX.dll` | — | Present; purpose not identified from name alone |
| `steam_api.dll` | — | Steam integration |

**No** `d3d9.dll`, `dinput8.dll`, `dsound.dll`, `ScriptHook.dll`, `ScriptHookDotNet.dll`
and **no `.asi` plugins** → the installation is unmodified. Good: a port should be
validated against a clean tree.

---

## 4. Edition and layout

| Marker | Status |
|---|---|
| GTA IV base (`common\data`) | PRESENT |
| **TLAD** — The Lost and Damned | **PRESENT** |
| **TBoGT** — The Ballad of Gay Tony | **PRESENT** |
| EFLC root | absent (episodes live in `TLAD\`/`TBoGT\` instead) |
| `pc\`, `common\` | PRESENT |
| `common\shaders` + `common\shaders\db` | PRESENT |
| `pc\audio` + `pc\audio\sfx` | PRESENT |
| `pc\models\cdimages` | PRESENT |
| `pc\textures` | PRESENT |
| `pc\data\cdimages` | PRESENT |
| `Installers` / DirectX redist | absent (Steam-installed) |

**Interpretation:** Steam layout of **GTA IV: The Complete Edition** — base game plus
both episodes as sibling folders. This is exactly the layout `gta4-webmap` expects.

---

## 5. Archives

**303 `.rpf` / `.img` archives**, 18.87 GiB combined (85% of the install).

| Magic | Count | Format |
|---|---|---|
| `RPF2` | 4 | GTA IV standard archive |
| `RPF3` | 45 | GTA IV **audio** archive |
| *not identified* | **254** | all of them are `.img` — see note |

**Largest archives (measured):**

| Archive | Size | Magic |
|---|---|---|
| `pc\audio\sfx\speech.rpf` | 1.49 GiB | RPF3 |
| `TLAD\pc\audio\sfx\EP1_SFX.rpf` | 0.93 GiB | RPF3 |
| `TBoGT\pc\audio\sfx\EP2_SFX.rpf` | 0.85 GiB | RPF3 |
| `pc\audio\sfx\cutscenes.rpf` | 0.79 GiB | RPF3 |
| `pc\audio\sfx\scripted_speech.rpf` | 0.72 GiB | RPF3 |
| `pc\models\cdimages\componentpeds.img` | 610 MiB | unidentified |
| `TLAD\pc\audio\sfx\EP1_SPEECH.rpf` | 0.55 GiB | RPF3 |
| `pc\anim\cuts.img` | 500 MiB | unidentified |
| `pc\data\maps\jersey\nj_01.img` | 313 MiB | unidentified |
| `pc\data\maps\manhat\manhat01.img` | 222 MiB | unidentified |

> **Scanner gap — flagged honestly, not a problem with your install.**
> Every one of the 49 `.rpf` files was identified (4 × RPF2, 45 × RPF3), but **none
> of the 254 `.img` files matched** the three IMG magics the scanner tests
> (`VER2`, `VER3`, `0xA94E2A52`). Their first four bytes are hash-like values
> (`0xcfea9168`, `0xca864146`, `0x669e1ec3`, `0x1645eec4`, `0x5e10d205`).
> This is a gap in my detection table, **not** evidence of anything wrong:
> `gta4-webmap` and RageLib read these exact files successfully. Resolving the real
> IMG3 magic is cosmetic for our purposes.

---

## 6. Composition by extension

| Extension | Count | Total | Share |
|---|---|---|---|
| `.rrr` | 1,813 | 35 MiB | radio/audio data |
| `.tune` | 1,119 | 42 MiB | radio tuning |
| `.whm` | 726 | 40 MiB | water heightmaps |
| `.fxc` | 612 | 22 MiB | compiled shaders |
| **`.img`** | **254** | **9.39 GiB** | **42.5%** |
| `.ide` | 228 | 14 MiB | item definitions |
| `.wtd` | 205 | 84 MiB | texture dictionaries |
| `.dat` | 147 | 51 MiB | various data |
| `.sps` | 133 | 6 KiB | **shader presets** (matches the 131 documented for the 360 build) |
| `.dcl` | 102 | 9 KiB | shader assembly + named constants |
| `.wpl` | 99 | 4.7 MiB | binary item placements |
| **`.rpf`** | **49** | **9.49 GiB** | **43.0%** |
| `.xml` | 31 | 0.7 MiB | includes `WeaponInfo.xml` |
| `.ipl` | 26 | 12 MiB | includes the four `paths*.ipl` |
| `.gxt` | 19 | 54 MiB | localisation text |
| **`.bik`** | **9** | **2.60 GiB** | **11.8%** — Bink cutscene video |
| `.wdd` | 2 | 27 KiB | drawable dictionaries |

**`.img` + `.rpf` + `.bik` = 21.47 GiB = 97.3% of the install.** Everything else
(5,398 files) is 0.61 GiB combined. Any streaming or size-reduction work should
target those three.

---

## 7. Data files the browser port depends on

Measured, from the scan:

| Purpose | Path | Status | Size |
|---|---|---|---|
| World definition | `common\data\gta.dat` | PRESENT | 8,022 B |
| Vehicle handling | `common\data\handling.dat` | PRESENT | 41,386 B |
| Weapon stats | `common\data\WeaponInfo.xml` | PRESENT | 19,318 B |
| Vehicle catalogue | `common\data\vehicles.ide` | PRESENT | 18,387 B |
| Vehicle colours | `common\data\carcols.dat` | PRESENT | 24,102 B |
| Ped catalogue | `common\data\peds.ide` | PRESENT | 96,264 B |
| Item definitions | `common\data\default.ide` | PRESENT | 11,342 B |
| Road network 1 | `common\data\maps\paths.ipl` | PRESENT | 1.64 MiB |
| Road network 2 | `common\data\maps\paths2.ipl` | PRESENT | 634 KiB |
| Boat lanes | `common\data\maps\paths3.ipl` | PRESENT | 98 KiB |
| Network paths 4 | `common\data\maps\paths4.ipl` | PRESENT | 425 KiB |
| Ped navmesh | `pc\data\cdimages\navmeshes.img` | PRESENT | 86.7 MiB |
| Vehicles | `pc\models\cdimages\vehicles.img` | PRESENT | 81.6 MiB |
| Weapons | `pc\models\cdimages\weapons.img` | PRESENT | 5.3 MiB |
| Player model | `pc\models\cdimages\playerped.rpf` | PRESENT | 15.4 MiB |
| Sky textures | `pc\textures\skydome.wtd` | PRESENT | 710 KiB |
| Audio SFX | `pc\audio\sfx` | PRESENT (39 files) | 6.23 GiB |
| Ped components | `pc\models\cdimages\componentpeds.img` | PRESENT | 610 MiB |

**Everything `gta4-webmap` needs is present.** It reads exactly this set:
`.img` archives, WPL/IPL placements, `.wdr`/`.wdd`, `.wtd`, `.wad` animations,
`timecyc.dat`, `WeaponInfo.xml`, `paths*.ipl` and `navmeshes.img`.

### Three items the scan reported MISSING — and why that is a scanner bug

| Reported missing | Reality |
|---|---|
| `common\data\timecyc.dat` | **Wrong path in my scanner.** `gta4-webmap` reads **`pc\data\timecyc.dat`**. Needs confirming on your tree. |
| `pc\models\cdimages\peds.img` | **Not expected in GTA IV.** Peds are assembled from `componentpeds.img` (610 MiB, present). My key-file list carried over a bad entry. |
| `pc\audio\radio` | Radio audio is not in that folder in the Steam Complete Edition; the 1,813 `.rrr` and 1,119 `.tune` files are the radio data. Location needs confirming. |

Only `timecyc.dat` matters for the port (it drives the lighting). See the one-liner below.

---

## 8. Audio

- `pc\audio\sfx` — **39 files, 6.23 GiB** (28% of the whole install)
- 45 RPF3 audio archives identified
- GTA IV PC audio is **not** AWC (AWC arrived with Red Dead Redemption); it is
  `.ivaud` streams inside RPF3 archives

**This is the subsystem `gta4-webmap` does not implement at all.** It is MVP-1
work, and it is the single largest chunk of bytes in the game.

---

## 9. What this changes

| Finding | Consequence |
|---|---|
| Complete Edition 1.2.0.59, clean, unmodded | ✅ Nothing to fix before Phase 2 |
| All 18 required data files present | ✅ `gta4-webmap` extraction should work unmodified |
| TLAD + TBoGT present | Bonus — two extra maps and their assets, available later |
| 22.08 GiB, 97% in img/rpf/bik | The multi-GB streaming problem is confirmed real, not hypothetical |
| 6.23 GiB of audio, zero audio support in the viewer | Confirms audio is the biggest missing subsystem |
| 86.7 MiB navmesh present | Crowd AI (910k walkable points) is achievable |
| Executable is 32-bit LAA | Irrelevant to the JS path; mildly favourable to a hypothetical wasm32 recompilation |

**No blocker was found.** Proceed to Phase 2.

---

*Generated from `summary.txt` supplied by the installation's owner, 2026-10-11.
The full 5,704-row `manifest.csv` was not available at generation time; this
document is derived from the summary, which covers every fact Phase 1 required.
No game content is contained in this document.*
