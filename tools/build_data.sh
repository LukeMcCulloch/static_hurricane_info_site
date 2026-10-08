#!/usr/bin/env bash
# Build data/<storm>_<cycle>.json from NHC's public ATCF files.
#
#   tools/build_data.sh al092026 ISAIAS            # latest cycle in the a-deck
#   tools/build_data.sh al092026 ISAIAS 2026100812 # a specific cycle
#
# Sources (public domain, U.S. Government):
#   a-deck (model aids): https://ftp.nhc.noaa.gov/atcf/aid_public/a<storm>.dat.gz
#   b-deck (best track): https://ftp.nhc.noaa.gov/atcf/btk/b<storm>.dat
#
# For each model aid and forecast hour we keep the first row (rows repeat once
# per wind-radii threshold) and drop rows with VMAX <= 0, which ATCF uses for
# "no value" or a dissipated system. Lat/lon of 0 (intensity-only aids) -> null.
set -euo pipefail

storm="${1:?storm id, e.g. al092026}"
name="${2:?storm name, e.g. ISAIAS}"
want="${3:-}"

root="$(cd "$(dirname "$0")/.." && pwd)"
raw="$root/data/raw"
mkdir -p "$raw"

curl -fsS -o "$raw/a$storm.dat.gz" "https://ftp.nhc.noaa.gov/atcf/aid_public/a$storm.dat.gz"
curl -fsS -o "$raw/b$storm.dat"    "https://ftp.nhc.noaa.gov/atcf/btk/b$storm.dat"
gunzip -f "$raw/a$storm.dat.gz"

if [ -z "$want" ]; then
  want="$(awk -F', *' '$5=="OFCL"{print $3}' "$raw/a$storm.dat" | sort -u | tail -1)"
fi

out="$root/data/${storm}_${want}.json"

awk -F', *' -v cyc="$want" -v storm="$storm" -v name="$name" \
    -v fetched="$(date -u +%Y-%m-%dT%H:%MZ)" -v bfile="$raw/b$storm.dat" '
function deg(s,   h, v) {
  h = substr(s, length(s)); v = substr(s, 1, length(s) - 1) / 10
  if (v == 0) return "null"
  return (h == "S" || h == "W") ? -v : v
}
BEGIN {
  # best track: one row per synoptic time
  while ((getline line < bfile) > 0) {
    n = split(line, f, /, */)
    if (f[3] in bseen) continue
    bseen[f[3]] = 1
    best = best (best ? "," : "") sprintf("[\"%s\",%s,%s,%d,%d,\"%s\"]", f[3], deg(f[7]), deg(f[8]), f[9], f[10], f[11])
  }
}
$3 == cyc && ($9 + 0) > 0 {
  key = $5 SUBSEP $6
  if (key in seen) next
  seen[key] = 1
  if (!($5 in pts)) order[++nm] = $5
  pts[$5] = pts[$5] (pts[$5] ? "," : "") sprintf("[%d,%d,%s,%s]", $6, $9, deg($7), deg($8))
}
END {
  printf "{\"storm\":\"%s\",\"name\":\"%s\",\"cycle\":\"%s\",\"fetched\":\"%s\",\n", storm, name, cyc, fetched
  printf "\"best\":[%s],\n\"models\":{", best
  for (i = 1; i <= nm; i++) printf "%s\n\"%s\":[%s]", (i > 1 ? "," : ""), order[i], pts[order[i]]
  printf "}}\n"
}' "$raw/a$storm.dat" > "$out"

# Same data as a script, so the page also works when opened from disk.
{ printf 'window.ATCF = window.ATCF || {};\nwindow.ATCF["%s"] = ' "$want"; cat "$out"; printf ';\n'; } > "${out%.json}.js"

echo "wrote $out and ${out%.json}.js"
