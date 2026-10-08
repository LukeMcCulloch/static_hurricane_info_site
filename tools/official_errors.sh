#!/usr/bin/env bash
# Empirical NHC official (OFCL) intensity errors, from archived a-decks and
# final best tracks:
#
#   tools/official_errors.sh 2023 2024 2025
#
# Writes data/ofcl_errors.csv: storm,cycle,tau,ofcl,best,err  (err = OFCL - best)
# A forecast verifies only when the system is a tropical or subtropical cyclone
# (TD TS HU SD SS) at both the initial and the verifying time, roughly as NHC
# does in its annual verification. Run spread_climatology.sh first (it
# downloads the a-decks this script reuses).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
arch="$root/data/raw/archive"
mkdir -p "$arch"
out="$root/data/ofcl_errors.csv"

for y in "$@"; do
  for f in $(curl -fsS "https://ftp.nhc.noaa.gov/atcf/archive/$y/" | grep -o 'bal[0-9]*\.dat\.gz' | sort -u); do
    [ -s "$arch/$f" ] || curl -fsS -o "$arch/$f" "https://ftp.nhc.noaa.gov/atcf/archive/$y/$f"
  done
done

echo "storm,cycle,tau,ofcl,best,err" > "$out"
{
  for f in "$arch"/bal*.dat.gz; do gzip -dc "$f" | sed 's/^/B,/'; done
  for f in "$arch"/aal*.dat.gz; do gzip -dc "$f" | { grep ', OFCL,' || true; } | sed 's/^/A,/'; done
} | awk -F', *' '
function addh(t, h) {   # YYYYMMDDHH + h hours, all in UTC
  return strftime("%Y%m%d%H", mktime(substr(t,1,4) " " substr(t,5,2) " " substr(t,7,2) " " substr(t,9,2) " 0 0", 1) + h * 3600, 1)
}
BEGIN { tc["TD"] = tc["TS"] = tc["HU"] = tc["SD"] = tc["SS"] = 1 }
$1 == "B" {
  k = $2 $3 SUBSEP $4
  if (!(k in bv)) { bv[k] = $10 + 0; bt[k] = $12 }
  next
}
$1 == "A" && $10 + 0 > 0 {
  tau = $7 + 0
  if (tau !~ /^(12|24|36|48|60|72|96|120)$/) next
  k = $2 $3 SUBSEP $4 SUBSEP tau
  if (k in done) next
  done[k] = 1
  st = $2 $3
  ki = st SUBSEP $4; kv = st SUBSEP addh($4, tau)
  if (!(ki in bt) || !(kv in bt) || !(bt[ki] in tc) || !(bt[kv] in tc)) next
  printf "%s%s,%s,%d,%d,%d,%d\n", $2, substr($4,1,4), $4, tau, $10, bv[kv], $10 - bv[kv]
}' >> "$out"

echo "wrote $out ($(($(wc -l < "$out") - 1)) verifying forecasts)"
