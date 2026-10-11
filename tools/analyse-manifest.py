#!/usr/bin/env python3
"""
analyse-manifest.py — turn a GTA IV installation manifest into a structured,
shareable inventory.

Reads a CSV of (path, size, sha256) — the output of tools/gta4-inventory.ps1 /
.sh, or anything else with comparable columns — and writes GAME_FILE_INVENTORY.md.

Contains no game content. Reads text only.

Usage:
    python3 tools/analyse-manifest.py inventory/manifest.csv
    python3 tools/analyse-manifest.py manifest.csv -o GAME_FILE_INVENTORY.md
    python3 tools/analyse-manifest.py manifest.csv --print     # summary to stdout

Column detection is automatic; common header spellings are accepted and a
headerless CSV is handled (path, size, sha256 in that order).
"""

import argparse
import csv
import os
import re
import sys
from collections import Counter, defaultdict

# --------------------------------------------------------------------- helpers

PATH_KEYS = {"relative_path", "relpath", "path", "file", "filename", "name",
             "fullpath", "full_path", "relative path", "filepath", "file path"}
SIZE_KEYS = {"size_bytes", "size", "bytes", "length", "filesize", "file size",
             "size (bytes)", "sizeinbytes"}
HASH_KEYS = {"sha256", "sha-256", "sha256sum", "hash", "checksum", "sha", "sha 256"}


def _norm(k):
    return (k or "").strip().strip('"').strip("'").lower()


def detect_columns(header):
    """Map header names to (path_idx, size_idx, hash_idx). Any may be None."""
    p = s = h = None
    for i, col in enumerate(header):
        n = _norm(col)
        if p is None and n in PATH_KEYS:
            p = i
        elif s is None and n in SIZE_KEYS:
            s = i
        elif h is None and n in HASH_KEYS:
            h = i
    return p, s, h


def human(n):
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return f"{n:,.2f} {unit}" if unit != "B" else f"{int(n):,} B"
        n /= 1024.0


def norm_path(p):
    """Normalise a manifest path to forward slashes, relative, no leading ./"""
    p = (p or "").strip().strip('"')
    p = p.replace("\\", "/")
    # Strip a leading drive letter or absolute prefix if present
    p = re.sub(r"^[A-Za-z]:", "", p)
    p = p.lstrip("/")
    while p.startswith("./"):
        p = p[2:]
    return p


def parent_dirs(path):
    parts = path.split("/")[:-1]
    return "/".join(parts)


# Segments that identify the true game root. If a manifest was captured with
# absolute paths (C:\Games\Grand Theft Auto IV\GTAIV\common\...), everything
# before the first of these is a prefix we must strip.
ROOT_MARKERS = {"common", "pc", "tlad", "tbogt", "eflc", "installers",
                "update", "redistributables", "docs", "manual"}
ROOT_FILES = {"gtaiv.exe", "launchgtaiv.exe", "eflc.exe", "launcheflc.exe",
              "binkw32.dll", "bink2w32.dll", "gtaivgdf.dll", "commandline.txt",
              "files.txt", "lang.ini", "readme.txt", "xlive.dll", "d3d9.dll"}


def find_root_offset(paths):
    """Return the number of leading path segments shared by every entry before
    the game root. Uses the modal position of a recognised root marker."""
    votes = Counter()
    for p in paths:
        segs = p.split("/")
        for i, s in enumerate(segs):
            sl = s.lower()
            if sl in ROOT_MARKERS:
                votes[i] += 1
                break
            if sl in ROOT_FILES and i == len(segs) - 1:
                votes[i] += 1
                break
    if not votes:
        return 0
    offset, hits = votes.most_common(1)[0]
    # Only trust it if a decent fraction of files agree
    return offset if hits >= max(1, len(paths) * 0.25) else 0


