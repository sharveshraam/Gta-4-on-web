#!/usr/bin/env bash
#
# gta4-inventory.sh — produce a shareable INVENTORY of a GTA IV installation.
#
# Produces NO game content. Only filenames, sizes, hashes and format
# fingerprints. This is how a ~22 GB installation can be analysed without
# uploading, moving or redistributing a single game asset.
#
# Output (~1 MB of text, safe to commit or paste into a chat):
#   gta4-inventory/summary.txt   detected version, executable format/arch/
#                                LAA flag, archive magics, per-extension
#                                counts and sizes, key marker files
#   gta4-inventory/manifest.csv  relative path, size bytes, sha256
#   gta4-inventory/tree.txt      directory tree, two levels deep
#
# Usage:
#   ./tools/gta4-inventory.sh [GAME_DIR] [-n]
#     -n   skip SHA-256 (seconds instead of minutes)
#
# Examples:
#   ./tools/gta4-inventory.sh
#   ./tools/gta4-inventory.sh ~/.steam/steam/steamapps/common/Grand\ Theft\ Auto\ IV/GTAIV
#   ./tools/gta4-inventory.sh /path/to/install -n
#
# Read-only: opens files, reads at most a few header bytes, executes nothing.

set -uo pipefail

NOHASH=0
GAME_DIR=""
for arg in "$@"; do
  case "$arg" in
    -n|--no-hash) NOHASH=1 ;;
    -h|--help)    sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)            GAME_DIR="$arg" ;;
  esac
done

# ---------------------------------------------------------------- hashing tool

HASHER=""
if command -v sha256sum >/dev/null 2>&1; then HASHER="sha256sum"
elif command -v shasum   >/dev/null 2>&1; then HASHER="shasum -a 256"
fi
if [ "$NOHASH" -eq 0 ] && [ -z "$HASHER" ]; then
  echo "Warning: no sha256sum or shasum found; continuing without hashes." >&2
  NOHASH=1
fi

# ------------------------------------------------------------------ locate game

if [ -z "$GAME_DIR" ]; then
  CANDIDATES=(
    "$HOME/.steam/steam/steamapps/common/Grand Theft Auto IV/GTAIV"
    "$HOME/.local/share/Steam/steamapps/common/Grand Theft Auto IV/GTAIV"
    "$HOME/.steam/steam/steamapps/common/Grand Theft Auto IV Episodes from Liberty City/EFLC"
    "$HOME/.local/share/Steam/steamapps/common/Grand Theft Auto IV Episodes from Liberty City/EFLC"
    "$HOME/.wine/drive_c/Program Files (x86)/Steam/steamapps/common/Grand Theft Auto IV/GTAIV"
    "$HOME/.wine/drive_c/Program Files (x86)/Rockstar Games/Grand Theft Auto IV"
  )
  for c in "${CANDIDATES[@]}"; do
    if [ -f "$c/GTAIV.exe" ]; then GAME_DIR="$c"; break; fi
  done
fi

if [ -z "$GAME_DIR" ] || [ ! -d "$GAME_DIR" ]; then
  echo "GTA IV installation not found."
  echo
  echo "Pass the path explicitly. It is the folder containing GTAIV.exe —"
  echo "on Steam that is usually the 'GTAIV' SUBFOLDER of 'Grand Theft Auto IV':"
  echo
  echo "  ./tools/gta4-inventory.sh \"/path/to/Grand Theft Auto IV/GTAIV\""
  echo
  exit 1
fi

ROOT="$(cd "$GAME_DIR" && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/gta4-inventory"
mkdir -p "$OUT"

echo
echo "  GTA IV inventory"
echo "  root : $ROOT"
echo "  out  : $OUT"
echo

# --------------------------------------------------------------- PE header read

