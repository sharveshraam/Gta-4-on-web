# How to hand over a 22 GB installation

**Short answer: you don't. Send the inventory, not the game.**

The analysis in Phase 1 needs to answer questions like *which build is this?*,
*is the executable 32-bit?*, *which archive versions are present?*, *is `paths2.ipl`
there?*, *how many `.rpf` files and how big?*. **Every one of those questions is
answered by filenames, file sizes and a few header bytes** — none of them needs
the file contents.

The output is **~1 MB of text** (about 0.005% of the install size) and contains
no game content, so it is safe to commit to a public repository or paste into a
chat.

---

## The three things you can send, best first

### Option 1 — Inventory (✅ do this)

Run the scanner on your machine, then share the text file it produces.

**Windows (PowerShell) — this is what you almost certainly want:**

```powershell
cd path\to\Gta-4-on-web
powershell -ExecutionPolicy Bypass -File .\tools\gta4-inventory.ps1
```

If auto-detection fails, give it the path. The folder you want is the one
**containing `GTAIV.exe`** — on Steam that is the `GTAIV` **subfolder** of
`Grand Theft Auto IV`:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\gta4-inventory.ps1 `
  -GameDir "C:\Program Files (x86)\Steam\steamapps\common\Grand Theft Auto IV\GTAIV"
```

**Linux / macOS (Steam Proton, CrossOver, etc.):**

```bash
cd path/to/Gta-4-on-web
chmod +x tools/gta4-inventory.sh
./tools/gta4-inventory.sh
# or explicitly:
./tools/gta4-inventory.sh "/path/to/Grand Theft Auto IV/GTAIV"
```

Add `-n` (or `-NoHash` on Windows) to skip SHA-256 — takes seconds instead of a
couple of minutes, at the cost of not being able to detect file corruption.

**It writes `tools/gta4-inventory/`:**

| File | Contents |
|---|---|
| `summary.txt` | **Read this first.** Detected executable format, machine type, bitness, `LARGEADDRESSAWARE` flag, link timestamp, ProductVersion/FileVersion; which DLLs are present; `.rpf`/`.img` magic numbers; per-extension counts and sizes; edition markers (`TLAD`, `TBoGT`, `EFLC`); presence of the exact data files the port depends on |
| `tree.txt` | Directory tree, two levels, with file counts and summed sizes |
| `manifest.csv` | `relative_path, size_bytes, sha256` for every file |

Then share it however is easiest:

- paste **`summary.txt`** straight into chat (it is ~5 KB), **or**
- `git add tools/gta4-inventory && git commit && git push` — it is plain text and
  contains no game content, **or**
- attach the folder.

### Option 2 — Just start Phase 2 and report back numbers

If you would rather skip the paperwork: install Node 22+ and .NET 8, clone
[`gta4-webmap`](https://github.com/luckeyfaraday/gta4-webmap) **inside** your
GTA IV folder, run `./setup.ps1` then `npm run extract` and `npm run serve`, and
tell me what you see at `http://127.0.0.1:4174`. That single test tells us more
than any manifest.

### Option 3 — The files themselves (❌ don't)

Not needed, and actively harmful. See below.

---

## What NOT to do

| Don't | Why |
|---|---|
| Zip and upload the install | 22 GB of copyrighted content. Unhostable, unlawful, and unnecessary |
| `git add` the game folder | GitHub hard-caps files at 100 MB and soft-caps repos at 1 GB; and you would be redistributing the game |
| Commit `web/assets/` or `web/data/` | These are **derived from** the game — extracted glTF, texture bundles, navmesh JSON. Still derivative works |
| Put a Google Drive link to the game in the repo or chat | Same as uploading it, and Drive is not reachable from my sandbox anyway |
| Send me a local path like `C:\...` | I cannot see your disk. My sandbox has no access to your machine — that is why the scanner exists |
| Run `GTAIV.exe` to "check it works" | Not needed, and I will not analyse it that way. The scanner reads headers only and never executes anything |

---

## Why the scanner is safe

- **Read-only.** Opens files, reads the first 4–16 bytes, closes them. Never
  writes to the game directory, never executes anything.
- **No content in the output.** Filenames, sizes, hashes, and a handful of magic
  numbers. A 4-byte magic like `RPF2` is a format identifier, not copyrightable
  content.
- **Root path is redacted** from every output file, so your Windows username and
  drive layout do not leak.
- **Hashes, not files.** SHA-256 lets me verify against known-good builds and
  detect corruption without ever seeing a byte of the game.

---

## What I will be able to conclude from the inventory

| From | I can determine |
|---|---|
| `GTAIV.exe` PE header | Format (PE), machine type and bitness, whether `LARGEADDRESSAWARE` is set — which governs how much RAM a native port could address |
| `GTAIV.exe` version resource + link timestamp | The patch level (1.0.x / 1.2.0.x) |
| DLL list | Whether this is a pre- or post-GFWL build; which middleware is present (Bink for video, etc.) |
| Directory markers | GTA IV standalone vs. EFLC vs. Complete Edition; whether TLAD/TBoGT are installed |
| `.rpf` / `.img` magic numbers | Archive versions (RPF2 vs. RPF3 audio), confirming the parsers needed |
| Archive sizes | The streaming budget, and which archives dominate |
| Presence of `paths*.ipl`, `handling.dat`, `timecyc.dat`, `navmeshes.img`, `vehicles.img`, `playerped.rpf`, `WeaponInfo.xml`, `skydome.wtd` | Whether every asset the browser port needs is actually there |
| Extension breakdown | Whether anything looks missing or unexpected |

**What the inventory cannot tell me** (say so explicitly rather than guessing):
whether files are corrupt in ways that preserve size, whether the install has
been modded, or anything about the *contents* of the archives. Those need
Phase 2 extraction logs.
