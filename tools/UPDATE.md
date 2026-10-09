# Updating the site for a new NHC cycle

0. **Sync first:** `git pull --rebase`. Another machine may have pushed an update.

Run from the repo root in Git Bash. NHC model cycles are 00/06/12/18Z; the official
forecast (OFCL) for a cycle appears in the a-deck about 3 h later with the advisory.

1. **Is there a new cycle?**
   `curl -fsS https://ftp.nhc.noaa.gov/atcf/aid_public/aal092026.dat.gz | gzip -dc | awk -F', *' '$5=="OFCL"{print $3}' | sort -u | tail -1`
   If it equals `cycle` in `data/current.js`, stop. If the storm has no new OFCL
   for 12 h (dissipated or post-tropical), go to step 9.
2. **Wait for the early aids.** The new cycle should have OFCL, HCCA, IVCN, HFAI,
   HFBI, CTCI, AVNI, SHIP, DSHP, LGEM, GDMI. If several are missing, check again later.
3. **Snapshot the live version:** `tools/snapshot.sh <old cycle>`, then add it to the
   "Earlier versions" list at the bottom of `index.html` (newest first).
4. **Rebuild data:**
   - `tools/build_data.sh al092026 ISAIAS <new>`
   - `prev` = the most recent cycle that has both `GDMN` and `AP01` (usually new − 6 h);
     `tools/build_data.sh al092026 ISAIAS <prev>`
   - `tools/summarize.sh al092026 <new>`
   - `awk -F', *' -v bfile=data/raw/bal092026.dat -f tools/early_verify.awk data/raw/aal092026.dat > data/early_verify.csv`
5. **Point the page at it:** update `data/current.js` and the two `data/al092026_*.js`
   script tags in `index.html`. Remove data files no longer referenced by the live page
   (snapshots keep their own copies).
6. **Re-derive every number in the text** of `index.html` from the new data. Nothing
   carries over unchecked. Includes: hero stamp, readout fallbacks, "The guidance",
   "What has already verified" (regenerate the table rows with `tools/verify_table.sh data/early_verify.csv`
   and paste them in place of the old rows; update the pair count and best-track time in the note;
   re-run the 48 h track check
   against the newest best-track point), "Where they split" (+24/+36/+48 h values),
   the DeepMind raw-vs-interpolated paragraph, tracks, "Is this disagreement unusual?"
   (percentiles), ensemble paragraph, figure captions. Valid times move with the cycle.
   If the story changed, rewrite the section. Keep the tone: factual, no hype,
   uncertainty stated.
7. **Check it:** serve locally (`tools/serve.ps1`), load at desktop and phone widths, confirm no console
   errors and that each chart draws.
8. **Commit and push:** `Update to <new cycle> cycle`.
9. **After landfall / dissipation:** fill "Scored after landfall" with errors against
   the best track, freeze the final version, and stop the update loop.

## Latest NWS page (`latest.html`), every run

Separate from the analysis above, and NWS-only: no model data, no derived numbers.

1. `powershell -ExecutionPolicy Bypass -File tools/build_latest.ps1 -Root <repo path>`. It fetches the
   current NHC and NWS Mobile products, rebuilds `latest.html`, saves the raw text to `data/raw/nws/`,
   and prints `CHANGED <field>` lines against `data/latest_state.json`.
2. If the only change in `latest.html` is the "Page built" stamp, discard it (`git checkout latest.html`).
3. Otherwise check the page against the raw products line by line (numbers, times, areas), check it
   at phone and desktop widths, then commit `Update latest NWS page (<products>)` and push.
4. A `CHANGED` line for the Fairhope zone (wind, surge, rain, tornado), Mobile Bay surge, the Mobile
   wind probabilities, the Fairhope alerts or the NHC track is the input for deciding whether the
   Mobile Bay / Fairhope forecast changed materially.

## Evacuation page (`evacuations.html`), every run

Official government sources only: the Governor of Alabama, and the Baldwin, Mobile (AL), Escambia, Santa
Rosa and Okaloosa (FL) county emergency management pages listed in `data/evacuations.json`. No news or
social media.

1. Re-read every source in `data/evacuations.json` (they are JavaScript-heavy; use a browser, not curl).
   For each order record who, where, effective time and who issued it exactly as the source states it.
   Write "Not stated" rather than inferring. Keep quotes short and exact; the signed proclamation can be
   quoted in full. Flag errors or conflicts in a source as notes instead of fixing them.
2. Update `read` to the time you finished reading, then run
   `powershell -ExecutionPolicy Bypass -File tools/build_evac.ps1 -Root <repo path>`. It also adds any
   evacuation or civil-emergency alerts the NWS relays for those counties, and NWS Mobile's evacuation text.
3. If nothing changed but the time stamps, discard. Otherwise check the page against the sources, check it
   at phone width, commit `Update evacuation notices (<what changed>)` and push.
4. A new, expanded or lifted order for Baldwin or Mobile County, especially one covering Fairhope or Mobile
   Bay shore residents, is a material change: notify the owner.
