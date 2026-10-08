# Input: concatenated a-deck rows (comma-separated). Output: CSV rows
# storm,cycle,tau,init_vmax,n,mean,sd,range for the fixed aid set.
# Used by spread_climatology.sh and, for a single cycle, by the site build.
BEGIN {
  split("HFAI HFBI HWFI HMNI CTCI AVNI DSHP LGEM", a, " ")
  for (i in a) aid[a[i]] = 1
  want[24] = want[48] = want[72] = 1
}
{
  storm = $1 $2 substr($3, 1, 4); cyc = $3; tech = $5; tau = $6 + 0; v = $9 + 0
  if (substr(cyc, 9, 2) !~ /^(00|06|12|18)$/) next
  if (tech == "OFCL" && tau == 0 && v > 0) init[storm, cyc] = v
  if (!(tech in aid) || !(tau in want) || v <= 0) next
  k = storm SUBSEP cyc SUBSEP tau
  if ((k, tech) in seen) next
  seen[k, tech] = 1
  n[k]++; s[k] += v; ss[k] += v * v
  if (!(k in lo) || v < lo[k]) lo[k] = v
  if (!(k in hi) || v > hi[k]) hi[k] = v
}
END {
  for (k in n) {
    if (n[k] < 6) continue
    split(k, p, SUBSEP)
    m = s[k] / n[k]
    var = (ss[k] - n[k] * m * m) / (n[k] - 1); if (var < 0) var = 0
    iv = ((p[1], p[2]) in init) ? init[p[1], p[2]] : ""
    printf "%s,%s,%d,%s,%d,%.1f,%.2f,%d\n", p[1], p[2], p[3], iv, n[k], m, sqrt(var), hi[k] - lo[k]
  }
}
