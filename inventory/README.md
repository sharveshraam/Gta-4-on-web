# Drop your manifest here

Put the output of `tools/gta4-inventory.ps1` (or `.sh`) in this folder:

```
inventory/
├── manifest.csv      ← required
├── summary.txt       ← recommended (has the PE header + archive magic facts)
└── tree.txt          ← optional
```

Then **commit and push** them:

```bash
git add inventory/
git commit -m "Add GTA IV installation inventory"
git push
```

These are plain-text name/size/hash listings with **no game content**, so they are
safe to commit to this public repository.

## Why this folder, and not a file upload

Direct chat uploads do not reliably reach the analysis sandbox. A commit to this
branch does — the sandbox can always `git fetch` from GitHub.

## What happens next

```bash
python3 tools/analyse-manifest.py inventory/manifest.csv
```

writes `GAME_FILE_INVENTORY.md` at the repo root — a structured inventory covering
edition, layout, archive inventory, audio, scripts, mod markers, and a
present/missing check for every data file the browser port depends on.

## Do NOT put here

- The game itself
- Extracted assets (`web/assets/`, `web/data/`)
- Anything with game content in it