def strip_root(paths):
    offset = find_root_offset(paths)
    if offset == 0:
        return paths, ""
    out = []
    prefix = ""
    for p in paths:
        segs = p.split("/")
        if len(segs) > offset:
            if not prefix:
                prefix = "/".join(segs[:offset]) + "/"
            out.append("/".join(segs[offset:]))
        else:
            out.append(p)
    return out, prefix


# ------------------------------------------------------------------ key files

KEY_FILES = [
    ("World definition (gta.dat)",        "common/data/gta.dat"),
    ("Vehicle handling",                  "common/data/handling.dat"),
    # Complete Edition keeps timecyc under pc/data - common/data/timecyc.dat is
    # the wrong path and yields a false MISSING.
    ("Timecycle / lighting (pc/data)",    "pc/data/timecyc.dat"),
    ("Timecycle / lighting (common/data)", "common/data/timecyc.dat"),
    ("Weapon stats",                      "common/data/WeaponInfo.xml"),
    ("Vehicle catalogue",                 "common/data/vehicles.ide"),
    ("Vehicle colours",                   "common/data/carcols.dat"),
    ("Ped catalogue",                     "common/data/peds.ide"),
    ("Default item definitions",          "common/data/default.ide"),
    ("Road network 1",                    "common/data/maps/paths.ipl"),
    ("Road network 2",                    "common/data/maps/paths2.ipl"),
    ("Boat lanes",                        "common/data/maps/paths3.ipl"),
    ("Network paths 4",                   "common/data/maps/paths4.ipl"),
    ("Ped navmesh",                       "pc/data/cdimages/navmeshes.img"),
    ("Vehicles",                          "pc/models/cdimages/vehicles.img"),
    ("Weapons",                           "pc/models/cdimages/weapons.img"),
    ("Player model",                      "pc/models/cdimages/playerped.rpf"),
    # GTA IV has no peds.img - peds are assembled from componentpeds.img.
    ("Ped components",                    "pc/models/cdimages/componentpeds.img"),
    ("Cutscene animation",                "pc/anim/cuts.img"),
    ("Sky textures",                      "pc/textures/skydome.wtd"),
]

MOD_MARKERS = [
    ("ScriptHook (ASI loader + hook)",    "ScriptHook.dll"),
    ("ScriptHookDotNet",                  "ScriptHookDotNet.dll"),
    ("ASI loader via dinput8",            "dinput8.dll"),
    ("ASI loader via dsound",             "dsound.dll"),
    ("FusionFix (dinput8 hook)",          "dinput8.dll"),
    ("IV-SDK .NET",                       "IVSDKDotNet.asi"),
    ("ASI mod present",                   None),  # special: any *.asi
]

GFWL_MARKERS = ["xlive.dll", "LiveTokenHelper.dll", "GFWLDownload.dll",
                "GameuxInstallHelper.dll", "XLiveRedist.msi"]

EPISODE_DIRS = {"TLAD": "The Lost and Damned", "TBoGT": "The Ballad of Gay Tony",
                "EFLC": "Episodes from Liberty City"}


# --------------------------------------------------------------------- reader

def read_manifest(path):
    rows = []
    with open(path, "r", encoding="utf-8", errors="replace", newline="") as fh:
        sample = fh.read(8192)
        fh.seek(0)
        delim = "\t" if sample.count("\t") > sample.count(",") else ","
        reader = csv.reader(fh, delimiter=delim)
        try:
            header = next(reader)
        except StopIteration:
            return rows, (None, None, None)

        p, s, h = detect_columns(header)
        first = _norm(header[0] if header else "")
        header_looks_like_data = (
            p is None
            or (p == 0 and s is None and h is None and not first.endswith((".exe", ".dll", ".dat", ".rpf", ".img", ".txt")))
        )

        if header_looks_like_data:
            # No header row: assume path, size, sha256
            fh.seek(0)
            reader = csv.reader(fh, delimiter=delim)
            p, s, h = 0, (1 if len(header) > 1 else None), (2 if len(header) > 2 else None)
        else:
            if p is None:
                p = 0
            if s is None and len(header) > 1:
                s = 1
            if h is None and len(header) > 2:
                h = 2

        for r in reader:
            if not r or not any(c.strip() for c in r):
                continue
            try:
                rel = norm_path(r[p]) if p is not None and p < len(r) else ""
            except IndexError:
                continue
            if not rel:
                continue
            size = 0
            if s is not None and s < len(r):
                raw = r[s].strip().replace(",", "")
                m = re.match(r"^(-?\d+)", raw)
                if m:
                    size = max(0, int(m.group(1)))
            sha = ""
            if h is not None and h < len(r):
                sha = r[h].strip().lower()
            rows.append({"path": rel, "size": size, "sha256": sha})
    return rows, (p, s, h)


