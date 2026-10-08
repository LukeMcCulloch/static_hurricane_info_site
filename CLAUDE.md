# Working on this repo

Static site comparing physics, statistical and AI hurricane guidance for Hurricane
Isaias (AL092026), built from NOAA/NHC public ATCF data. Live:
https://lukemcculloch.github.io/static_hurricane_info_site/ . Updates follow
`tools/UPDATE.md`.

## Ground rules from the owner

- **Scope:** edit, commit and push only inside this repo. Never touch any other
  folder, and especially not the owner's personal site (`LukeMcCulloch.github.io`)
  or any copy of it.
- **Check everything before it goes public.** The owner is a scientist and this page
  is public under their name. Every number in the text must be re-derived from the
  data in this cycle. Nothing carries over unchecked. Every model description needs a
  source, or must be checked against the data itself. If a claim can't be verified,
  soften it or remove it. Say plainly in the commit message or report what changed.
- **Official sources only.** Forecasts, warnings and impacts from NWS/NHC; model data from NOAA's
  ATCF files; evacuation orders from official government emergency management (governor, county
  EMAs). No news or social media. Quote official text exactly, write "not stated" rather than
  infer, and flag errors in a source instead of silently fixing them.
- **Tone:** factual, calm, no hype, uncertainty stated. Spend more words on what went
  right than on what went wrong. Not a forecast; always point to NHC for decisions.
- **Always `git pull --rebase` first.** Another machine may also edit this repo.
- **Notify the owner** only when a decision is needed, or when the forecast changes
  materially for Mobile Bay / Fairhope, AL, where the owner's parents live (track,
  timing, intensity, or which side of the storm the area falls on).

## Lessons already learned (don't repeat these)

- **Dates in awk:** use `mktime(spec, 1)` (UTC). Without the UTC flag, local time
  shifted every verification time by 6 h and inflated errors.
- **Model IDs:** `CEM2`/`CEMI`/`CEMN` = Canadian *ensemble mean*. `CMC`/`CMC2`/`CMCI` =
  the deterministic Canadian global model. `AEMN`/`AEMI` = GEFS mean. `AP01-30` +
  `AC00` = GEFS members. `GDMN` = Google DeepMind raw, `GDMI`/`GDM2` interpolated.
  Trailing `I` = 6-h-old run adjusted to current position and intensity, `2` = 12-h-old.
- **OFCL vs OFCI:** OFCL is the current official forecast. OFCI (on the Tropical
  Tidbits plot) is the previous advisory, interpolated. They can differ a lot.
- **Interpolation artifacts:** when a raw run misses the observed intensity at the
  start, the interpolated aid shifts. Check the raw run (`GDMN`, `HFSA`, `HFSB`)
  before claiming one model class is "more" or "less" aggressive.
- **ECMWF** is not in NOAA's public a-deck. Don't describe it from data.
- **Statistical and ML aids** (SHIP, DSHP, LGEM, NNIC) carry borrowed tracks. Don't
  score their track error.
- **Multi-panel charts:** create all panels before drawing (see `panels()` in
  `assets/app.js`). Otherwise wide screens render them tiny.
- **Verified sources** are listed on `methods.html`. Grid spacings verified: HAFS
  inner nest ~2 km, GFS ~13 km, ECMWF ~9 km, UKMET ~10 km. GEFS and CMC spacings are
  unverified, so don't quote them.
