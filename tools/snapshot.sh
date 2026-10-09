#!/usr/bin/env bash
# Freeze the current site as a self-contained copy before updating to a new cycle.
#   tools/snapshot.sh 2026100812
# Writes snapshots/<cycle>/ with the three pages, assets and the data scripts they
# load, plus an "archived" banner on each page linking back to the live analysis.
set -euo pipefail
cyc="${1:?cycle being archived, e.g. 2026100812}"
root="$(cd "$(dirname "$0")/.." && pwd)"
dst="$root/snapshots/$cyc"
[ -e "$dst" ] && { echo "snapshots/$cyc already exists"; exit 1; }
mkdir -p "$dst/assets" "$dst/data"

cp "$root"/index.html "$root"/models.html "$root"/methods.html "$dst/"
cp "$root"/assets/* "$dst/assets/"
for f in $(grep -o 'data/[A-Za-z0-9_.-]*\.js' "$root/index.html" | sort -u); do cp "$root/$f" "$dst/$f"; done

label="$(date -u -d "${cyc:0:8} ${cyc:8:2}:00" '+%HZ %a %-d %b %Y')"
banner="<p class=\"note warn\" style=\"margin-top:16px\">Archived snapshot from the ${label} model cycle. Forecasts have changed since. <a href=\"../../\">See the latest analysis</a>.</p>"
for p in index.html models.html methods.html; do
  # The live-only pages (Latest NWS, Evacuations) are not snapshotted; point their nav links to the live ones.
  awk -v b="$banner" '{sub(/href="latest\.html"/, "href=\"../../latest.html\""); sub(/href="evacuations\.html"/, "href=\"../../evacuations.html\"")} {print} /<\/header>/ && !done {print "  " b; done=1}' "$dst/$p" > "$dst/$p.tmp"
  mv "$dst/$p.tmp" "$dst/$p"
done
echo "wrote snapshots/$cyc ($label)"