# ------------------------------------------------------------------ analysis

def analyse(rows):
    r = {}
    # Normalise away any install prefix (e.g. "Grand Theft Auto IV/GTAIV/")
    stripped, prefix = strip_root([x["path"] for x in rows])
    for x, s in zip(rows, stripped):
        x["path"] = s
    r["root_prefix"] = prefix
    r["count"] = len(rows)
    r["total"] = sum(x["size"] for x in rows)
    r["has_hash"] = sum(1 for x in rows if x["sha256"]) / max(1, len(rows))

    paths = {x["path"]: x for x in rows}
    lower = {p.lower(): p for p in paths}

    # top-level directories
    top = defaultdict(lambda: [0, 0])
    for x in rows:
        parts = x["path"].split("/")
        key = parts[0] if len(parts) > 1 else "(root files)"
        top[key][0] += 1
        top[key][1] += x["size"]
    r["top"] = dict(top)

    # extensions
    ext_count = Counter()
    ext_size = Counter()
    for x in rows:
        e = os.path.splitext(x["path"])[1].lower() or "(none)"
        ext_count[e] += 1
        ext_size[e] += x["size"]
    r["ext_count"] = ext_count
    r["ext_size"] = ext_size

    # executables
    r["exes"] = []
    for name in ("GTAIV.exe", "LaunchGTAIV.exe", "EFLC.exe", "LaunchEFLC.exe"):
        if name.lower() in lower:
            p = lower[name.lower()]
            r["exes"].append((p, paths[p]["size"], paths[p]["sha256"]))

    # root DLLs
    r["root_dlls"] = sorted(
        (os.path.basename(p), paths[p]["size"])
        for p in paths
        if p.lower().endswith(".dll") and "/" not in p
    )

    # archives
    arch = [x for x in rows if x["path"].lower().endswith((".rpf", ".img"))]
    arch.sort(key=lambda x: -x["size"])
    r["archives"] = arch
    r["archive_total"] = sum(x["size"] for x in arch)

    # audio
    audio = [x for x in rows if x["path"].lower().startswith("pc/audio/")]
    r["audio_files"] = audio
    r["audio_total"] = sum(x["size"] for x in audio)
    sfx = [x for x in audio if "/sfx" in x["path"].lower()]
    radio = [x for x in audio if "/radio" in x["path"].lower()]
    r["sfx"] = sfx
    r["radio"] = radio

    # key files
    r["key"] = []
    for label, rel in KEY_FILES:
        if rel.lower() in lower:
            p = lower[rel.lower()]
            r["key"].append((label, rel, True, paths[p]["size"], paths[p]["sha256"]))
        else:
            r["key"].append((label, rel, False, 0, ""))

    # edition markers
    r["episodes"] = {}
    for d, name in EPISODE_DIRS.items():
        hits = [x for x in rows if x["path"].lower().startswith(d.lower() + "/")]
        if hits:
            r["episodes"][d] = (name, len(hits), sum(x["size"] for x in hits))
    r["has_common"] = any(x["path"].lower().startswith("common/") for x in rows)
    r["has_pc"] = any(x["path"].lower().startswith("pc/") for x in rows)

    # GFWL / mod markers
    r["gfwl"] = [m for m in GFWL_MARKERS if m.lower() in lower]
    r["asi_mods"] = [x["path"] for x in rows if x["path"].lower().endswith(".asi")]
    r["mod_dlls"] = [(lbl, f) for lbl, f in MOD_MARKERS if f and f.lower() in lower]

    # version-ish hints from names
    r["hint_files"] = []
    for name in ("files.txt", "commandline.txt", "lang.ini", "readme.txt",
                 "gtaiv.exe.cat", "gtaiv.exe.cfg"):
        if name.lower() in lower:
            p = lower[name.lower()]
            r["hint_files"].append((p, paths[p]["size"]))

    # scripts (.sco) anywhere
    r["sco"] = [x for x in rows if x["path"].lower().endswith(".sco")]

    # largest files overall
    r["largest"] = sorted(rows, key=lambda x: -x["size"])[:25]

    return r


