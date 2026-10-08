# Updating the site for a new NHC cycle

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
   "What has already verified" (re-run the homogeneous table and the 48 h track check
   against the newest best-track point), "Where they split" (+24/+36/+48 h values),
   the DeepMind raw-vs-interpolated paragraph, tracks, "Is this disagreement unusual?"
   (percentiles), ensemble paragraph, figure captions. Valid times move with the cycle.
   If the story changed, rewrite the section. Keep the tone: factual, no hype,
   uncertainty stated.
7. **Check it:** serve locally, load at desktop and phone widths, confirm no console
   errors and that each chart draws.
8. **Commit and push:** `Update to <new cycle> cycle`.
9. **After landfall / dissipation:** fill "Scored after landfall" with errors against
   the best track, freeze the final version, and stop the update loop.
