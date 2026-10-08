# Score every forecast already verifiable for the current storm: each aid's
# forecasts from earlier cycles against the operational best track so far.
#   awk -F', *' -v bfile=data/raw/bal092026.dat -f tools/early_verify.awk data/raw/aal092026.dat
# Output rows: tech,cycle,tau,valid,fc_vmax,bt_vmax,err_kt,track_err_nmi
function ep(s) { return mktime(substr(s,1,4) " " substr(s,5,2) " " substr(s,7,2) " " substr(s,9,2) " 0 0", 1) }
function deg(s,  h, v) { h = substr(s, length(s)); v = substr(s, 1, length(s) - 1) / 10; return (h == "S" || h == "W") ? -v : v }
function nmi(a1, o1, a2, o2,  r, x) {   # great-circle distance, nautical miles
  r = 3.14159265 / 180
  x = sin(a1*r)*sin(a2*r) + cos(a1*r)*cos(a2*r)*cos((o2-o1)*r); if (x > 1) x = 1
  return 3440.065 * atan2(sqrt(1 - x*x), x)
}
BEGIN {
  while ((getline line < bfile) > 0) {
    split(line, f, /, */)
    if (f[3] in bv) continue
    bv[f[3]] = f[9] + 0; blat[f[3]] = deg(f[7]); blon[f[3]] = deg(f[8])
  }
}
($9 + 0) > 0 && ($6 + 0) > 0 {
  k = $5 SUBSEP $3 SUBSEP $6; if (k in seen) next; seen[k] = 1
  valid = strftime("%Y%m%d%H", ep($3) + $6 * 3600, 1)
  if (!(valid in bv)) next
  lat = deg($7); te = (lat != 0) ? sprintf("%.0f", nmi(lat, deg($8), blat[valid], blon[valid])) : ""
  printf "%s,%s,%d,%s,%d,%d,%d,%s\n", $5, $3, $6, valid, $9, bv[valid], $9 - bv[valid], te
}