# -------------------------------------------------------------------- render

def render(r, src):
    L = []
    A = L.append

    A("# GTA IV installation — structured inventory")
    A("")
    A(f"Source manifest: `{src}`  ")
    A(f"Files: **{r['count']:,}**  ·  Total size: **{human(r['total'])}**  ·  "
      f"SHA-256 coverage: **{r['has_hash']*100:.0f}%**")
    if r["root_prefix"]:
        A(f"  ")
        A(f"Install prefix detected and stripped from all paths: `{r['root_prefix']}`")
    A("")
    A("> Generated by `tools/analyse-manifest.py` from a name/size/hash manifest.")
    A("> **No game content is contained in or reproduced by this document.**")
    A("> Version is inferred from structure only — a name/size manifest cannot")
    A("> establish patch level on its own. See *Version determination* below.")
    A("")

    # ---- edition
    A("## 1. Edition and layout")
    A("")
    A(f"- `common/` present: **{r['has_common']}**")
    A(f"- `pc/` present: **{r['has_pc']}**")
    if r["episodes"]:
        for d, (name, n, s) in sorted(r["episodes"].items()):
            A(f"- `{d}/` present: **YES** — {name} ({n:,} files, {human(s)})")
    else:
        A("- Episode directories: **none found**")
    A("")
    if r["episodes"] and r["has_pc"]:
        A("**Interpretation:** this looks like **GTA IV: The Complete Edition** "
          "(base game + both episodes), which is the layout `gta4-webmap` targets.")
    elif r["has_pc"]:
        A("**Interpretation:** GTA IV base installation (no episode directories).")
    else:
        A("**Interpretation:** layout not recognised as a standard PC install — "
          "check the manifest root.")
    A("")

    # ---- executables
    A("## 2. Executables and root modules")
    A("")
    if r["exes"]:
        A("| File | Size | SHA-256 |")
        A("|---|---|---|")
        for p, s, h in r["exes"]:
            A(f"| `{p}` | {s:,} B | `{h[:16]}…` |" if h else f"| `{p}` | {s:,} B | — |")
    else:
        A("**No `GTAIV.exe` / `EFLC.exe` found in the manifest.** The manifest root "
          "may not be the game root, or the scan was run one level too high/low.")
    A("")
    A("**Architecture note:** executable bitness and the `LARGEADDRESSAWARE` flag "
      "cannot be read from a name/size manifest — they live in the PE header. Run "
      "`tools/gta4-inventory.ps1`, which parses them, or the report's §3.1 "
      "(GTA IV PC is a 32-bit Direct3D 9.0c executable per PCGamingWiki).")
    A("")

    # ---- root dlls
    A("### Native modules in the install root")
    A("")
    if r["root_dlls"]:
        A("| DLL | Size |")
        A("|---|---|")
        for n, s in r["root_dlls"]:
            A(f"| `{n}` | {s:,} B |")
    else:
        A("*(none listed)*")
    A("")

    # ---- version determination
    A("## 3. Version determination")
    A("")
    A("A name/size manifest **cannot** by itself establish the patch level. What it "
      "can do is constrain it:")
    A("")
    if r["gfwl"]:
        A(f"- **Games for Windows Live modules present:** {', '.join('`'+m+'`' for m in r['gfwl'])}.")
        A("  → Suggests a **pre-2020 build** (1.0.x / 1.1.x). GFWL was removed in the "
          "2020-03-19 Complete Edition update.")
    else:
        A("- **No GFWL modules found** (`xlive.dll` and friends).")
        A("  → Consistent with **GTA IV: Complete Edition 1.2.0.x** (post-GFWL).")
    A(f"- Episode directories: **{', '.join(r['episodes']) if r['episodes'] else 'none'}**")
    A("")
    A("**To pin the version exactly,** either:")
    A("")
    A("1. Run `tools/gta4-inventory.ps1` — it reads `GTAIV.exe`'s PE version resource "
      "and link timestamp, and reports ProductVersion / FileVersion directly.")
    A("2. Or read the version in-game / from the launcher and tell me.")
    A("3. Or share the SHA-256 of `GTAIV.exe` (from `manifest.csv`) so it can be "
      "compared against a community hash database.")
    A("")
    if r["exes"]:
        p, s, h = r["exes"][0]
        if h:
            A(f"`GTAIV.exe` SHA-256 (for comparison): `{h}`")
            A("")
    if r["hint_files"]:
        A("Version-adjacent files present:")
        A("")
        for p, s in r["hint_files"]:
            A(f"- `{p}` ({s:,} B)")
        A("")

    # ---- archives
    A("## 4. Archive inventory (`.rpf` / `.img`)")
    A("")
    A(f"- Archives: **{len(r['archives']):,}**")
    A(f"- Combined size: **{human(r['archive_total'])}** "
      f"({r['archive_total']/max(1,r['total'])*100:.1f}% of the install)")
    A("")
    A("**25 largest archives:**")
    A("")
    A("| # | Archive | Size |")
    A("|---|---|---|")
    for i, x in enumerate(r["archives"][:25], 1):
        A(f"| {i} | `{x['path']}` | {human(x['size'])} |")
    A("")
    A("> Archive *magic* (RPF2 vs RPF3 vs IMG3) cannot be read from a manifest — it "
      "needs the first 4 bytes. `tools/gta4-inventory.ps1` reports it.")
    A("")

    # ---- key files
    A("## 5. Data files the browser port depends on")
    A("")
    A("| Purpose | Expected path | Status | Size |")
    A("|---|---|---|---|")
    for label, rel, ok, size, _h in r["key"]:
        A(f"| {label} | `{rel}` | {'**PRESENT**' if ok else 'MISSING'} | "
          f"{human(size) if ok else '—'} |")
    missing = [k for k in r["key"] if not k[2]]
    A("")
    if missing:
        A(f"**{len(missing)} of {len(r['key'])} expected files are absent.** "
          "Confirm the manifest root is the folder containing `GTAIV.exe`; if it is, "
          "these are genuinely missing and the corresponding port subsystem will not work.")
    else:
        A("**All expected data files are present.** The asset side of the recommended "
          "port path is satisfied.")
    A("")

    # ---- audio
    A("## 6. Audio")
    A("")
    A(f"- Files under `pc/audio/`: **{len(r['audio_files']):,}** ({human(r['audio_total'])})")
    A(f"- SFX: **{len(r['sfx']):,}** files ({human(sum(x['size'] for x in r['sfx']))})")
    A(f"- Radio: **{len(r['radio']):,}** files ({human(sum(x['size'] for x in r['radio']))})")
    A("")
    A("GTA IV PC audio is **not** AWC (that arrived with Red Dead Redemption); it is "
      "stored in RPF3 archives under `pc/audio/` as `.ivaud` streams. This is the "
      "subsystem `gta4-webmap` does not implement at all.")
    A("")

    # ---- scripts
    A("## 7. Mission scripts")
    A("")
    A(f"- `.sco` (compiled RAGE script) files in the manifest: **{len(r['sco']):,}**")
    for x in sorted(r["sco"], key=lambda x: -x["size"])[:10]:
        A(f"  - `{x['path']}` ({human(x['size'])})")
    if not r["sco"]:
        A("  *(none at the top level of this manifest — most `.sco` files live inside "
          "archives and will not appear in a file listing)*")
    A("")

    # ---- mods
    A("## 8. Modification markers")
    A("")
    if r["mod_dlls"] or r["asi_mods"]:
        A("Signs the install may be modded:")
        A("")
        for lbl, f in r["mod_dlls"]:
            A(f"- {lbl} — `{f}`")
        for p in r["asi_mods"][:20]:
            A(f"- ASI plugin — `{p}`")
        A("")
        A("**Recommendation:** verify against a clean install before drawing "
          "conclusions from hashes, and do not port from a modded tree.")
    else:
        A("No ScriptHook / ASI-loader / ASI-plugin markers found. The install appears "
          "clean on this evidence.")
    A("")

    # ---- extensions
    A("## 9. Composition by extension")
    A("")
    A("| Extension | Files | Total size |")
    A("|---|---|---|")
    for e, c in r["ext_count"].most_common(30):
        A(f"| `{e}` | {c:,} | {human(r['ext_size'][e])} |")
    A("")

    # ---- top level dirs
    A("## 10. Top-level layout")
    A("")
    A("| Directory | Files | Size |")
    A("|---|---|---|")
    for k, (n, s) in sorted(r["top"].items(), key=lambda kv: -kv[1][1]):
        A(f"| `{k}/` | {n:,} | {human(s)} |")
    A("")

    # ---- largest files
    A("## 11. Largest files overall")
    A("")
    A("| # | File | Size |")
    A("|---|---|---|")
    for i, x in enumerate(r["largest"], 1):
        A(f"| {i} | `{x['path']}` | {human(x['size'])} |")
    A("")

    A("---")
    A("")
    A("*End of inventory. Generated by `tools/analyse-manifest.py`. Contains no game content.*")
    return "\n".join(L) + "\n"


