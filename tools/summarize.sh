#!/usr/bin/env bash
# Summarize the climatology CSVs into data/climatology.js for the site.
#   tools/summarize.sh al092026 2026100812
# Needs data/spread_climatology.csv, data/ofcl_errors.csv and data/raw/a<storm>.dat.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
storm="${1:?storm id}"; cyc="${2:?cycle}"
out="$root/data/climatology.js"

{
  printf 'window.CLIM = {\n'

  # Spread of the fixed aid set for this storm/cycle.
  printf '"storm": {'
  awk -F', *' -v c="$cyc" '$3 == c' "$root/data/raw/a$storm.dat" \
    | awk -F', *' -f "$root/tools/spread.awk" \
    | sort -t, -k3n | awk -F, '{printf "%s\"%d\":{\"n\":%d,\"mean\":%s,\"sd\":%s,\"range\":%d}", (NR>1?",":""), $3, $5, $6, $7, $8}'
  printf '},\n'

  # Past spreads: hurricanes at the initial time (OFCL tau 0 >= 64 kt).
  printf '"spread": {'
  awk -F, 'NR > 1 && $4 >= 64 { v[$3] = v[$3] (v[$3] == "" ? "" : ",") $7; n[$3]++ }
    END { split("24 48 72", t, " "); for (i = 1; i <= 3; i++) printf "%s\"%d\":[%s]", (i>1?",":""), t[i], v[t[i]] }' \
    "$root/data/spread_climatology.csv"
  printf '},\n'

  # NHC official intensity error quantiles by lead time.
  printf '"ofcl": {'
  awk -F, 'NR > 1 { t = $3; e = $6 < 0 ? -$6 : $6; n[t]++; s[t] += e; b[t] += $6; a[t, n[t]] = e }
    END {
      split("12 24 36 48 60 72 96 120", T, " ")
      for (j = 1; j <= 8; j++) {
        t = T[j]; m = n[t]; delete x
        for (i = 1; i <= m; i++) x[i] = a[t, i]
        asort(x)
        printf "%s\"%d\":{\"n\":%d,\"mae\":%.1f,\"bias\":%.1f,\"p50\":%d,\"p67\":%d,\"p90\":%d}", (j>1?",":""), t, m, s[t]/m, b[t]/m, x[int(m*.5)], x[int(m*.67)], x[int(m*.9)]
      }
    }' "$root/data/ofcl_errors.csv"
  printf '}\n};\n'
} > "$out"
echo "wrote $out"
