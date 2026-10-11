# Gta-4-on-web

One tool in this repo: **an installer-free scanner that describes a GTA IV
installation without touching, copying, or uploading the game.**

It outputs a small text inventory (~1 MB) — filenames, sizes, hashes, and a few
format fingerprints. **No game content**, so it is safe to commit here.

---

## Run it

### Windows

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\gta4-inventory.ps1
```

If auto-detect fails, point it at the folder that contains `GTAIV.exe`
(on Steam that is the `GTAIV` **subfolder** of `Grand Theft Auto IV`):

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\gta4-inventory.ps1 `
  -GameDir "C:\Program Files (x86)\Steam\steamapps\common\Grand Theft Auto IV\GTAIV"
```

### Linux / macOS (Steam Proton, CrossOver, …)

```bash
chmod +x tools/gta4-inventory.sh
./tools/gta4-inventory.sh "/path/to/Grand Theft Auto IV/GTAIV"
```

Add `-NoHash` (Windows) or `-n` (Linux/macOS) to skip SHA-256 — seconds instead
of minutes.

It writes `tools/gta4-inventory/`:

| File | What is in it |
|---|---|
| `summary.txt` | executable format/bitness/LAA flag/version, DLLs, archive magic numbers, per-extension counts, edition markers, and which data files are present |
| `tree.txt` | directory tree, two levels, with sizes |
| `manifest.csv` | `relative_path, size_bytes, sha256` for every file |

**Start with `summary.txt`.**

---

## Put it in GitHub

```bash
git add tools/gta4-inventory
git commit -m "Add GTA IV installation inventory"
git push
```

That is the reliable way to hand it over — the analysis sandbox can always
`git fetch` this, whereas chat attachments do not always arrive.

---

## Do not commit

- The game
- Extracted assets (`web/assets/`, `web/data/`)
- Anything containing game content
