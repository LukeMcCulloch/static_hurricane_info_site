#!/usr/bin/env bash
# Print the "What has already verified" table rows (homogeneous sample, +12 to +48 h) from an early_verify.csv.
#   tools/verify_table.sh data/early_verify.csv [max_cycle]
# Rows are sorted by mean absolute intensity error. Track error is left out (—) for aids that borrow tracks.
set -euo pipefail
csv="${1:?early_verify.csv}"; maxv="${2:-}"
awk -F, -v maxv="$maxv" '
BEGIN { n = split("HCCA NNIC GDMI OFCL CTCI HWFI HMNI SHIP DSHP HFAI HFBI AVNI LGEM AEMI", L, " "); for (i = 1; i <= n; i++) want[L[i]] = 1
  type["HCCA"]="Consensus"; type["NNIC"]="Machine learning"; type["GDMI"]="AI (DeepMind)"; type["OFCL"]="NHC official"
  type["CTCI"]=type["HWFI"]=type["HMNI"]=type["HFAI"]=type["HFBI"]="Regional physics"; type["SHIP"]=type["LGEM"]="Statistical"
  type["AVNI"]=type["AEMI"]="Global physics"; notrack["NNIC"]=notrack["SHIP"]=notrack["DSHP"]=notrack["LGEM"]=1 }
$3 >= 12 && $3 <= 48 && ($1 in want) && (maxv == "" || $4 <= maxv) { k = $2 SUBSEP $3; e[$1, k] = $7; t[$1, k] = $8; has[k]++ }
END {
  for (k in has) if (has[k] == n) { np++; ks[np] = k }
  for (i = 1; i <= n; i++) { a = L[i]; se = sb = st = 0
    for (j = 1; j <= np; j++) { v = e[a, ks[j]]; se += (v < 0 ? -v : v); sb += v; st += t[a, ks[j]] }
    mae[a] = se / np; bias[a] = sb / np; trk[a] = st / np }
  if (sprintf("%.1f%.1f", mae["SHIP"], bias["SHIP"]) != sprintf("%.1f%.1f", mae["DSHP"], bias["DSHP"])) print "WARNING: SHIP and DSHP differ; list them separately" > "/dev/stderr"
  printf "<!-- %d pairs -->\n", np
  m = 0; for (i = 1; i <= n; i++) if (L[i] != "DSHP") { m++; o[m] = L[i] }
  for (i = 1; i <= m; i++) for (j = i + 1; j <= m; j++) if (mae[o[j]] < mae[o[i]]) { x = o[i]; o[i] = o[j]; o[j] = x }
  for (i = 1; i <= m; i++) { a = o[i]; b = sprintf("%+.1f", bias[a]); sub(/^-/, "\342\210\222", b)
    printf "          <tr><td>%s</td><td>%s</td><td>%.1f kt</td><td>%s</td><td>%s</td></tr>\n", (a == "SHIP" ? "SHIP / DSHP" : a), type[a], mae[a], b, (a in notrack ? "\342\200\224" : sprintf("%.0f nmi", trk[a])) }
}' "$csv"