pe_field() {
  # $1 = file, $2 = field name
  local f="$1" field="$2"
  [ -f "$f" ] || { echo "unknown"; return; }

  # Must be at least 0x40 bytes
  local size; size=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
  [ "${size:-0}" -lt 64 ] 2>/dev/null && { echo "too small"; return; }

  local mz; mz=$(od -An -tx1 -N2 -j0 "$f" 2>/dev/null | tr -d ' \n')
  [ "$mz" != "4d5a" ] && { echo "not a PE/DOS executable"; return; }

  local lfanew; lfanew=$(od -An -tu4 -N4 -j60 "$f" 2>/dev/null | tr -d ' \n')
  [ -z "$lfanew" ] || [ "$lfanew" -lt 64 ] 2>/dev/null && { echo "DOS header only"; return; }

  local hex; hex=$(od -An -tx1 -N24 -j"$lfanew" "$f" 2>/dev/null | tr -d ' \n')
  [ "${#hex}" -lt 48 ] && { echo "truncated PE header"; return; }

  local sig="${hex:0:8}"
  [ "$sig" != "50450000" ] && { echo "MZ without PE signature"; return; }

  # little-endian 16-bit reads out of the hex byte string
  local machine_le="${hex:10:2}${hex:8:2}"
  local char_le="${hex:46:2}${hex:44:2}"
  local machine=$((16#$machine_le))
  local chars=$((16#$char_le))

  case "$field" in
    machine)
      case "$machine" in
        332)   echo "i386 (x86 32-bit)" ;;
        34404) echo "AMD64 (x86-64)" ;;
        448)   echo "ARM" ;;
        43620) echo "ARM64" ;;
        *)     printf '0x%04x\n' "$machine" ;;
      esac ;;
    bitness)
      if [ "$machine" -eq 34404 ] || [ "$machine" -eq 43620 ]; then echo "64-bit"; else echo "32-bit"; fi ;;
    laa)
      if [ $((chars & 0x20)) -ne 0 ]; then echo "YES"; else echo "no"; fi ;;
    subsystem)
      local optstart=$((lfanew + 24))
      local sub_le; sub_le=$(od -An -tx1 -N2 -j$((optstart + 68)) "$f" 2>/dev/null | tr -d ' \n')
      [ "${#sub_le}" -lt 4 ] && { echo "unknown"; return; }
      local subb=$((16#${sub_le:2:2}${sub_le:0:2}))
      case "$subb" in
        2) echo "GUI (Windows)" ;;
        3) echo "Console (CUI)" ;;
        9) echo "Windows CE" ;;
        *) printf '0x%x\n' "$subb" ;;
      esac ;;
    timestamp)
      local ts; ts=$(od -An -tu4 -N4 -j$((lfanew + 8)) "$f" 2>/dev/null | tr -d ' \n')
      if [ -n "$ts" ] && [ "$ts" -gt 0 ] 2>/dev/null; then
        # GNU coreutils uses -d @<epoch>; BSD/macOS uses -r <epoch>
        date -u -d "@$ts" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null \
          || date -u -r "$ts" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null \
          || echo "$ts (raw)"
      else
        echo "unknown"
      fi ;;
    *) echo "unknown" ;;
  esac
}

# ----------------------------------------------------- archive magic fingerprint

magic_of() {
  local f="$1"
  [ -f "$f" ] || { echo "(missing)"; return; }
  local h; h=$(od -An -tx1 -N4 -j0 "$f" 2>/dev/null | tr -d ' \n')
  local a; a=$(head -c4 "$f" 2>/dev/null | tr -d '\0')
  case "$a" in
    RPF2) echo "RPF2 - GTA IV standard archive"; return ;;
    RPF3) echo "RPF3 - GTA IV AUDIO archive";    return ;;
    RPF0) echo "RPF0 - Table Tennis archive";    return ;;
    RPF4) echo "RPF4 - Max Payne 3 archive";     return ;;
    RPF6) echo "RPF6 - RDR archive";             return ;;
    RPF7) echo "RPF7 - GTA V archive";           return ;;
    RPF8) echo "RPF8 - RDR2 archive";            return ;;
  esac
  [ "${#h}" -lt 8 ] && { echo "(too small)"; return; }
  local u32=$((16#${h:6:2}${h:4:2}${h:2:2}${h:0:2}))
  case "$u32" in
    843602774) echo "IMG2 (VER2) - RenderWare-era archive"; return ;;
    860049238) echo "IMG3 (VER3) - RAGE archive";           return ;;
  esac
  case "$h" in
    52494646*) echo "RIFF - audio container" ;;
    1a45dfa3) echo "EBML/Matroska - video container" ;;
    504b*)     echo "ZIP" ;;
    7f454c46)  echo "ELF - Linux executable" ;;
    *)         echo "unknown (0x$h)" ;;
  esac
}

# ------------------------------------------------------------------- manifest

CSV="$OUT/manifest.csv"
echo "relative_path,size_bytes,sha256" > "$CSV"

