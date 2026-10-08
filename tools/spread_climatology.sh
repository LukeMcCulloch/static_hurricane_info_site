#!/usr/bin/env bash
# How unusual is the model disagreement? Compute intensity-guidance spread for
# every Atlantic forecast cycle in past seasons, from NHC's archived a-decks.
#
#   tools/spread_climatology.sh 2023 2024 2025
#
# Writes data/spread_climatology.csv with one row per (storm, cycle, tau):
#   storm,cycle,tau,init_vmax,n,mean,sd,range
#
# Fixed aid set (all present 2023-2025, so seasons are comparable):
#   HFAI HFBI HWFI HMNI CTCI  regional physics
#   AVNI                      global physics
#   DSHP LGEM                 statistical
# A cycle/tau counts only when at least 6 of the 8 aids have a forecast.
# sd is the sample standard deviation (n-1). init_vmax is OFCL at tau 0.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
arch="$root/data/raw/archive"
mkdir -p "$arch"
out="$root/data/spread_climatology.csv"

for y in "$@"; do
  for f in $(curl -fsS "https://ftp.nhc.noaa.gov/atcf/archive/$y/" | grep -o 'aal[0-9]*\.dat\.gz' | sort -u); do
    [ -s "$arch/$f" ] || curl -fsS -o "$arch/$f" "https://ftp.nhc.noaa.gov/atcf/archive/$y/$f"
  done
done

echo "storm,cycle,tau,init_vmax,n,mean,sd,range" > "$out"
for f in "$arch"/aal*.dat.gz; do
  gzip -dc "$f"
done | awk -F', *' -f "$root/tools/spread.awk" >> "$out"

echo "wrote $out ($(($(wc -l < "$out") - 1)) rows)"
