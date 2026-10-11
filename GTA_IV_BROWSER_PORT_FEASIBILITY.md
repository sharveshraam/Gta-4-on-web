# GTA IV Browser Port — Phase 1: Engine Discovery & Feasibility Investigation

**Report date:** 2026-10-11 (all repository "last activity" dates verified on this date via the GitHub REST API unless stated otherwise)
**Subject:** Is there a credible technical path to running *Grand Theft Auto IV* locally inside a desktop browser?
**Phase:** RESEARCH ONLY. No engine code was written, no game binary was executed, no game asset was downloaded or redistributed.

---

## 0. How this report was produced (verification method)

| Method | What it establishes |
|---|---|
| `gh api repos/…` (GitHub REST API) | Repository existence, language, license SPDX id, star/fork count, `pushed_at`, `created_at`, archived flag — **verified first-hand on 2026-10-11** |
| `git clone` of candidate repos | Actual file layout, README content, dependency manifests, subsystem inventory — **verified first-hand** |
| `fetch_page` on the primary technical write-up | Direct reading of the GTA V-in-browser technical analysis (12 chunks; chunks 0, 8, 11 read in full) |
| `web_search` | Third-party reporting, file-format documentation, browser-platform facts — **cited individually** |
| `gh api search/repositories` | Exhaustive-ish sweep for GTA IV / RAGE reimplementation projects |

**Explicit non-actions, per the safety constraints of this investigation:**
- No leaked or proprietary source code was searched for, retrieved, or used.
- No pirated game copy, no DRM-bypass material, no credentials were sought.
- **No game binary was executed.** File-format conclusions come from public documentation and from projects that already parse these formats.
- One GitHub repository surfaced by a general web search appears to contain the actual GTA IV executable and DLLs. It is deliberately **not named, linked, or used** in this report, and you should not use it as a source.

---

## 1. Executive summary

**Bottom line: EXPERIMENT — with a clearly identified first track. Do not attempt a "port the real GTA IV engine to WebAssembly" project.**