count=0
while IFS= read -r -d '' f; do
  rel="${f#$ROOT/}"
  size=$(wc -c < "$f" | tr -d ' ')
  sha=""
  if [ "$NOHASH" -eq 0 ]; then
    sha=$($HASHER "$f" 2>/dev/null | awk '{print $1}')
    [ -z "$sha" ] && sha="ERROR"
  fi
  esc=${rel//\"/\"\"}
  printf '"%s",%s,%s\n' "$esc" "$size" "$sha" >> "$CSV"
  count=$((count + 1))
done < <(find "$ROOT" -type f -print0 | sort -z)

echo "  manifest.csv   written ($count files)"

# --------------------------------------------------------------------- tree

TREE="$OUT/tree.txt"
{
  echo "GTA IV installation tree (2 levels, sizes summed). Root path redacted."
  echo "Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo
  for d in $(find "$ROOT" -mindepth 1 -maxdepth 1 -type d | sort); do
    n=$(find "$d" -type f | wc -l | tr -d ' ')
    s=$(find "$d" -type f -exec wc -c {} + 2>/dev/null | tail -1 | awk '{print $1}')
    [ -z "$s" ] && s=0
    printf '%-44s %7s files %14s bytes\n' "$(basename "$d")/" "$n" "$s"
    for d2 in $(find "$d" -mindepth 1 -maxdepth 1 -type d | sort); do
      n2=$(find "$d2" -type f | wc -l | tr -d ' ')
      s2=$(find "$d2" -type f -exec wc -c {} + 2>/dev/null | tail -1 | awk '{print $1}')
      [ -z "$s2" ] && s2=0
      printf '  %-42s %7s files %14s bytes\n' "$(basename "$d2")/" "$n2" "$s2"
    done
  done
} > "$TREE"
echo "  tree.txt       written"

# ------------------------------------------------------------------ summary

SUM="$OUT/summary.txt"
TOTAL=$(find "$ROOT" -type f -exec wc -c {} + 2>/dev/null | tail -1 | awk '{print $1}')
[ -z "$TOTAL" ] && TOTAL=0

{
echo "================================================================================"
echo " GTA IV INSTALLATION INVENTORY"
echo "================================================================================"
echo " Generated          : $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo " Scanner            : tools/gta4-inventory.sh"
echo " Root path          : (redacted - not recorded)"
echo " Total files        : $count"
echo " Total size         : $(awk -v b="$TOTAL" 'BEGIN{printf "%.2f GB (%d bytes)", b/1073741824, b}')"
echo
echo " NOTE ON SHARING"
echo " ----------------"
echo " This file contains filenames, sizes and hashes ONLY. It contains no game"
echo " content and is safe to commit to a public repository or paste into a chat."
echo " The installation root path has been deliberately redacted."
echo

echo "================================================================================"
echo " EXECUTABLES"
echo "================================================================================"
for name in GTAIV.exe LaunchGTAIV.exe EFLC.exe LaunchEFLC.exe; do
  p="$ROOT/$name"
  if [ -f "$p" ]; then
    echo
    echo " $name"
    echo "   Size:             $(wc -c < "$p" | tr -d ' ') bytes"
    echo "   Format:           PE (Portable Executable)"
    echo "   Machine:          $(pe_field "$p" machine)"
    echo "   Bitness:          $(pe_field "$p" bitness)"
    echo "   LargeAddressAware: $(pe_field "$p" laa)"
    echo "   Subsystem:        $(pe_field "$p" subsystem)"
    echo "   LinkTimestamp:    $(pe_field "$p" timestamp)"
  fi
done
echo

echo "================================================================================"
echo " NATIVE DLL DEPENDENCIES / MIDDLEWARE MARKERS"
echo "================================================================================"
for m in binkw32.dll bink2w32.dll xlive.dll d3d9.dll d3dx9_40.dll d3dx9_41.dll \
         d3dx9_42.dll d3dx9_43.dll xinput1_3.dll x3daudio1_7.dll dsound.dll \
         GTAIVGDF.dll LiveTokenHelper.dll GameuxInstallHelper.dll Paul.dll \
         DFA.dll 1911.dll openal32.dll OpenAL32.dll dinput8.dll; do
  if [ -f "$ROOT/$m" ]; then
    printf '   %-26s present   %12s bytes\n' "$m" "$(wc -c < "$ROOT/$m" | tr -d ' ')"
  fi
done
echo
echo "   All DLLs in root: $(cd "$ROOT" && ls -1 *.dll 2>/dev/null | tr '\n' ' ')"
echo

echo "================================================================================"
echo " ARCHIVE FINGERPRINTS (first 4 bytes; identifies the container format)"
echo "================================================================================"
echo
find "$ROOT" -type f \( -iname '*.rpf' -o -iname '*.img' \) -print0 \
  | sort -z \
  | while IFS= read -r -d '' a; do
      rel="${a#$ROOT/}"
      printf '   %-56s %s\n' "$rel" "$(magic_of "$a")"
    done 2>/dev/null | head -60
echo
echo "   (showing first 60; run the scanner on the full set for all)"
echo

echo "================================================================================"
echo " FILE COUNT AND SIZE BY EXTENSION (top 40 by count)"
echo "================================================================================"
printf '   %-14s %8s %16s %10s\n' EXT COUNT BYTES GB
find "$ROOT" -type f -print0 2>/dev/null \
  | while IFS= read -r -d '' f; do
      e="${f##*.}"
      [ "$e" = "$f" ] && e="(none)"
      printf '%s\t%s\n' "${e,,}" "$(wc -c < "$f" | tr -d ' ')"
    done \
  | awk -F'\t' '{c[$1]++; s[$1]+=$2} END {for (k in c) printf "%s\t%d\t%d\n", k, c[k], s[k]}' \
  | sort -t$'\t' -k2 -rn \
  | head -40 \
  | awk -F'\t' '{printf "   %-14s %8s %16s %10.3f\n", $1, $2, $3, $3/1073741824}'
echo

echo "================================================================================"
echo " EDITION AND VERSION MARKERS"
echo "================================================================================"
for d in common/data TLAD TBoGT EFLC pc common common/shaders common/shaders/db \
         pc/audio pc/audio/sfx pc/audio/radio pc/models/cdimages pc/textures \
         pc/data/cdimages Installers; do
  if [ -d "$ROOT/$d" ]; then
    printf '   %-40s %s\n' "$d" "PRESENT"
  else
    printf '   %-40s %s\n' "$d" "-"
  fi
done
echo
if [ -f "$ROOT/files.txt" ]; then
  echo " files.txt exists ($(wc -c < "$ROOT/files.txt" | tr -d ' ') bytes) - first 5 lines:"
  head -5 "$ROOT/files.txt" | sed 's/^/   | /'
fi
if [ -f "$ROOT/commandline.txt" ]; then
  echo
  echo " commandline.txt contents:"
  sed 's/^/   | /' "$ROOT/commandline.txt"
fi
echo

echo "================================================================================"
echo " KEY DATA FILES USED BY THE BROWSER PORT (presence + size)"
echo "================================================================================"
for k in common/data/gta.dat common/data/handling.dat common/data/timecyc.dat \
         common/data/WeaponInfo.xml common/data/vehicles.ide common/data/carcols.dat \
         common/data/peds.ide common/data/default.ide \
         common/data/maps/paths.ipl common/data/maps/paths2.ipl \
         common/data/maps/paths3.ipl common/data/maps/paths4.ipl \
         pc/data/cdimages/navmeshes.img pc/models/cdimages/vehicles.img \
         pc/models/cdimages/weapons.img pc/models/cdimages/playerped.rpf \
         pc/models/cdimages/peds.img pc/textures/skydome.wtd; do
  p="$ROOT/$k"
  if [ -f "$p" ]; then
    printf '   %-46s %12s bytes\n' "$k" "$(wc -c < "$p" | tr -d ' ')"
  elif [ -d "$p" ]; then
    printf '   %-46s DIR, %s files\n' "$k" "$(find "$p" -type f | wc -l | tr -d ' ')"
  else
    printf '   %-46s %s\n' "$k" "MISSING"
  fi
done
echo
echo "================================================================================"
echo " END OF INVENTORY"
echo "================================================================================"
} > "$SUM"

echo "  summary.txt    written"
echo
echo "  Done. Output in:"
echo "    $OUT"
echo
for f in "$OUT"/*; do
  printf '      %-16s %10s bytes\n' "$(basename "$f")" "$(wc -c < "$f" | tr -d ' ')"
done
echo
echo "  NEXT STEP"
echo "  Read summary.txt first. Then share either:"
echo "    - summary.txt + tree.txt  (small, paste straight into chat), or"
echo "    - the whole gta4-inventory folder (commit it, or paste the text)."
echo
echo "  Do NOT upload the game itself, and do not commit web/assets or web/data."
echo