def print_summary(r):
    print()
    print(f"  Files          : {r['count']:,}")
    print(f"  Total size     : {human(r['total'])}")
    print(f"  SHA-256        : {r['has_hash']*100:.0f}% covered")
    print(f"  Archives       : {len(r['archives']):,} ({human(r['archive_total'])})")
    print(f"  Audio files    : {len(r['audio_files']):,} ({human(r['audio_total'])})")
    print(f"  Episodes       : {', '.join(r['episodes']) if r['episodes'] else 'none'}")
    print(f"  GFWL modules   : {', '.join(r['gfwl']) if r['gfwl'] else 'none (post-2020 build?)'}")
    miss = [k[1] for k in r["key"] if not k[2]]
    print(f"  Key files      : {len(r['key']) - len(miss)}/{len(r['key'])} present")
    if miss:
        for m in miss:
            print(f"      MISSING: {m}")
    print()


def main():
    ap = argparse.ArgumentParser(description="Analyse a GTA IV installation manifest.")
    ap.add_argument("manifest", nargs="?", default="inventory/manifest.csv",
                    help="path to manifest.csv (default: inventory/manifest.csv)")
    ap.add_argument("-o", "--out", default="GAME_FILE_INVENTORY.md",
                    help="output markdown file (default: GAME_FILE_INVENTORY.md)")
    ap.add_argument("--print", dest="do_print", action="store_true",
                    help="print the summary to stdout as well")
    args = ap.parse_args()

    if not os.path.exists(args.manifest):
        sys.exit(f"Manifest not found: {args.manifest}\n"
                 f"Usage: python3 tools/analyse-manifest.py <path/to/manifest.csv>")

    rows, cols = read_manifest(args.manifest)
    if not rows:
        sys.exit(f"No rows parsed from {args.manifest} (detected columns: {cols})")

    r = analyse(rows)
    print_summary(r)

    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(render(r, args.manifest))
    print(f"  Wrote {args.out}")
    print()


if __name__ == "__main__":
    main()