The single most important finding is that **a browser-native GTA IV world runtime already exists, is MIT-licensed, is actively maintained, and reads real GTA IV assets**: [`luckeyfaraday/gta4-webmap`](https://github.com/luckeyfaraday/gta4-webmap). It is not a game — it is a streaming Three.js/WebGL2 viewer with a playable third-person Niko, traffic, crowds, police, driving and combat built on top of the real map data. But it is, by a wide margin, the strongest foundation available, and it is already *in the browser*.

The second important finding is that **the GTA V browser demonstration is not a model you can follow**. It was built from Rockstar's own engine source with Rockstar's own game data, both unlicensed for that use, and it was taken down. Its architecture is instructive as *evidence of what browsers can do*; it is not a legal or practical template for GTA IV.

The third finding is that **static recompilation of GTA IV is real and working** — two independent projects (LibertyRecomp for desktop, Theft4 for ARM64 iOS) have the Xbox 360 build of GTA IV running with native renderers. This proves the game's code is recoverable, but neither project has a WebGPU/WASM backend, and both are GPL-3.0.

**Recommended first move (Phase 2):** fork `gta4-webmap`, reproduce its single-sector build locally, and extend it. This is the only path where the work is browser-native from day one, the licence is permissive, the asset posture is already correct (user supplies their own legally owned files), and the deploy target is plain static hosting with no cross-origin-isolation requirement.

**Hard NO-GO items:** running the retail Windows `GTAIV.exe` through any WASM x86/Wine compatibility layer; shipping or hosting any Rockstar asset; any path that depends on leaked source.

---

## 2. Verified analysis of the GTA V browser demonstration

### 2.1 What the demonstration was

`playgta5.com` appeared in early October 2026 and was taken down within days. Multiple outlets reported it as a WebAssembly port rather than cloud streaming, and reported that it was built from the previously leaked GTA V source code [1](https://businessupturn.com/technology/gta-v-is-suddenly-running-inside-chrome-viral-browser-port-shrinks-a-170gb-game-to-around-700mb-but-it-may-not-survive-for-long/) [2](https://www.talkesport.com/news/gaming/gta-5/play-gta-5-in-browser-playgta5-shut-down/). Nobody has published independently reproducible proof of the provenance claim; treat it as **unverified reporting**.

### 2.2 What the technical evidence actually shows

The most detailed independently produced analysis I could find is Satyajit Ghana's write-up [1](https://ai.thesatyajit.com/articles/gta5-in-the-browser), which states the author downloaded every file the site served, read all of its JavaScript, and ran the game headless. Its findings (dated October 2026):

| Claim | Evidence status |
|---|---|
| **It executes locally, not streamed** | **Verified by analysis.** The page serves a real engine binary; assets are fetched by HTTP Range into browser storage; there is no video stream. |
| `game.wasm` is **63,201,802 bytes**, ~91,000 named functions, RAGE + GTA V game code, compiled to **wasm64** | Verified by binary analysis. |
| Runs as ~75 threads on 64-bit shared memory; Emscripten pthread pool `min(160, 36 + 4 × cores)` | Verified by reading `game.js`. |
| **Graphics: it still issues Direct3D 11 calls**, captured into a 32 MB ring as 48 opcodes, replayed by a worker onto **WebGPU** | Verified. Graphics were *not* rewritten; a D3D11→WebGPU replay layer was written. |
| **Shaders translated ahead of time**: 4,919 DXBC shaders in → 4,808 usable WGSL out, 72 MB in 18 packs; 720 render-pipeline recipes precompiled | Verified. |
| **The game is 20.9 GB on the server and stays there.** The tab fetched a 582 MB "boot set" plus on-demand blocks; one session reached **743 MB** before the player could walk | Verified. **This directly refutes the "700 MB game" framing in the popular press.** |
| Assets fetched as **4 KB blocks via HTTP Range** into an append-only store in OPFS, with a manifest of 5,814 paths and a journal guarded by a magic + version | Verified. |
| Audio via an `AudioWorklet` reading interleaved float samples straight out of the engine's own linear memory | Verified. |
| Built from Rockstar's own C++ source | Stated by the analyst as their conclusion; **not independently verifiable and not something I attempted to verify.** |
| Site taken down | Reported by multiple outlets [2](https://www.talkesport.com/news/gaming/gta-5/play-gta-5-in-browser-playgta5-shut-down/); the exact mechanism (DMCA, host action, or voluntary) is **unconfirmed**. |

### 2.3 What this does and does not prove for GTA IV

**It proves (useful to us):**
- A modern browser can host a real, threaded, AAA-scale C++ engine at tens of MB of wasm.
- A D3D-command-replay + pre-translated-shader approach to GPU translation works.
- Range-request block fetching into OPFS is a viable asset-streaming strategy for a 20 GB-class game folder.
- WASM-64 with >4 GB heaps is real and shippable (Emscripten `MEMORY64`).

**It does not prove (do not carry over):**
- That GTA IV shares a reusable codebase with GTA V. **It does not.** GTA IV and GTA V are both "RAGE", but they are separated by seven years, a renderer rewrite (D3D9 vs D3D11), different archive versions (RPF2/3 vs RPF7), different model containers (`.wdr`/`.wft` vs `.ydr`/`.yft`), different script formats (`.sco` vs `.ysc`), and different physics/animation middleware generations.
- That a 63 MB wasm module is achievable without the original source. **It is not.** That module exists because the original C++ was available.
- That the project was lawful or durable. It was taken down [2](https://www.talkesport.com/news/gaming/gta-5/play-gta-5-in-browser-playgta5-shut-down/).

### 2.4 The correct reference model: the reVC / re3 browser port

Your second reference is the right one to copy, and it is a completely different architecture:

- [`joncodeofficial/gta-vice-city-wasm`](https://github.com/joncodeofficial/gta-vice-city-wasm) — MIT-licensed browser client. The user imports their own `game.tar.gz` (~668 MB compressed); a Web Worker extracts it to **OPFS**; a **Service Worker** then serves game files locally; the engine is **reVC/re3** (open-source reimplementation of the GTA III/VC engine) compiled to WASM with Emscripten, rendering on WebGL2. It runs fully offline after import and is deployed on GitHub Pages. Credits: browser client by @joncodeofficial, based on [reVCDOS](https://github.com/Lolendor/reVCDOS), engine from [re3/reVC](https://github.com/SugaryHull/re3/tree/miami) [1](https://github.com/joncodeofficial/gta-vice-city-wasm).
- **Legal precedent worth noting:** this lineage was DMCA'd. Take-Two had the DOS Zone hosting removed in 2025, and the same codebase resurfaced on another host in September 2026 [3](https://timesofindia.indiatimes.com/technology/gaming/take-two-shuts-down-browser-based-gta-vice-city-port-with-dmca-takedown-says-it-was-misleading-users/articleshow/126236663.cms) [1](https://technosports.co.in/vice-city-gta-returns-browsers/). The takedown targeted *the hosting of the game under the GTA name*, not the reverse-engineered code itself, which remains on GitHub. This is the single most likely failure mode for your project too. See §11.

**Key architectural lesson from reVC-wasm, and it is the one that matters most for you:** the engine ships as code, **the assets never ship**. The user supplies them, they land in OPFS, and gameplay is server-free thereafter. That is exactly the architecture your brief asks for, and it is the architecture `gta4-webmap` already uses.

---

## 3. GTA IV engine and file-format findings

### 3.1 The engine

| Property | Value | Source |
|---|---|---|
| Engine | **RAGE** (Rockstar Advanced Game Engine) | [PCGamingWiki](https://www.pcgamingwiki.com/wiki/Grand_Theft_Auto_IV) |
| Graphics API (PC) | **Direct3D 9.0c** only | [PCGamingWiki](https://www.pcgamingwiki.com/wiki/Grand_Theft_Auto_IV) |
| Executable | **32-bit** x86 (`GTAIV.exe`, `LaunchGTAIV.exe`). PCGW flags that 32-bit executables may need the LAA flag on modern machines | [PCGamingWiki](https://www.pcgamingwiki.com/wiki/Grand_Theft_Auto_IV) |
| Character physics / animation | **Euphoria** (NaturalMotion, Dynamic Motion Synthesis) — proprietary middleware, integrated into RAGE starting with GTA IV [1](https://gta.fandom.com/wiki/Euphoria) [3](https://en.wikipedia.org/wiki/NaturalMotion) | fandom / Wikipedia |
| Vehicle & rigid-body physics | Rockstar in-house RAGE solver. **`handling.dat` carries the tuning constants but not the solver**, so a reimplementation cannot recover the real vehicle model from the assets alone (observed directly in `gta4-webmap`) | `gta4-webmap` README, read first-hand |
| Video | Bink (`binkw32.dll`) | Observed in public install listings |
| Online/DRM | SecuROM + Games for Windows Live in early builds; **removed in the Complete Edition** | [PCGamingWiki](https://www.pcgamingwiki.com/wiki/Grand_Theft_Auto_IV) |
| Install size | ~22 GB (PCGW); retail/Complete listings vary ~16–32 GB | [PCGamingWiki](https://www.pcgamingwiki.com/wiki/Grand_Theft_Auto_IV) |
| PC patch lineage | 1.0.0.4 → 1.0.1.0 → 1.0.2.0 → 1.0.3.0 → 1.0.4.0 → 1.0.5.0 → 1.0.6.0 → 1.0.7.0 → 1.0.8.0 → Complete Edition 1.2.0.x (2020-03-19 update removed GFWL) [1](https://gta.fandom.com/wiki/Grand_Theft_Auto_IV/Title_Update_Notes) | fandom |

**Why Euphoria matters:** GTA IV's signature character behaviour — procedural staggers, grabs, balance recovery, ragdolls — is not in the assets. It is licensed middleware whose source you cannot obtain. Any reimplementation will produce *different* character physics. This is a permanent, unfixable fidelity gap, and it must be stated rather than papered over.

### 3.2 GTA IV file formats (publicly documented)

Archive and resource formats, per [GTAMods Wiki](https://gtamods.com/wiki/RPF_archive) and the GTA IV category index:

| Extension | Role |
|---|---|
| `.rpf` **RPF2** (`0x52504632`) | Main archive container. Header carries TOC size, entry count, encryption flag; TOC begins 2048 bytes in and is encrypted when flagged; per-file entries are name-offset / size / 24-bit offset / resource-type / flags. Payloads are raw zlib without a deflate header when compressed [1](https://gtamods.com/wiki/RPF_archive) |
| `.rpf` **RPF3** (`0x52504633`) | GTA IV **audio** archives (and Midnight Club: LA) [1](https://gtamods.com/wiki/RPF_archive) |
| `.img` (IMG3) | Archive format used for `vehicles.img`, `weapons.img`, `navmeshes.img` |
| `.wdr` / `.wdd` | Drawable / drawable-dictionary: map models, weapon models, player parts. Header block 0x2A0 with vtable, shader-group offset, skeleton offset, bounds, model collection, LOD model pointers, 2DFX array [2](https://gtamods.com/wiki/WDR) |
| `.wft` | Fragment models (parent drawable + skinned child pieces bound to skeleton bones) |
| `.wtd` | Texture dictionary (`pgDictionary`); keyed on bare leaf name with no extension |
| `.wbd` / `.wbn` | Collision — bound geometry / bound dictionary |
| `.wpl` | Binary item **placement** (the binary successor to `.ipl` instances; Xbox equivalent `.xpl`, PS3 `.cpl`) [5](https://gtamods.com/wiki/WPL) |
| `.ipl`, `.ide` | Text item placement and item definitions (`objs`, `tobj`, `anim`, `mlo`, `txdp` sections) |
| `.sco` | **Compiled RAGE script / mission bytecode** |
| `.wad` | Animation dictionary (`move_cop.wad`, movement sets) |
| `.nod`, `.rrr`, `.gxt`, `.dat`, `.whm` | Vehicle nodes, radio, localisation text, data tables, water heightmaps |

**Audio:** GTA IV PC audio is *not* AWC. AWC arrived with Red Dead Redemption. GTA IV stores sound in **RPF3 archives under `pc/audio/` as `.ivaud` streams** — historically exported via SparkIV/OpenIV [4](https://gtaforums.com/topic/391675-gta4-converting-the-rpf-radios-to-wav-or-mp3/) [5](https://www.se7ensins.com/forums/threads/so-we-can-edit-animal-noises-and-other-sounds.1316231/). RageLib (see §4) ships an `Audio/` namespace with `AudioFile`, `AudioWave` and a `SoundBank` folder, so a C# reference reader exists.

**Scripts / missions:** `.sco` compiled RAGE scripts. RageLib ships a `Scripting/` namespace (`ScriptFile.cs`, `HLScript/`, `Output/`) — i.e. a script parser and high-level-code output path exists in C#. A separate community repository publishes decompiled GTA IV mission scripts under the Unlicense: `0x52617665/GTAIVMissionScripts` (15–25 stars, last push 2020-11-26 — **stale, treat as a reference only**).

**Shaders:** GTA IV stores precompiled shaders in `.fxc` containers plus **plain-text `.sps` shader preset files** under `common/shaders/db/` (131 `.sps` files, 89 `.fxc` files in the Xbox 360 build), per LibertyRecomp's `docs/SHADER_PIPELINE.md` (read first-hand). `common/shaders/dcl` ships the atmosphere shader's assembly with constants named — `gta4-webmap` used exactly this to reconstruct the sky.

### 3.3 GTA IV file analysis — **NOT PERFORMED: no files were accessible**

**This is a gap you must close before Phase 2 can be more than a paper study.**

Your brief had a placeholder where the game files should be:

> `[INSERT GOOGLE DRIVE LINK, LOCAL FILE PATH, OR REPOSITORY URL]`

No link, path, or repository was provided. I therefore inspected **nothing**, and I make **no claim** about your specific installation — its version, its integrity, its archives, or its contents.

**What I cannot conclude without access:**
- Exact executable/build version and patch level
- Whether `GTAIV.exe` is LAA-enabled
- Actual archive inventory, sizes and encryption state
- Whether the install is GTA IV standalone, EFLC, or Complete Edition
- Whether any required file is missing
- Actual asset totals

**"But the install is 22 GB — how do I provide it?"**

**You don't, and you shouldn't. Send a text inventory instead.** Every question Phase 1 actually needs to answer — *which build is this? is the executable 32-bit? is it LAA? which archive versions are present? is `paths2.ipl` there? how many `.rpf` files and how big?* — is answered by **filenames, file sizes and a few header bytes**. None of it needs file contents.

I have written the scanner so this is one command. See **[`tools/README.md`](tools/README.md)** for the full guide; in short:

```powershell
# Windows — auto-detects the Steam install
powershell -ExecutionPolicy Bypass -File .\tools\gta4-inventory.ps1

# or give the path explicitly (the folder containing GTAIV.exe)
powershell -ExecutionPolicy Bypass -File .\tools\gta4-inventory.ps1 `
  -GameDir "C:\Program Files (x86)\Steam\steamapps\common\Grand Theft Auto IV\GTAIV"
```

```bash
# Linux / macOS (Proton, CrossOver, …)
chmod +x tools/gta4-inventory.sh && ./tools/gta4-inventory.sh
```

It writes **`tools/gta4-inventory/`** — about **1 MB of text**, i.e. ~0.005% of the install:

| File | Contents |
|---|---|
| `summary.txt` | PE format/machine/bitness/`LARGEADDRESSAWARE`/link timestamp/ProductVersion; DLL inventory; `.rpf`/`.img` magic numbers; per-extension counts and sizes; edition markers (`TLAD`/`TBoGT`/`EFLC`); presence of every data file the port depends on |
| `tree.txt` | Directory tree, two levels, with counts and summed sizes |
| `manifest.csv` | `relative_path, size_bytes, sha256` for every file |

Then paste `summary.txt` into chat (~5 KB), or commit the whole folder — it is plain text with no game content.

**Options ranked:**

1. **Inventory (best).** One command, no content transfer, answers everything Phase 1 asks. **This is what I recommend.**
2. **Skip the paperwork and run Phase 2.2.** Install Node 22+ and .NET 8, clone `gta4-webmap` **inside** the game directory (its extractors resolve the parent as the game root: `…/Grand Theft Auto IV - The Complete Edition/_webmap/`), run `./setup.ps1` → `npm run extract` → `npm run serve`, and report what you see at `http://127.0.0.1:4174`. That single test yields more signal than any manifest.
3. **A repository URL containing only the manifest.** Fine. Never the assets.
4. **Google Drive:** not reachable from this environment, and I would not download game content from it regardless.

**Do not** zip and upload the install, `git add` the game folder, commit `web/assets/` or `web/data/` (those are derived works), or send a local path — **my sandbox cannot see your disk**, which is precisely why the scanner exists.

**Scanner safety:** read-only (opens files, reads the first 4–16 bytes, closes them); never writes to the game directory; **executes nothing**; the root path is **redacted** from all output so your username and drive layout do not leak; the only file-derived data emitted is SHA-256 hashes and 4-byte format magics.

**I will not execute `GTAIV.exe`** — not to identify it, not to profile it. Static inspection only (PE header reads, hash manifests, archive magic bytes). This is both a security posture and a licensing posture.

---

## 4. Existing projects and their actual capabilities

Verified on 2026-10-11 via the GitHub REST API and by cloning each repository.

### 4.1 ★ `luckeyfaraday/gta4-webmap` — **the primary candidate**

| Field | Value |
|---|---|
| URL | https://github.com/luckeyfaraday/gta4-webmap |
| Purpose | "Liberty City browser map: unofficial local Three.js viewer and extraction pipeline for a legally installed copy of GTA IV." |
| Language / stack | **JavaScript + Three.js 0.185.1 (WebGL2)**, browser; extractor in **C#/.NET 8** + Node.js tooling; PowerShell driver scripts |
| Licence | **MIT** on original code — with an explicit, well-drafted `ASSET_NOTICE.md` disclaiming any licence over Rockstar assets |
| Stars / activity | 3 stars; **last push 2026-10-10** (very active; commits through Sept 2026) |
| Loads real GTA IV assets? | **Yes.** Reads `.img` archives, WPL/IPL placements, `.wdr`/`.wdd` models, `.wtd` texture dictionaries, `.wad` animations, `timecyc.dat`, `WeaponInfo.xml`, `paths*.ipl`, `navmeshes.img` |
| Gameplay? | **Partial — genuinely playable free-roam, but not the game** |

**What it actually does** (measured from the README and the source I cloned):

- **World:** all **34 outdoor sectors** of Liberty City (Manhattan, Broker/Dukes/Bohan, Alderney) exported as instanced, Meshopt-compressed glTF, streamed per-sector. Baked prelighting is preserved from `COLOR_0`.
- **Rendering:** a deliberate draw-call-collapsing design (WebGL2 `sampler2DArray` texture arrays + `BatchedMesh`). Measured on an AMD iGPU at 1440×900: **3,590 → 88 draw calls; ~3,500 shader programs → 2; 32.7 ms → 3.4 ms render time; 2,838 → 19 requests to first render.**
- **Lighting:** driven by the game's own `timecyc.dat` (9 weathers × 11 keyframes); sun direction reconstructed from the `SunMult` column; sky drawn with GTA IV's own `gta_atmoscatt_clouds` shader reverse-engineered from `common/shaders/dcl`; colour grade and bloom ported.
- **Player:** Niko as a skinned, animated glTF with his own skeleton, textures and 62 clips. Third-person walk mode with an animation state machine (`idle/walk/run/sprint`, `jump_takeoff → jump_inair → jump_land`), sprint, walk, jump, first-person toggle, orbiting camera with collision.
- **Vehicles:** all **127** traffic vehicles (19 MB), paint from `carcols`, wheels rolled from distance travelled, spawn weighted by `vehicles.ide` `Frq`/`MaxNum` (95 models in the ambient rotation).
- **Pedestrians:** **343** ambient peds over a shared library of **112** locomotion clips (30 MB + 51 MB textures).
- **Traffic:** real road network from `paths*.ipl` — **24,602 nodes, 24,568 edges, 1,440 junctions**, median segment 8 m. Includes the genuinely non-obvious finding that a node chain is one *carriageway*, not a road centreline.
- **Crowd AI:** ped navmesh reverse-engineered from `navmeshes.img` — **910,402 walkable points in 3.5 MB** from 3,600 tiles, with three independent correctness checks documented. RageLib has **no `.wnv` reader**, so this format was worked out from scratch.
- **Wanted system + police:** six-star heat model (continuous heat, stars as display, sighting-gated cooling), priced offences, officer and cruiser response drawn from units the ambient systems hold back.
- **Driving:** enter/exit, chase camera, constants sourced from `handling.dat`. **Explicitly an arcade model** — no suspension, no weight transfer, no tyre model.
- **Weapons/combat:** pistol, M4, RPG with behaviour read verbatim from `WeaponInfo.xml`; 141 animation clips; additive upper-body layering over armed locomotion.

**What it explicitly does NOT have** (verified by grepping the entire `web/` tree — zero hits for `audio`, `sound`, `radio`, `save`, `mission`, `interior`, `mlo`):

- **No audio at all.**
- **No missions, no `.sco` script execution.**
- **No interiors / MLO support.**
- **No save system.**
- **No Euphoria-class character physics** (hand-animated state machine + procedural twist/leg-IK instead).
- **No real vehicle physics.**
- **Outdoor sectors only.**

**Licensing caveat you must plan for:** the repo is MIT, **but its extractor builds against RageLib sources vendored inside `Infinity-Loops/GTA4Unity`, which is GPL-3.0.** The maintainers handle this by cloning GTA4Unity into a gitignored `converter/` directory at build time rather than vendoring it. That is a defensible separation for a build-time tool, but if you fork this project you inherit the question. See §11.

**Platform caveat:** the extraction pipeline is **Windows-only** (PowerShell scripts, `.ps1`, plus .NET 8). The *viewer* is plain static JS and runs anywhere. If your development machine is Linux or macOS, you will need to port `extract-*.ps1` + the Node/C# glue before you can generate assets.

### 4.2 `Infinity-Loops/GTA4Unity` — the upstream asset library, and a Unity world loader

| Field | Value |
|---|---|
| URL | https://github.com/Infinity-Loops/GTA4Unity |
| Purpose | "Open source reimplementation of GTA IV game engine in Unity" |
| Language / stack | **C#**, **Unity 6 (6000.4.0f1+)**, URP Forward+, **Entities / ECS** + `BatchRendererGroup` |
| Licence | **GPL-3.0** (this applies to the whole repo, including the vendored RageLib) |
| Stars / activity | 15 stars, 9 forks; **last push 2026-05-06** (~5 months stale as of this report) |
| Loads real GTA IV assets? | **Yes** — IMG archives, `.wdr`/`.wft`, `.wtd`, WPL/IPL, IDE, water, MLO interiors |
| Gameplay? | **No.** |

**Contents (from the clone):** 357 C# files. `Assets/Scripts/RageLib/` — 500 files, a full RAGE format library covering `Animation`, `Audio` (+`SoundBank`), `Collision` (`PhBound`, `PhBoundComposite`, `PhPolygon`), `FileSystem` (`RPF`, `IMG`), `Models`, `Shaders`, `Scripting`, `Textures`. Plus `IVUnity.ECS/` world streaming (200K+ entities, `Dormant → Pending → Loading → Loaded → Unloading`), LOD fading, MLO interiors, fragment models, ped animation (`PedAnimationSystem`, `PedMoveBlendTree`, `PedTwistSolver`, leg IK), and `IVUnity.Physics/` (`RageMeshCollider`, `LinearBvhBuilder`) reading `.wbn` collision.

**Status statement in its own README:** *"World geometry, textures, LOD streaming, MLO interiors, and fragment models load and render correctly. Not a complete game - no physics, vehicles, peds, or gameplay yet."* — Note that this line is **stale relative to the code**: ped animation, leg IK, twist solvers, collision parsing and physics layers have since landed. Treat the README's status section as out of date and the source as authoritative: it is a **world loader with early character systems**, not a game.

**Do not call this a playable engine.** There are no vehicles, no gameplay loop, no audio runtime, no mission scripts.

### 4.3 `OZORDI/LibertyRecomp` — static recompilation of the Xbox 360 build (desktop)

| Field | Value |
|---|---|
| URL | https://github.com/OZORDI/LibertyRecomp |
| Purpose | "An unofficial PC port of the Xbox 360 version of Grand Theft Auto IV created through the process of static recompilation" |
| Language / stack | **C++ (C++23, Clang 18+, CMake 3.29+, Ninja)**; SDL3; **Vulkan** (volk, VMA, MoltenVK on macOS), D3D12 on Windows, Metal on macOS; FSR/DLSS/SMAA; FFmpeg; ~13,348 tracked files |
| Licence | **GPL-3.0** |
| Stars / activity | 300 stars, 32 forks; created 2025-12-13; **last push 2026-09-23**; repo size ~1.1 GB |
| Loads real GTA IV assets? | **Yes** — requires an Xbox 360 ISO, extracted folder, or XContent package |
| Gameplay? | **Reported yes — with caveats.** |

**Status:** the README says *"in early development and is NOT meant for public use"* and is a fork of the MarathonRecomp framework, using the ReXGlue SDK for PowerPC→C++ translation and Xenos shader translation. Completed items listed: cross-platform build (Windows/Linux/macOS), installer wizard, shader extraction pipeline, audio (XMA decoder, SDL2), save data, input remapping, VFS/RPF handling, network/multiplayer stubs. In progress: RAGE engine structure RE, GPU/rendering pipeline, game-specific patches.

However, the **commit log contradicts the "early development" framing**: Sep 2026 commits include *"Implement native temporal rendering"*, *"Restore renderer and input improvements; stabilize pacing and replay state"*, *"Fix macOS build targeting and portable app packaging"*, *"Document GTA IV collision aliasing fix"*. This is a functioning renderer, not a stub.

**Renderer reality check (from `docs/BUILDING.md` and `docs/SHADER_PIPELINE.md`, read first-hand):** the desktop build targets **D3D12 / Vulkan / Metal**, with shaders pre-compiled at build time into DXIL / SPIR-V / AIR caches embedded in the binary (1,132 shader cache entries; the AIR cache alone is 8 MB compressed → 29 MB). Linux requires a Vulkan driver. **There is no WebGPU or WASM backend of any kind.**

**Relevance to a browser port:** this is the only project that runs *actual GTA IV game code* on a non-Microsoft platform. It is therefore the only route to "the actual game, including missions". But:
- It is **GPL-3.0** — a browser build would have to be GPL-3.0 too, and you'd owe source to users.
- It is a **recompilation of code you did not write**, which compounds the legal exposure rather than reducing it.
- Static recompilation output is host-specific: it assumes a 32-bit guest address space mapped into host memory, direct pointer arithmetic, and a native GPU API. Retargeting to `wasm32` is not a flag; it is a new backend (memory model, threading, file I/O, audio, and above all the GPU layer).
- Shader translation currently ends at DXIL/SPIR-V/AIR. **WGSL is a new target.**

### 4.4 `KoreanSeats1/Theft4` — static AOT recompilation for ARM64 iOS

| Field | Value |
|---|---|
| URL | https://github.com/KoreanSeats1/Theft4 |
| Purpose | "Experimental static AOT recompilation of GTA IV's Xbox 360 build for ARM64 iOS and iPadOS" |
| Language / stack | C++; **direct Metal renderer** (0.3 replaced the Vulkan→MoltenVK route) |
| Licence | **GPL-3.0** |
| Stars / activity | 70 stars; created 2026-09-15; **last push 2026-10-09** — the most recently active GTA IV project of any |
| Gameplay? | **Reported yes.** |

**Status (0.3.1, Oct 2026):** a signed, sideloadable IPA is published. The README reports build 123 passing 34 launcher/build tests, 27 CPU contracts, 45 GPU graphics cases plus 32 saved draw replays in each of two configurations; a tested native run at 2416×1359; *"excellent visuals and a major native-resolution performance improvement, with a remaining spike that recovers."* It is explicit that **"Locked 30 FPS across every scene/device is not established."** It credits LibertyRecomp and the ReXGlue SDK as its foundation. It also publishes an unusually detailed engineering record (`THEFT4_0.3_ARCHITECTURE.md`, per-build notes, CPU/GPU performance audits) including a stated goal of *"a source-backed record of the rewritten boundaries … for future ports."*

**Why it matters to you:** it is proof that a *new, hand-written GPU backend* can be substituted into a GTA IV static recompilation — which is precisely the kind of work a WebGPU backend would require — and it documents the boundaries. But it is Metal, on iOS, GPL-3.0, and built on a recompilation.

### 4.5 Other projects checked

| Project | Language / Licence | Last push | Verdict |
|---|---|---|---|
| `ThirteenAG/GTAIV.EFLC.FusionFix` | C++ / GPL-3.0, 3,381★ | 2026-10-09 | **Not an engine.** The definitive GTA IV PC bugfix/RE knowledge base. An indispensable *reference* for RE work on `GTAIV.exe`; not a port target. |
| `dexyfex/CodeWalker` | C# / **no licence declared**, 760★, 332 forks | 2025-04-11 | GTA V world viewer/editor. Its `RpfFile.cs` is the de-facto public RPF reference. **No declared licence → do not copy code.** |
| `VIRUXE/rpf-archive-rs` + `VIRUXE/rage-cli` | Rust / **Unlicense**, 9★ and 28★ | 2026-09-20 / 2026-10-02 | Clean-room Rust RPF0–RPF8 + IMG readers and a RAGE CLI (RSC7 resources, textures, navmeshes). Historically had a **wasm glTF export** path. **Unlicense = maximum freedom.** The best-licensed option if you need a fresh, WASM-compilable asset layer. |
| `Cathering/SparkAll` (fork of Spark IV) | C# | — | Legacy RAGE archive editor. Historical reference for RPF2/RPF3 and `.ivaud`. |
| `Cleolibrary/CLEO-Redux` | Rust / NOASSERTION, 282★ | 2026-09-26 | Script host for 3D-era GTA **and GTA IV**. Useful if you attempt script-level modding; not a runtime. |
| `0x52617665/GTAIVMissionScripts` | Unlicense, 22★ | 2020-11-26 | Decompiled GTA IV mission scripts. **Stale (6 years)**. Reference only — useful for understanding `.sco` semantics and mission structure. |
| `luisxl15/GTA-IV-RECOMP-XBOX-360` | Python / none, 33★ | 2026-08-08 | Empty (repo size 42 KB, no description). No evidence of substance. |
| `Hochgeschwindigkeitsrennfahrer/Grand-Theft-Auto-IV-VR-Mod` | C++ / MIT | 2026-08-14 | WIP SteamVR mod. Narrow scope. |
| `GTA-Network/IV-Network` | C++ | 2016-10-19 | **Abandoned (10 years).** |
| `Swoorup/paths-visualizer` | Python | 2019-12-16 | Abandoned Blender addon. |

**Sweep result:** GitHub searches for `gta iv reimplementation`, `gta iv decompilation`, `rage engine reimplementation`, and `gta4 wasm` returned **no additional credible engine projects** beyond those above. `gta4 wasm` returned zero repositories. There is **no existing re3/reVC-equivalent open-source GTA IV engine.**

### 4.6 Capability matrix

| | gta4-webmap | GTA4Unity | LibertyRecomp | Theft4 | reVC-wasm (GTA III/VC) |
|---|---|---|---|---|---|
| Browser-native | **Yes** | No (Unity) | No | No | **Yes** |
| Permissive licence | **MIT** | GPL-3.0 | GPL-3.0 | GPL-3.0 | **MIT** |
| Reads real assets | **Yes** | **Yes** | **Yes** | **Yes** | **Yes** |
| Renders world | **Yes** | **Yes** | **Yes** | **Yes** | Yes |
| Interiors | No | **Yes** | **Yes** | **Yes** | Yes |
| Playable character | **Yes** | Partial | **Yes** | **Yes** | Yes |
| Vehicles / driving | **Yes (arcade)** | No | **Yes** | **Yes** | Yes |
| Pedestrians / traffic | **Yes** | No | **Yes** | **Yes** | Yes |
| Real vehicle physics | No | No | **Yes** | **Yes** | Yes (reimplemented) |
| Euphoria-class peds | No | No | **Yes** | **Yes** | n/a |
| Weapons / combat | **Yes** | No | **Yes** | **Yes** | Yes |
| Missions / scripts | No | No | **Yes** | **Yes** | Yes |
| Audio | **No** | No (reader only) | **Yes** | **Yes** | Yes |
| Saves | No | No | **Yes** | **Yes** | Yes |
| Builds on Linux | Viewer yes / **extractor no** | Unity editor (yes) | **Yes** | No (iOS) | Yes |
| Public activity 2026-10 | **Yes** | Stale (May) | **Yes** (Sep) | **Yes** (Oct) | Yes |

---

## 5. Comparison of potential implementation approaches

### A. Port an existing GTA IV engine implementation to WebAssembly

**Classification: HIGH RISK** (borderline BLOCKED).

There is no open-source GTA IV *engine* to port. The only implementations that run real game code are LibertyRecomp and Theft4, both static recompilations of the Xbox 360 binary, both GPL-3.0, both with native GPU backends (Vulkan/D3D12/Metal) and no WASM target.

| Dimension | Assessment |
|---|---|
| Required source | Generated C++ from a PowerPC recompiler. Not clean-room; provenance is a recompilation of a proprietary binary. |
| Assets | User-supplied Xbox 360 ISO/extract. |
| Rendering | New WebGPU backend required. Shader pipeline currently ends at DXIL/SPIR-V/AIR; **WGSL is a new target** for 1,132 shader entries. |
| Physics | Recompiled guest code — works, but ~32-bit guest addressing and heavy pointer arithmetic must survive in wasm32. |
| Threading | Recompiled code + RAGE's job system assumes many blocking OS threads. Requires Emscripten pthreads with a pre-spawned worker pool and **cross-origin isolation (COOP/COEP)**. |
| Memory | The guest is a 512 MB-console game; wasm32's 4 GB ceiling is probably survivable, but a 63 MB-class module link is memory-hungry at build time. |
| Effort | Very large (multi-person-year). |
| Blockers | GPL-3.0; no WASM backend; no WGSL shader target; legal compounding (recompilation + browser distribution). |

### B. Adapt an existing GTA IV engine reimplementation

**Classification: EXPERIMENTAL** — this is the recommended track, but be precise about what "reimplementation" means here.

`gta4-webmap` is a *partial* reimplementation that already runs in a browser. GTA4Unity is a more complete *asset layer* (GPL-3.0, Unity, and no gameplay). The realistic play is: **take gta4-webmap's viewer, and borrow GTA4Unity/RageLib's format knowledge** to extend coverage (interiors, audio, scripts) — while being careful about the licence boundary (§11).

| Dimension | Assessment |
|---|---|
| Required source | MIT viewer + your own additions. Format knowledge from RageLib (GPL, use as build-time reference) or the Unlicensed Rust stack. |
| Rendering | **Already solved** for outdoors at good performance (88 draw calls, 3.4 ms). Needs: interiors/MLO, more shader families, and eventually a WebGPU path. |
| Physics | **The main gap.** Arcade vehicle model only. RageLib can read `.wbn`/`.wbd` collision; a rigid-body/vehicle solver must be written or integrated (e.g. Rapier/Cannon compiled to WASM, or a custom solver). |
| Audio | **Not started.** RPF3 + `.ivaud` reader needed (RageLib `Audio/` is a C# reference); then WebAudio mixing, plus radio streaming. |
| AI / scripts | Crowd + police + traffic exist but are hand-written approximations. **Missions require a `.sco` interpreter/VM — a major, multi-month subsystem.** |
| Threading | Currently single-threaded JS. Streaming and extraction can move to Workers without COOP/COEP. |
| Effort | Large but tractable in stages. |
| Blockers | Vehicle feel (no Euphoria, no RAGE solver — unreachable fidelity); missions; audio; Windows-only extraction pipeline. |

### C. Build a browser runtime around an existing engine or compatibility layer

**Classification: HIGH RISK for Unity; BLOCKED for Windows emulation.**

- **Unity (GTA4Unity → Unity WebGL build).** Technically Unity 6 can target WebGL/WASM. Against it: **GPL-3.0** on the project code; Unity's own licence terms; Unity WebGL is a heavyweight, large-download runtime; a 200K-entity ECS world with 20 GB of streamed assets is a poor fit for Unity's WebGL asset pipeline; and you would still have to write all the gameplay that doesn't exist. **Recommend against.**
- **Godot / Bevy / custom C++ + Emscripten.** A cleaner slate than Unity and genuinely viable, but you would be rebuilding what `gta4-webmap` has already built, in a harder environment (compile times, no hot reload, COOP/COEP if threaded). Only worth it if you need native-level performance for a physics solver.

### D. Reimplement the minimum necessary GTA IV engine systems from documented formats + legally obtained assets

**Classification: EXPERIMENTAL — this is what you would actually be doing**, and it is the honest description of the recommended plan. Formats are documented well enough (§3.2) for a partial reimplementation; the undocumented parts (vehicle solver, Euphoria, `.wnv`) are either approximated or reverse-engineered. Note that `gta4-webmap` already had to reverse-engineer `.wnv` from scratch because RageLib has no reader for it — expect more of that.

### E. Limited browser prototype preserving a path to the full game

**Classification: PROMISING. This is the recommendation.**

Build on `gta4-webmap`. It already satisfies most of your MVP wish-list and its gaps are individually addressable:

| MVP item | Status in gta4-webmap |
|---|---|
| Actual GTA IV world | **Done** (34 outdoor sectors, real assets) |
| Walking | **Done** (Niko, third person, real animations) |
| Driving | **Done** (arcade physics, real handling constants) |
| Vehicle physics | **Partial** — arcade only |
| Missions | **Absent** |
| Pedestrians | **Done** (343 peds) |
| Traffic | **Done** (real road graph) |
| AI / interactions | **Partial** (greedy navmesh pursuit; no planning) |
| Audio | **Absent** |
| Input | **Done** (keyboard + mouse; no gamepad) |
| Saves / config | **Absent** |
| Browser-local, no streaming server | **Done** |
| User-provided assets | **Done** (extract locally; never shipped) |
| Static hosting, offline single-player | **Done** |

### F. Windows compatibility layer (Wine / Boxedwine / v86) in the browser

**Classification: BLOCKED.**

[Boxedwine](https://github.com/danoon2/Boxedwine) (GPL-2.0) is the main attempt: an unmodified 32-bit Wine over an emulated Linux kernel and an interpreted x86 CPU, compiled to WASM [1](https://github.com/danoon2/Boxedwine). Its own README states: **"Emscripten/Web Boxedwine is still slow, need to implement a JIT"** and **"Games after the year 2010 have limitted success at running."** A hosting service built on it states Wine speed is **10–40% of native** and that the WASM build is interpretation-only [1](https://exebrowser.com/). Real-world reports for a 2001 title on Boxedwine/WASM: **0.4–0.7 fps** [3](https://www.tribesnext.com/forum/discussion/4335/boxedwine-as-a-path-to-running-tribes-2-in-a-web-browser).

GTA IV (2008, D3D9, 1.5 GB RAM minimum, multi-threaded) is orders of magnitude heavier than that. Additionally: Wine's D3D9→OpenGL translation would have to survive a second translation to WebGL/WebGPU; there is no JIT in WASM builds; and there is no plausible path to acceptable performance. **Do not pursue.**

### Why you cannot just "compile the Windows .exe to WebAssembly"

This deserves a direct answer, because it is the most common misconception:

1. **WASM is not x86.** It is a different instruction set with a different memory model. A PE binary contains x86 machine code, which WASM cannot execute. You need the C/C++ *source* and a compiler that targets WASM.
2. **Even with source, the platform calls don't exist.** WASM has no Win32, no Direct3D, no XAudio2, no Win32 file handles, no `CreateThread`. Every OS boundary needs a replacement. This is exactly why the GTA V port needed a bespoke D3D11→WebGPU replay worker, an HTTP/OPFS file worker, and an AudioWorklet — three hand-written subsystems — *on top of* having the source.
3. **The libraries are binary.** `binkw32.dll`, `xlive.dll`, `d3d9.dll`, `d3dx9_*.dll` and the Euphoria runtime are closed-source x86 binaries. They cannot be recompiled, only reimplemented or substituted.
4. **Threading is not free.** Blocking worker threads over shared memory require `SharedArrayBuffer`, which requires cross-origin isolation (COOP/COEP headers), which many static hosts cannot set.
5. **32-bit helps and hurts.** GTA IV being 32-bit is convenient (it maps naturally onto `wasm32`), but the 4 GB address ceiling and the need to reimplement every OS API remain.
6. **Legal.** Decompiling or recompiling a retail binary you don't own the rights to, and publishing it, is a separate and serious problem on top of the technical one.

---

## 6. Recommended architecture

### Guiding principle

**Engine code ships. Assets never ship.** The user imports files they own; everything stays on their device. This is the reVC-wasm model, it is already what `gta4-webmap` does, and it is the only posture that is both defensible and compatible with static hosting.

### Proposed architecture

```
┌─ BUILD TIME (on the user's machine, offline, Windows today) ────────────┐
│  GTA IV: Complete Edition install  ──►  extractor (Node + .NET 8)       │
│    .img/.rpf → .wdr/.wft/.wtd/.wad/.wbn → glTF + texture arrays        │
│    timecyc.dat, paths*.ipl, navmeshes.img, WeaponInfo.xml → JSON        │
│  Output: a single user-local bundle (never committed, never uploaded)   │
└────────────────────────────────────────────────────────────────────────┘
                                  │
                    user drops bundle / folder onto the page
                                  ▼
┌─ RUNTIME (browser, static host, zero server logic) ────────────────────┐
│  Main thread      Three.js WebGL2 renderer (→ WebGPU later)            │
│                   game loop, player controller, HUD                    │
│  Worker: streamer sector load/unload, glTF decode, texture arrays      │
│  Worker: AI       traffic (road graph), crowd (navmesh), police        │
│  Worker: physics  rigid bodies + vehicle solver (WASM, later)          │
│  Web Audio        SFX graph + radio streaming (later)                  │
│  OPFS             extracted assets, persisted; Service Worker serves   │
│  localStorage     settings; OPFS/IDB for save games (later)            │
└────────────────────────────────────────────────────────────────────────┘
```

### Design decisions, with reasons

1. **Start on WebGL2, not WebGPU.** `gta4-webmap` already achieves 88 draw calls / 3.4 ms on WebGL2 with texture arrays. WebGPU is now broadly available — Chrome/Edge 113+, Firefox 141+ (Windows) and 145+ (macOS ARM64), Safari 26 [1](https://web.dev/blog/webgpu-supported-major-browsers) — but Firefox Linux/Android is still in progress, so WebGL2 remains the compatibility floor. Design for a swap later; `three.js` `WebGPURenderer` with automatic WebGL2 fallback makes this a one-line change.
2. **Stay single-threaded JS at first; do not enable Emscripten pthreads.** This avoids the COOP/COEP requirement entirely, which means **GitHub Pages works**. If you later need a threaded WASM physics solver, you must move to a host that can set headers (Cloudflare Pages via `_headers`, Netlify via `_headers`, Vercel via `vercel.json`).
3. **Move the extractor off Windows.** Port `extract-*.ps1` + the Node glue to plain Node.js so Linux/macOS contributors can build assets. The .NET 8 extractor itself runs cross-platform; only the PowerShell wrappers are Windows-bound.
4. **Prefer the Unlicensed Rust asset stack (`rpf-archive-rs`, `rage-cli`) for any new parsers**, to keep the shipped runtime permissive. Use RageLib (GPL-3.0) as a *documentation and reference* source only.
5. **Keep the renderer's batching discipline.** It is the single biggest performance lever in this codebase and it is easy to destroy by adding per-object materials.
6. **Design the asset layer for streaming from the start** — per-sector, range-friendly, with a manifest. That is what makes a multi-GB world survivable.

---

## 7. Minimum viable prototype definition

### MVP-0 — "Reproduce and prove" (target: days, not weeks)

**Goal: demonstrate that the existing pipeline runs end-to-end on your hardware.**

1. Install GTA IV: Complete Edition.
2. Clone `gta4-webmap` into the game directory.
3. `./setup.ps1`, then `npm run extract` (single proof sector `manhat01`), then `npm run serve`.
4. Open `http://127.0.0.1:4174`, confirm the sector renders.
5. `npm run extract:player` and `npm run test:walk` — confirm Niko walks.
6. **Record:** sector extraction time, generated payload size, first-render time, steady FPS, and browser RSS at 1080p on the RTX 3050 laptop.

**Exit criterion:** one outdoor sector + a walking Niko, running locally in a browser, with measured numbers.

### MVP-1 — "Playable free roam" (target: weeks)

Build on `gta4-webmap`'s existing systems; add:

- Full 34-sector world extraction with a real streaming budget and eviction policy.
- **Gamepad input** (Gamepad API) — currently absent.
- **Audio**: RPF3/`.ivaud` extraction → WebAudio SFX with positional playback. Start with weapons/engines/ambience; radio is a separate, larger job.
- **Vehicle physics upgrade**: replace the arcade model with a real solver. Recommended: a WASM-compiled rigid-body engine (Rapier or Bullet via Emscripten), still driven by `handling.dat` constants. Run it in a Worker; keep it single-threaded initially to avoid COOP/COEP.
- **Persistent settings** and a **save system** (position, wanted level, vehicle state, inventory) in OPFS.
- **Cross-platform extractor** (Node instead of PowerShell).

**Definition of done:** free roam across the whole outdoor city, on foot and in vehicles, with audio, gamepad support, and saves that survive a reload — at ≥30 fps at 1080p on an RTX 3050 laptop.

### MVP-2 — "Toward the game" (target: months, and **do not plan it in detail yet**)

- Interiors / MLO support (RageLib has a reader; `gta4-webmap` has none).
- A **`.sco` script VM** — the prerequisite for missions. This is the largest single unknown in the whole project.
- Deeper AI (path planning rather than greedy pursuit).
- WebGPU renderer path.

### Explicitly out of scope for any realistic MVP

- Full mission/story content.
- Euphoria-equivalent character dynamics.
- Frame-perfect parity with retail vehicle handling.

---

## 8. Required development tools and dependencies

| Layer | Tool | Version | Notes |
|---|---|---|---|
| Runtime | Node.js | **≥22** | Required by `gta4-webmap` (`engines.node: >=22`) |
| Runtime | `three` | 0.185.1 | Pinned; dependabot is already proposing 0.186.0 |
| Runtime | `http-server` | 14.1.1 | Local static serving on port 4174 |
| Runtime | `@gltf-transform/cli` | 4.5.0 | Meshopt compression of exported glTF |
| Runtime | `playwright-core` | 1.62.1 | Headless browser checks |
| Extractor | **.NET SDK 8** | 8.0 | C# extractor; `setup.ps1` can install a repo-local copy |
| Extractor | **Windows PowerShell** | Win 10/11 | *To be ported to Node for cross-platform use* |
| Browser | Chrome or Edge | current | The tests target Chromium |
| Testing | Playwright + `gta4map` global | — | `setPaused`, `lookAtPoint`, `reportCrime`, `getState` |
| Later: WASM | Emscripten (em++) | current | For a physics solver; **not needed for MVP-0/1** |
| Later: WASM | CMake + Ninja | — | If compiling Bullet/Rapier |
| Useful | `rpf-archive-rs` / `rage-cli` | current | Rust, **Unlicense** — clean-room reference and possible WASM asset path |
| Useful | OpenIV / SparkAll | — | Windows-only, **closed source**. Indispensable for eyeballing formats; **do not copy code** |
| Useful | Ghidra / Binary Ninja | — | Only if you attempt `GTAIV.exe` static RE. Never execute the binary. |

**Your machine (16 GB RAM, NVIDIA RTX 3050 laptop GPU):**

| Task | Suitable? | Notes |
|---|---|---|
| Building/testing a browser-compatible engine | **Yes** | This is JS tooling; 16 GB is comfortable |
| Compiling C/C++ → WebAssembly | **Yes, with caution** | Emscripten is fine for a physics library. A 63 MB-class module like GTA V's would need far more than 16 GB at link time — use `-O2`, `wasm32`, and/or a CI runner with 32–64 GB |
| Testing a reduced GTA IV prototype | **Yes — this is the sweet spot** | `gta4-webmap` reports 3.4 ms render time on an *AMD iGPU* at 1440×900. An RTX 3050 laptop (4 GB VRAM) is comfortably above that, but **VRAM is your binding constraint**: the design is texture-memory bound, so keep `--max-edge` at 256 and cap sector residency |
| Testing the complete game if a port existed | **No** | 4 GB VRAM and 16 GB system RAM are below a realistic full-fidelity requirement. Run the engine, not the whole game |
| Generating assets | **Yes but slow** | A full 34-sector world extraction is hours-long and multi-GB; the 343-ped meshopt pass alone is ~30 minutes |

---

## 9. Browser compatibility and performance risks

### Platform constraints

| Risk | Detail | Mitigation |
|---|---|---|
| **SharedArrayBuffer / pthreads** | Requires cross-origin isolation (COOP + COEP headers). **GitHub Pages cannot set response headers.** | Stay single-threaded for MVP-0/1. If you need threads, move to Cloudflare Pages / Netlify / Vercel |
| **wasm32 4 GB ceiling** | Emscripten `MAXIMUM_MEMORY` defaults to 2 GB; wasm32 hard limit is 4 GB. `MEMORY64=1` lifts this but is a different engine path | Design for <2 GB. Not a constraint for the recommended track |
| **OPFS quota and eviction** | Chrome: up to **60% of disk**. Firefox: **10% of disk or 10 GB**, whichever is smaller (best-effort); 50% up to 8 TB if persistent storage is granted. Safari: ~1 GB default, and **7-day eviction of script-writable storage with no user interaction** unless the site is installed [1](https://qnotepad.com/blog/indexeddb-storage-limits-safari-firefox-chrome) [3](https://www.harxit.com/blog/how-to-store-big-files-in-the-browser) | Call `navigator.storage.persist()`; show the user a quota estimate; design for re-import; treat Safari as a second-class target |
| **Firefox quota** | 10 GB best-effort cap is the real limit for a multi-GB asset cache | Request persistent storage explicitly; allow partial-city installs |
| **WebGPU availability** | Chrome/Edge 113+; Firefox 141+ on Windows, 145+ on macOS ARM64; Safari 26. **Firefox on Linux and Android still in progress** [1](https://web.dev/blog/webgpu-supported-major-browsers) | WebGL2 floor with automatic WebGPU upgrade |
| **Safari OPFS in private mode** | Disabled entirely; Chrome incognito caps around 100 MB | Detect and fail gracefully with a clear message |
| **Draw-call explosion** | The renderer is draw-call bound, not fill bound. Naïve per-object materials would take 3.4 ms back to 32.7 ms | Enforce the batching discipline; add a CI perf check |
| **No JIT for any emulation path** | Fatal for approach F | Don't use approach F |
| **Texture memory** | Sector residency is capped by texture memory, not draw calls | Keep `--max-edge 256`; tune residency; watch 4 GB VRAM |

### Performance expectations

**Anchored (measured, first-hand from the project):** 88 draw calls, 3.4 ms render time, 19 requests to first render, on an **AMD integrated GPU** at 1440×900, for a batched sector.

**Uncertain estimates — clearly labelled as such, not benchmarks:**

- **Browser memory for an MVP-1-class prototype: roughly 2–4 GB RSS** at 1080p with a few resident sectors. *Estimate only. Confidence: low-moderate.* Basis: the engine's own 2008 minimum was 1.5 GB; glTF + texture arrays + JS heap overhead add substantially; no measurement of this exists for this project.
- **Browser memory for a full-fidelity port: unknown, likely >4 GB.** *Do not plan around this.*
- **Generated asset payload: multiple gigabytes** for the full 34-sector city. The project's own README states this plainly. Per-asset-class figures are known (player 2.8 MB, 127 vehicles 19 MB, 343 peds 30 MB + 51 MB textures); the map texture bundles are the bulk and are not broken out.
- **Frame rate on your RTX 3050 laptop: unknown.** The reference figure is 3.4 ms render on an iGPU, but that is render time for one batched sector at 1440×900 — not a full-frame budget including AI, streaming and physics at 1080p. **Measure it in MVP-0. Do not assume.**

---

## 10. Free or low-cost hosting strategy

### What you can host for free

**Only code.** Engine code, tooling, and documentation. Nothing derived from Rockstar assets — not extracted glTF, not texture bundles, not `web/assets/`, not `web/data/`. `gta4-webmap` already gitignores these and says so explicitly in `ASSET_NOTICE.md`.

| Host | Free tier | COOP/COEP headers? | Verdict |
|---|---|---|---|
| **GitHub Pages** | Generous for static; practical soft limits ~1 GB repo, ~100 GB/month bandwidth | **No** | **Best for MVP-0/1.** Exactly what reVC-wasm uses. Fine as long as you stay single-threaded |
| **Cloudflare Pages** | Generous free tier | **Yes** (`_headers`) | Best if you later need pthreads/SharedArrayBuffer |
| **Netlify** | 100 GB/month | **Yes** (`_headers`) | Good alternative |
| **Vercel** | Hobby tier | **Yes** (`vercel.json`) | Good alternative, tighter limits |

### Asset delivery — and the cost question

Because **users supply their own assets**, you do not host 20 GB and you do not pay for 20 GB of egress. The reVC port's model applies directly: the user imports once (~668 MB for Vice City), it is extracted to OPFS, and gameplay is server-free afterwards.

**For GTA IV the numbers are materially worse.** A full GTA IV install is ~22 GB [PCGamingWiki](https://www.pcgamingwiki.com/wiki/Grand_Theft_Auto_IV). Even a curated outdoor-only export is multi-GB. Practical consequences:

- The import step must be a **folder/file picker** (File System Access API where available) or a **pre-packed archive the user builds locally**, not a download.
- Import must be **resumable and incremental** — you cannot ask a user to hold a 5 GB upload in one go.
- **Compression and chunking matter**: Meshopt geometry (already used), KTX2/Basis texture transcoding (not yet used — a strong candidate for a big win), and per-sector granularity (already used).
- **Offline after setup: yes**, subject to OPFS persistence and the browser's eviction policy (§9).

### The honest cost warning

**Do not promise this stays free at any scale.** If you ever host *any* game asset, or if traffic grows, you pay. Static hosting free tiers are for code and small assets. Bandwidth for multi-GB user-uploaded content is not a thing a free tier absorbs — and in the recommended architecture, it is also not a thing you are responsible for, because **the user's files never transit your server**. Preserve that property.

---

## 11. Legal and licensing considerations

> **This is not legal advice. I am not a lawyer.** Where uncertainty is material, consult a qualified attorney licensed in your jurisdiction before publishing.

### The hard rule

**The website must not distribute, host, cache, or proxy any Rockstar/Take-Two asset.** Not textures, not models, not audio, not extracted glTF, not text. Users supply files they legally own; the files stay on their device. Both reference projects follow exactly this rule [1](https://github.com/joncodeofficial/gta-vice-city-wasm) [ASSET_NOTICE.md](https://github.com/luckeyfaraday/gta4-webmap).

### Licence analysis of candidate dependencies

| Dependency | Licence | Consequence for a browser port |
|---|---|---|
| **`gta4-webmap`** | **MIT** | Safest choice. Copy, modify, publish — preserve the copyright notice. Its `ASSET_NOTICE.md` is explicit that MIT covers only original code and documentation |
| **GTA4Unity / RageLib** | **GPL-3.0** | **Strong copyleft.** If you *link, bundle, or derive browser code* from it, your browser code must be GPL-3.0 and you must offer source. Only safe as (a) a build-time tool kept in a separate process, or (b) a *reference* you reimplement from. `gta4-webmap` chooses (a) — it clones GTA4Unity into a gitignored `converter/` directory rather than vendoring it |
| **LibertyRecomp** | **GPL-3.0** | Same. A WASM build inherits GPL-3.0 |
| **Theft4** | **GPL-3.0** | Same |
| **`rpf-archive-rs` / `rage-cli` (VIRUXE)** | **Unlicense** | **Public domain. Maximum freedom.** Preferred for any new parser you ship in the browser |
| **re3 / reVC** | Mixed; the browser client is MIT | Precedent only |
| **CodeWalker (dexyfex)** | **No licence declared** | **Do not copy.** Read as reference only |
| **OpenIV / SparkAll** | Closed source | Reference only |
| **three.js** | MIT | Fine |
| **Emscripten / LLVM** | Apache-2.0 with LLVM exceptions / UIUC | Fine |
| **Boxedwine** | GPL-2.0 | Moot — approach F is BLOCKED |
| **FusionFix** | GPL-3.0 | Reference only (it is a game mod, not a library you link) |

### Specific risks

1. **Trademark and passing-off — the highest practical risk.** The Take-Two DMCA against the reVC browser host targeted **the use of the "Grand Theft Auto: Vice City" name and the invitation to input data from original copies**, framed as misleading to users — not the reverse-engineered code [3](https://timesofindia.indiatimes.com/technology/gaming/take-two-shuts-down-browser-based-gta-vice-city-port-with-dmca-takedown-says-it-was-misleading-users/articleshow/126236663.cms). Naming, branding, and presentation matter at least as much as code provenance.
2. **Reverse engineering and EULA.** GTA IV's EULA restricts reverse engineering. Clean-room practice — documenting formats from observation, never from proprietary source — is the defensible posture. Jurisdiction matters (EU software-directive interoperability rights differ from US law).
3. **Recompilation compounds exposure.** LibertyRecomp/Theft4 are recompilations of a proprietary binary. Building a browser port on top of them stacks a third layer of risk onto an already-risky base.
4. **Never touch leaked source.** The GTA V browser port is reported to have been built on leaked source [1](https://businessupturn.com/technology/gta-v-is-suddenly-running-inside-chrome-viral-browser-port-shrinks-a-170gb-game-to-around-700mb-but-it-may-not-survive-for-long/). Not a path to consider, and not a path to research.
5. **Asset-derived files are still derived.** Extracted glTF, repacked texture arrays, and converted audio are derivative works of the originals. "It's just geometry" is not a defence.
6. **User-uploaded content.** Your architecture avoids hosting it — keep it that way. Do not add a server-side upload, cache, or CDN in front of game assets.
7. **Untrusted input, technically.** Archives, extracted assets and downloaded tooling are untrusted input: parse defensively (bounds-check every offset and length, cap allocations, never `eval` data-derived strings), pin dependencies by hash, and never execute a downloaded binary — including `GTAIV.exe`.

**When to get a lawyer:** before you publish a public URL; before you use the name "GTA", "GTA IV", "Liberty City", or Rockstar's marks in the site's title, domain, or marketing; before shipping any GPL-3.0-derived browser code; and before accepting contributions from others into a codebase with this provenance.

---

## 12. Major blockers and unresolved questions

### Blockers

| # | Blocker | Classification |
|---|---|---|
| B1 | **No game files provided.** Version, integrity, and archive inventory are unknown. **Unblocked by running `tools/gta4-inventory.ps1` (≈1 MB of text; no content transfer)** | **BLOCKED pending your action** |
| B2 | Euphoria character physics cannot be reimplemented — proprietary middleware | **BLOCKED** (permanent fidelity gap) |
| B3 | RAGE vehicle solver is not in the assets (`handling.dat` holds tuning only) | **HIGH RISK** (approximation only) |
| B4 | Missions require a `.sco` script VM that does not exist in any browser project | **HIGH RISK** |
| B5 | Windows-only extraction pipeline (PowerShell) | **EXPERIMENTAL** — needs porting |
| B6 | No audio subsystem exists in any browser GTA IV project | **EXPERIMENTAL** |
| B7 | Windows compatibility layers in the browser are far too slow | **BLOCKED** |
| B8 | Full-city multi-GB asset payload exceeds Firefox's 10 GB best-effort quota and Safari's ~1 GB default | **HIGH RISK** for Safari/Firefox |

### Open questions

1. **Which GTA IV build do you own, and on what OS is your development machine?** (The extraction pipeline currently needs Windows.)
2. **Is "outdoor free roam" acceptable as the MVP**, or is mission content a hard requirement? The answer changes the roadmap by a year or more.
3. **How much fidelity loss in vehicle handling and character physics is acceptable?** There is no path to parity.
4. **Is a GPL-3.0-encumbered runtime acceptable to you?** If yes, LibertyRecomp becomes a possible long-horizon track. If no, the MIT track is the only track.
5. **Will you publish publicly?** That materially changes the legal risk profile (§11).
6. **What is the actual measured FPS and memory on your RTX 3050 laptop?** Unknown until MVP-0.
7. **What is the real generated payload size for all 34 sectors?** The project does not publish it; the README only says "several gigabytes."

---

## 13. Prioritised implementation roadmap

### Phase 1 — RESEARCH ✅ *(this report — complete)*

### Phase 2 — REPRODUCE AND MEASURE *(days — do this next)*

| # | Action | Success criterion |
|---|---|---|
| 2.1 | Run `tools/gta4-inventory.ps1`, share `summary.txt` (see `tools/README.md`) | Version + archive inventory confirmed |
| 2.2 | Install Node 22+, .NET 8, Git; clone `gta4-webmap` **inside** the game directory | Repo resolves parent as game root |
| 2.3 | `./setup.ps1` → `npm run extract` (sector `manhat01` only) → `npm run serve` | **`manhat01` renders in a browser** ← the single most important test in this whole plan |
| 2.4 | `npm run extract:player` → `npm run test:walk` | Niko walks in the streamed world |
| 2.5 | Run `npm test`, `test:traffic`, `test:crowd`, `test:wanted`, `test:driving`, `test:weapons`; inspect `artifacts/` | All existing browser checks pass |
| 2.6 | **Measure and record:** extraction time, payload size, first-render time, steady FPS @1080p, browser RSS | A written baseline exists |

**Gate: do not write engine code until 2.3 and 2.6 pass.** If 2.3 fails, nothing downstream is worth planning.

### Phase 3 — MVP-1, PLAYABLE FREE ROAM *(weeks)*

| # | Action |
|---|---|
| 3.1 | Port the PowerShell extractors to Node.js (cross-platform) |
| 3.2 | Full 34-sector extraction + streaming budget + eviction; measure payload |
| 3.3 | Gamepad API input |
| 3.4 | Audio: RPF3/`.ivaud` extraction → WebAudio SFX (weapons, engines, ambient) |
| 3.5 | Vehicle physics: WASM rigid-body solver in a Worker, driven by `handling.dat` |
| 3.6 | Settings persistence + save games in OPFS |
| 3.7 | `navigator.storage.persist()` + quota UI + graceful degradation |
| 3.8 | Deploy engine-only build to GitHub Pages; confirm no assets are committed |

### Phase 4 — TOWARD THE GAME *(months; do not plan in detail until Phase 3 is done)*

| # | Action | Classification |
|---|---|---|
| 4.1 | Interiors / MLO support | EXPERIMENTAL (RageLib has a reader) |
| 4.2 | `.sco` script VM + mission runtime | **HIGH RISK** — the largest unknown |
| 4.3 | Path-planned AI (replace greedy pursuit) | EXPERIMENTAL |
| 4.4 | Radio streaming | EXPERIMENTAL |
| 4.5 | WebGPU renderer path with WebGL2 fallback | PROMISING |
| 4.6 | KTX2/Basis texture transcoding to cut payload | PROMISING |
| 4.7 | Re-evaluate LibertyRecomp/Theft4 for a WASM backend | EXPERIMENTAL, GPL-3.0 |

### Phase 5 — RECONSIDER THE HARD PROBLEM

Only after Phase 3: reassess whether a LibertyRecomp-derived WASM backend (GPL-3.0, new WebGPU backend, new WGSL shader target) is worth attempting, in light of what you learned, what the upstream projects have done since, and legal advice obtained in the interim.

---

## 14. Sources and verification notes

### Primary sources — verified first-hand (GitHub REST API and/or `git clone`, 2026-10-11)

| Project | URL | Licence | Last push | Verified |
|---|---|---|---|---|
| gta4-webmap | https://github.com/luckeyfaraday/gta4-webmap | MIT | 2026-10-10 | API + full clone; README, ASSET_NOTICE.md, AGENTS.md, `web/`, `tools/`, `extractor/` read |
| GTA4Unity | https://github.com/Infinity-Loops/GTA4Unity | GPL-3.0 | 2026-05-06 | API + full clone; 357 C# files, RageLib 500 files inventoried |
| LibertyRecomp | https://github.com/OZORDI/LibertyRecomp | GPL-3.0 | 2026-09-23 | API + blobless clone (13,348 files); `docs/BUILDING.md`, `docs/SHADER_PIPELINE.md`, `.gitmodules` read |
| Theft4 | https://github.com/KoreanSeats1/Theft4 | GPL-3.0 | 2026-10-09 | API + README (444 lines) read |
| CodeWalker | https://github.com/dexyfex/CodeWalker | **none** | 2025-04-11 | API; 760★, 332 forks |
| rpf-archive-rs | https://github.com/VIRUXE/rpf-archive-rs | Unlicense | 2026-09-20 | API; 9★ |
| rage-cli | https://github.com/VIRUXE/rage-cli | — | 2026-10-02 | API; 28★ |
| GTAIV.EFLC.FusionFix | https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix | GPL-3.0 | 2026-10-09 | API; 3,381★ |
| CLEO-Redux | https://github.com/cleolibrary/CLEO-Redux | NOASSERTION | 2026-09-26 | API; 282★ |
| GTAIVMissionScripts | https://github.com/0x52617665/GTAIVMissionScripts | Unlicense | 2020-11-26 | API; **stale** |
| gta-vice-city-wasm | https://github.com/joncodeofficial/gta-vice-city-wasm | MIT | active | API + README read |
| Boxedwine | https://github.com/danoon2/Boxedwine | GPL-2.0 | active | API + README |

### Primary technical write-up

- Satyajit Ghana, *"GTA V in a browser tab: Rockstar's own engine, recompiled to wasm64 and WebGPU"*, ai.thesatyajit.com, October 2026 — [link](https://ai.thesatyajit.com/articles/gta5-in-the-browser). **Read directly** (chunks 0, 8, 11 of 12). The most detailed independent technical analysis available. Its stated method: downloaded every file the site serves, read all of its JavaScript, pulled sample game files apart byte by byte, ran the game headless on a 16-core server with no GPU.

### File-format documentation

- RPF archive versions — [GTAMods Wiki](https://gtamods.com/wiki/RPF_archive) [1](https://gtamods.com/wiki/RPF_archive)
- WDR model format — [GTAMods Wiki](https://gtamods.com/wiki/WDR) [2](https://gtamods.com/wiki/WDR)
- WPL placement format — [GTAMods Wiki](https://gtamods.com/wiki/WPL) [5](https://gtamods.com/wiki/WPL)
- GTA IV PC specs, API, executable bitness, install size — [PCGamingWiki](https://www.pcgamingwiki.com/wiki/Grand_Theft_Auto_IV)
- PC patch/version history — [GTA Wiki](https://gta.fandom.com/wiki/Grand_Theft_Auto_IV/Title_Update_Notes) [1](https://gta.fandom.com/wiki/Grand_Theft_Auto_IV/Title_Update_Notes)
- Euphoria / NaturalMotion — [GTA Wiki](https://gta.fandom.com/wiki/Euphoria) [1](https://gta.fandom.com/wiki/Euphoria), [Wikipedia](https://en.wikipedia.org/wiki/NaturalMotion) [3](https://en.wikipedia.org/wiki/NaturalMotion)
- GTA IV audio (RPF3 / `.ivaud`, **not** AWC) — [GTAForums](https://gtaforums.com/topic/391675-gta4-converting-the-rpf-radios-to-wav-or-mp3/) [4](https://gtaforums.com/topic/391675-gta4-converting-the-rpf-radios-to-wav-or-mp3/), [Se7enSins](https://www.se7ensins.com/forums/threads/so-we-can-edit-animal-noises-and-other-sounds.1316231/) [5](https://www.se7ensins.com/forums/threads/so-we-can-edit-animal-noises-and-other-sounds.1316231/)

### Browser platform

- WebGPU availability — [web.dev](https://web.dev/blog/webgpu-supported-major-browsers) [1](https://web.dev/blog/webgpu-supported-major-browsers) (Chrome/Edge 113+; Firefox 141+ Windows, 145+ macOS ARM64; Safari 26)
- Storage quotas and eviction — [qnotepad](https://qnotepad.com/blog/indexeddb-storage-limits-safari-firefox-chrome) [1](https://qnotepad.com/blog/indexeddb-storage-limits-safari-firefox-chrome), [harxit](https://www.harxit.com/blog/how-to-store-big-files-in-the-browser) [3](https://www.harxit.com/blog/how-to-store-big-files-in-the-browser)
- WASM memory limits (`MAXIMUM_MEMORY` default 2 GB, wasm32 4 GB ceiling, `MEMORY64` modes) — Emscripten settings documentation
- COOP/COEP gating of `SharedArrayBuffer` — Emscripten pthreads documentation

### Legal precedent

- Take-Two DMCA against the reVC browser host — [Times of India](https://timesofindia.indiatimes.com/technology/gaming/take-two-shuts-down-browser-based-gta-vice-city-port-with-dmca-takedown-says-it-was-misleading-users/articleshow/126236663.cms) [3](https://timesofindia.indiatimes.com/technology/gaming/take-two-shuts-down-browser-based-gta-vice-city-port-with-dmca-takedown-says-it-was-misleading-users/articleshow/126236663.cms)
- The same codebase resurfaces on a new host, Sept 2026 — [TechnoSports](https://technosports.co.in/vice-city-gta-returns-browsers/) [1](https://technosports.co.in/vice-city-gta-returns-browsers/)
- playgta5.com takedown / provenance reporting — [TalkEsport](https://www.talkesport.com/news/gaming/gta-5/play-gta-5-in-browser-playgta5-shut-down/) [2](https://www.talkesport.com/news/gaming/gta-5/play-gta-5-in-browser-playgta5-shut-down/), [Business Upturn](https://businessupturn.com/technology/gta-v-is-suddenly-running-inside-chrome-viral-browser-port-shrinks-a-170gb-game-to-around-700mb-but-it-may-not-survive-for-long/) [1](https://businessupturn.com/technology/gta-v-is-suddenly-running-inside-chrome-viral-browser-port-shrinks-a-170gb-game-to-around-700mb-but-it-may-not-survive-for-long/)

### Verification notes and caveats

- All repository dates come from the GitHub REST API `pushed_at` field on **2026-10-11**.
- `gta4-webmap`'s capability claims are taken from its README and from the source I cloned — which the project backs with automated Playwright checks for each subsystem. **I did not run the pipeline** (no game files), so these are *reported* results, not reproduced ones.
- GTA V browser-port figures come from one independent analyst's published measurements, not mine.
- **No benchmark in this report was produced by me.** Every number is attributed, and every estimate is labelled as an estimate.
- Deliberately excluded: one GitHub repository appearing to contain the retail GTA IV executable and DLLs; leaked-source material; piracy and DRM-bypass sources; and any repository with no declared licence (CodeWalker is cited as reference only, never as a code source).

---

## 15. Project inventory (substitute for the game-file inventory)

**Game files were not accessible, so no game-file inventory exists.** See §3.3 for exactly what is needed to produce one.

The following is the **project inventory** — the state of the ecosystem you would be building on.

| # | Project | Type | Licence | Last activity | Builds Linux? | WASM-capable? | Decision |
|---|---|---|---|---|---|---|---|
| 1 | [`luckeyfaraday/gta4-webmap`](https://github.com/luckeyfaraday/gta4-webmap) | Browser viewer + extractor, partial gameplay | **MIT** | 2026-10-10 | Viewer yes / extractor no | **Already browser-native** | **PROMISING — build on this** |
| 2 | [`Infinity-Loops/GTA4Unity`](https://github.com/Infinity-Loops/GTA4Unity) | Unity world loader + RageLib format library | **GPL-3.0** | 2026-05-06 | Unity editor yes | Via Unity WebGL, poorly | **EXPERIMENTAL — reference / build-time only** |
| 3 | [`OZORDI/LibertyRecomp`](https://github.com/OZORDI/LibertyRecomp) | Static recomp, Xbox 360 → PC; Vulkan/D3D12/Metal | **GPL-3.0** | 2026-09-23 | **Yes** | **No backend exists** | **HIGH RISK — long-horizon option** |
| 4 | [`KoreanSeats1/Theft4`](https://github.com/KoreanSeats1/Theft4) | Static AOT recomp → ARM64 iOS, direct Metal | **GPL-3.0** | 2026-10-09 | No | No | **HIGH RISK — proves a new GPU backend is possible** |
| 5 | [`joncodeofficial/gta-vice-city-wasm`](https://github.com/joncodeofficial/gta-vice-city-wasm) | reVC → WASM + OPFS browser port | MIT | active | Yes | **Yes** | **PROMISING — architectural template** |
| 6 | [`VIRUXE/rpf-archive-rs`](https://github.com/VIRUXE/rpf-archive-rs), [`rage-cli`](https://github.com/VIRUXE/rage-cli) | Rust RAGE archive/resource readers | **Unlicense** | 2026-10-02 | Yes | Yes (has prior wasm glTF export) | **PROMISING — clean-room asset layer** |
| 7 | [`ThirteenAG/GTAIV.EFLC.FusionFix`](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix) | PC bugfix / RE knowledge base | GPL-3.0 | 2026-10-09 | n/a | n/a | Reference only |
| 8 | [`dexyfex/CodeWalker`](https://github.com/dexyfex/CodeWalker) | GTA V world editor, `RpfFile.cs` | **none** | 2025-04-11 | n/a | n/a | Reference only — **do not copy** |
| 9 | [`cleolibrary/CLEO-Redux`](https://github.com/cleolibrary/CLEO-Redux) | Script host incl. GTA IV | NOASSERTION | 2026-09-26 | Yes | n/a | Tooling only |
| 10 | [`0x52617665/GTAIVMissionScripts`](https://github.com/0x52617665/GTAIVMissionScripts) | Decompiled mission scripts | Unlicense | 2020-11-26 | n/a | n/a | Stale; reference only |
| 11 | [`danoon2/Boxedwine`](https://github.com/danoon2/Boxedwine) | 32-bit Windows emulation in WASM | GPL-2.0 | active | Yes | Yes, but far too slow | **BLOCKED** |

---

## 16. Final recommendation

### EXPERIMENT — proceed to Phase 2 on one narrow track

**Attempt this first: fork and extend `luckeyfaraday/gta4-webmap`.**

Why this track over every alternative:

1. **It is already in the browser.** Not "portable in principle" — running, with measured performance, on real GTA IV assets.
2. **MIT-licensed**, with a well-drafted asset notice. Every other GTA IV runtime is GPL-3.0.
3. **The asset posture is already correct.** Local extraction, assets never shipped, user supplies their own copy. This is the only legally defensible architecture and it is already implemented.
4. **Most of your MVP list already exists** — real world, real Niko with real animations, 127 vehicles, 343 peds, traffic on the real road graph, a reverse-engineered navmesh, wanted system, police, driving, and three weapons with data-driven behaviour.
5. **It deploys anywhere.** Pure JS + WebGL2, no WASM, no `SharedArrayBuffer`, so **no COOP/COEP requirement and GitHub Pages works**. A threaded WASM port would not.
6. **The gaps are legible and individually addressable**: audio, real vehicle physics, saves, gamepad, cross-platform extraction. None of them is a research problem. Missions are the one research problem, and they are correctly deferred.

Why not the alternatives:

- **Porting a GTA IV engine to WASM (A):** there is no open-source engine to port. The two that run real game code are GPL-3.0 static recompilations with no WASM backend and no WGSL shader target.
- **Unity / compatibility-layer runtime (C):** GPL-3.0 plus Unity's terms, a 200K-entity world through Unity's WebGL asset pipeline, and no gameplay to inherit. Worse on every axis.
- **Windows emulation (F):** **NO-GO** — interpretation-only, 10–40% of native, and a 2001 title already runs at 0.4–0.7 fps. GTA IV is not remotely reachable.
- **Compiling `GTAIV.exe` to WASM:** not possible. Different instruction set, no Win32 or D3D9, closed-source middleware, and no legal basis.

### The smallest reproducible test

> **Clone `gta4-webmap` into your GTA IV: Complete Edition directory, run `./setup.ps1`, then `npm run extract` (single sector `manhat01`) and `npm run serve`. Open `http://127.0.0.1:4174` and see real Liberty City in a browser.**
>
> Then run `npm run extract:player` and `npm run test:walk` and watch Niko walk.

If that works on your RTX 3050 laptop, you have a credible foundation and should proceed. If it does not, you have spent a day rather than a year, and you will have learned something essential about the asset pipeline before committing anything.

### Per-option verdicts

| Option | Verdict |
|---|---|
| **A. Port an existing GTA IV engine to WASM** | **HIGH RISK** — no such open-source engine; only GPL-3.0 recompilations with no WASM backend |
| **B. Adapt an existing GTA IV reimplementation** | **PROMISING — RECOMMENDED** (via `gta4-webmap`) |
| **C. Browser runtime on an existing engine / compatibility layer** | **HIGH RISK** (Unity); **BLOCKED** (Windows emulation) |
| **D. Reimplement minimum systems from documented formats** | **EXPERIMENTAL** — accurate description of what track B actually becomes |
| **E. Limited prototype with a path to the full game** | **PROMISING — this is the plan** |
| **F. Windows compatibility layer** | **BLOCKED** |

### What I need from you to start Phase 2

1. **The inventory output** — run `tools/gta4-inventory.ps1` (or `.sh`) and share `tools/gta4-inventory/summary.txt`. ~1 MB of text, no content transfer (§3.3, `tools/README.md`).
2. **Your development OS** — the extraction pipeline currently requires Windows.
3. **Whether outdoor free roam is an acceptable MVP**, or whether missions are a hard requirement.
4. **Whether a GPL-3.0-encumbered runtime is acceptable** — this decides if the LibertyRecomp track is ever worth revisiting.

---

*End of Phase 1. No engine implementation was started, per instruction. Awaiting direction before Phase 2.*
