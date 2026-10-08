/* Charts for the Isaias model page. Data: window.ATCF[cycle] (NHC a-deck, via tools/build_data.sh)
   and window.CLIM (2023-2025 climatology, via tools/summarize.sh). Requires d3 v7. */
(function () {
  "use strict";
  if (!window.d3 || !window.ATCF || !window.CLIM) return;

  const CYC = "2026100812", PREV = "2026100806";
  const A = ATCF[CYC], P = ATCF[PREV], CL = CLIM;

  const FAMS = [
    { id: "official", label: "NHC official" },
    { id: "consensus", label: "Consensus" },
    { id: "regional", label: "Regional physics" },
    { id: "global", label: "Global physics" },
    { id: "stat", label: "Statistical" },
    { id: "ai", label: "AI / machine learning" },
    { id: "base", label: "No-skill baseline" },
  ];
  const MODELS = {
    OFCL: ["official", "NHC official forecast"],
    HCCA: ["consensus", "HFIP Corrected Consensus"],
    IVCN: ["consensus", "Intensity consensus (average)"],
    HFAI: ["regional", "HAFS-A, NOAA"],
    HFBI: ["regional", "HAFS-B, NOAA"],
    HWFI: ["regional", "HWRF, NOAA (previous generation)"],
    HMNI: ["regional", "HMON, NOAA (previous generation)"],
    CTCI: ["regional", "COAMPS-TC, U.S. Navy"],
    AVNI: ["global", "GFS, NOAA"],
    AEMI: ["global", "GEFS ensemble mean, NOAA"],
    UKX2: ["global", "UK Met Office global (12 h old)"],
    CEM2: ["global", "Canadian global, CMC (12 h old)"],
    SHIP: ["stat", "SHIPS (no land effect)"],
    DSHP: ["stat", "Decay-SHIPS (with land)"],
    LGEM: ["stat", "Logistic Growth Equation Model"],
    GDMI: ["ai", "Google DeepMind, interpolated"],
    NNIC: ["ai", "Neural-net intensity consensus (ML)"],
    OCD5: ["base", "Climatology & persistence"],
  };
  const DASH = { NNIC: "5 3", OCD5: "2 3", IVCN: "6 3", GDMN: "6 3" };
  const SS = [[34, 64, "TS"], [64, 83, "Cat 1"], [83, 96, "Cat 2"], [96, 113, "Cat 3"], [113, 137, "Cat 4"]];

  const visible = new Set(FAMS.map(f => f.id));
  const css = n => getComputedStyle(document.documentElement).getPropertyValue(n).trim();
  const famColor = f => css("--f-" + f);
  const fmt = d3.format(".1f");

  // ---- time helpers --------------------------------------------------------
  const t0 = Date.UTC(+CYC.slice(0, 4), +CYC.slice(4, 6) - 1, +CYC.slice(6, 8), +CYC.slice(8, 10));
  const hoursFrom = s => (Date.UTC(+s.slice(0, 4), +s.slice(4, 6) - 1, +s.slice(6, 8), +s.slice(8, 10)) - t0) / 36e5;
  const DOW = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  function zLabel(h) { const d = new Date(t0 + h * 36e5); return DOW[d.getUTCDay()] + " " + String(d.getUTCHours()).padStart(2, "0") + "Z"; }
  function cdt(h) {
    const d = new Date(t0 + (h - 5) * 36e5), H = d.getUTCHours();
    return DOW[d.getUTCDay()] + " " + ((H + 11) % 12 + 1) + (H < 12 ? " AM" : " PM") + " CDT";
  }
  const cat = v => v >= 137 ? "Cat 5" : v >= 113 ? "Cat 4" : v >= 96 ? "Cat 3" : v >= 83 ? "Cat 2" : v >= 64 ? "Cat 1" : v >= 34 ? "TS" : "TD";

  // ---- data helpers --------------------------------------------------------
  function series(d, id, shift = 0) {
    const m = d.models[id];
    return m ? m.map(p => ({ h: p[0] + shift, v: p[1], lat: p[2], lon: p[3] })) : null;
  }
  const at = (s, h) => { const p = s && s.find(q => q.h === h); return p ? p.v : null; };
  const best = A.best.map(b => ({ h: hoursFrom(b[0]), v: b[3], lat: b[1], lon: b[2], ty: b[5] }));
  const shown = Object.keys(MODELS).filter(id => A.models[id]);
  function sd(a) { const m = d3.mean(a); return Math.sqrt(d3.sum(a, x => (x - m) ** 2) / (a.length - 1)); }
  function pct(arr, x) { let lo = 0, eq = 0; for (const v of arr) { if (v < x) lo++; else if (v === x) eq++; } return 100 * (lo + eq / 2) / arr.length; }
  const ord = n => { const r = Math.round(n), s = ["th", "st", "nd", "rd"], v = r % 100; return r + (s[(v - 20) % 10] || s[v] || s[0]); };

  // ---- shared drawing ------------------------------------------------------
  function frame(el, hRatio, minH, maxH, m) {
    const w = Math.max(300, el.clientWidth), h = Math.round(Math.max(minH, Math.min(maxH, w * hRatio)));
    d3.select(el).selectAll("svg,.tip").remove();
    const svg = d3.select(el).append("svg").attr("viewBox", `0 0 ${w} ${h}`).attr("role", "img");
    const tip = d3.select(el).append("div").attr("class", "tip").attr("hidden", true);
    return { svg, tip, w, h, iw: w - m.l - m.r, ih: h - m.t - m.b, g: svg.append("g").attr("transform", `translate(${m.l},${m.t})`) };
  }
  function saffir(g, y, iw, labels = true) {
    SS.forEach(([lo, hi, name], i) => {
      const [a, b] = y.domain(); if (lo >= b) return;
      g.append("rect").attr("x", 0).attr("width", iw).attr("y", y(Math.min(hi, b))).attr("height", y(lo) - y(Math.min(hi, b)))
        .attr("fill", i % 2 ? "var(--band-strong)" : "var(--band)");
      if (labels) g.append("text").attr("class", "band-lbl").attr("x", iw + 6).attr("y", (y(lo) + y(Math.min(hi, b))) / 2).attr("dy", "0.35em").text(name);
    });
  }
  function hAxis(g, x, ih, iw, step) {
    const ticks = d3.range(Math.ceil(x.domain()[0] / step) * step, x.domain()[1] + 1, step);
    const ax = g.append("g").attr("class", "axis").attr("transform", `translate(0,${ih})`)
      .call(d3.axisBottom(x).tickValues(ticks).tickSize(4).tickFormat(h => (h > 0 ? "+" : "") + h + "h"));
    ax.selectAll(".tick").append("text").attr("y", 28).attr("fill", "currentColor").text(h => zLabel(h));
    g.append("g").attr("class", "grid").selectAll("line").data(ticks).join("line")
      .attr("x1", x).attr("x2", x).attr("y1", 0).attr("y2", ih).attr("stroke-opacity", .6);
  }
  function kAxis(g, y, label) {
    g.append("g").attr("class", "axis").call(d3.axisLeft(y).ticks(6).tickSize(4));
    g.append("text").attr("class", "lbl").attr("x", 0).attr("y", -6).text(label || "kt");
  }
  function nowLine(g, x, ih) {
    g.append("line").attr("x1", x(0)).attr("x2", x(0)).attr("y1", 0).attr("y2", ih).attr("stroke", "var(--ink)").attr("stroke-dasharray", "2 3");
    g.append("text").attr("class", "lbl").attr("x", x(0) - 6).attr("y", 12).attr("text-anchor", "end").text("observed");
    g.append("text").attr("class", "lbl").attr("x", x(0) + 6).attr("y", 12).text("forecast");
  }
  function placeTip(tip, el, px, py, html) {
    tip.attr("hidden", null).html(html);
    const tw = tip.node().offsetWidth, W = el.clientWidth;
    tip.style("left", Math.min(W - tw - 6, Math.max(6, px + 14)) + "px").style("top", Math.max(6, py - 10) + "px");
  }

  // ---- readout -------------------------------------------------------------
  function readout() {
    const ofcl = series(A, "OFCL"), pk = ofcl.reduce((a, b) => (b.v > a.v ? b : a));
    const set = (k, v, n) => { const e = document.querySelector(`[data-ro="${k}"]`); if (e) { e.querySelector(".v").textContent = v; e.querySelector(".n").textContent = n; } };
    set("peak", pk.v + " kt", `${cat(pk.v)} · +${pk.h} h (${cdt(pk.h)})`);
    const at24 = shown.filter(id => !["official", "consensus", "base"].includes(MODELS[id][0])).map(id => at(series(A, id), 24)).filter(v => v != null);
    set("range", d3.min(at24) + "–" + d3.max(at24) + " kt", `${at24.length} model aids at +24 h`);
    const p = [24, 48, 72].map(t => ord(pct(CL.spread[t], CL.storm[t].sd)));
    set("spread", "Typical", `${p.join(" / ")} percentile at +24/48/72 h vs. 2023–25 hurricanes`);
    const e = CL.ofcl["24"];
    set("err", "±" + e.p67 + " kt", `2 of 3 NHC forecasts at +24 h were this close (2023–25); 9 of 10 within ±${e.p90}`);
  }

  // ---- Fig 1: intensity guidance ------------------------------------------
  function figIntensity() {
    const el = document.getElementById("fig-intensity"); if (!el) return;
    const m = { t: 22, r: 48, b: 46, l: 38 };
    const F = frame(el, .56, 330, 500, m);
    const x = d3.scaleLinear([-48, 120], [0, F.iw]), y = d3.scaleLinear([0, 115], [F.ih, 0]);
    saffir(F.g, y, F.iw); hAxis(F.g, x, F.ih, F.iw, F.w < 640 ? 48 : 24); kAxis(F.g, y); nowLine(F.g, x, F.ih);
    F.svg.attr("aria-label", "Intensity forecasts for Hurricane Isaias from each model aid, by forecast hour.");

    // Historical NHC error envelope around the official forecast.
    const ofcl = series(A, "OFCL").filter(p => p.h % 12 === 0 && p.h <= 72);
    const env = q => ofcl.map(p => ({ h: p.h, lo: Math.max(0, p.v - (p.h ? CL.ofcl[p.h][q] : 0)), hi: p.v + (p.h ? CL.ofcl[p.h][q] : 0) }));
    if (visible.has("official")) ["p90", "p67"].forEach((q, i) => {
      F.g.append("path").datum(env(q)).attr("fill", "var(--f-official)").attr("fill-opacity", i ? .14 : .07)
        .attr("d", d3.area().x(d => x(d.h)).y0(d => y(d.lo)).y1(d => y(d.hi)).curve(d3.curveMonotoneX));
    });

    const line = d3.line().x(d => x(d.h)).y(d => y(d.v)).curve(d3.curveMonotoneX);
    const bt = best.filter(b => b.h >= -48 && b.h <= 0);
    F.g.append("path").datum(bt).attr("fill", "none").attr("stroke", "var(--ink)").attr("stroke-width", 2.5).attr("d", line);
    F.g.selectAll(".bt").data(bt).join("circle").attr("cx", d => x(d.h)).attr("cy", d => y(d.v)).attr("r", 2.6).attr("fill", "var(--ink)");

    const ser = shown.filter(id => visible.has(MODELS[id][0])).map(id => ({ id, fam: MODELS[id][0], pts: series(A, id).filter(p => p.h <= 120) }));
    ser.sort((a, b) => (a.id === "OFCL") - (b.id === "OFCL"));
    const paths = F.g.selectAll(".series").data(ser).join("path").attr("class", "series").attr("fill", "none")
      .attr("stroke", d => famColor(d.fam)).attr("stroke-width", d => d.id === "OFCL" ? 3.2 : 1.6)
      .attr("stroke-dasharray", d => DASH[d.id] || null).attr("stroke-linejoin", "round").attr("d", d => line(d.pts));
    const ofs = ser.find(s => s.id === "OFCL");
    if (ofs) {
      const pk = ofs.pts.reduce((a, b) => (b.v > a.v ? b : a));
      F.g.append("text").attr("class", "ann").attr("x", x(pk.h) + 6).attr("y", y(pk.v) - 8).attr("font-weight", 700).text("NHC official");
    }

    hover(el, F, x, y, ser, paths, (s, h, v) =>
      `<b>${s.id}</b> · ${MODELS[s.id][1]}<br>+${h} h (${zLabel(h)}): <b>${Math.round(v)} kt</b> ${cat(v)}`);
  }

  function hover(el, F, x, y, ser, paths, html) {
    const ov = F.g.append("rect").attr("width", F.iw).attr("height", F.ih).attr("fill", "transparent").style("cursor", "crosshair");
    const dot = F.g.append("circle").attr("r", 4.5).attr("fill", "var(--panel)").attr("stroke-width", 2).attr("visibility", "hidden");
    function valueAt(pts, h) {
      for (let i = 1; i < pts.length; i++) {
        const a = pts[i - 1], b = pts[i];
        if (h >= a.h && h <= b.h) return a.v + (b.v - a.v) * (h - a.h) / (b.h - a.h || 1);
      }
      return null;
    }
    function move(ev) {
      const [px, py] = d3.pointer(ev, F.g.node()), h = x.invert(px), v0 = y.invert(py);
      let bestS = null, bestD = Infinity, bestV = null;
      for (const s of ser) { const v = valueAt(s.pts, h); if (v != null && Math.abs(v - v0) < bestD) { bestD = Math.abs(v - v0); bestS = s; bestV = v; } }
      if (!bestS || bestD > 12) return leave();
      const hr = Math.round(h / 3) * 3, vv = valueAt(bestS.pts, hr) ?? bestV;
      paths.attr("opacity", d => d === bestS ? 1 : .18).attr("stroke-width", d => d === bestS ? 3 : (d.id === "OFCL" ? 3.2 : 1.6));
      dot.attr("visibility", "visible").attr("cx", x(hr)).attr("cy", y(vv)).attr("stroke", famColor(bestS.fam));
      const [cx, cy] = d3.pointer(ev, el);
      placeTip(F.tip, el, cx, cy, html(bestS, hr, vv));
    }
    function leave() {
      paths.attr("opacity", 1).attr("stroke-width", d => d.id === "OFCL" ? 3.2 : 1.6);
      dot.attr("visibility", "hidden"); F.tip.attr("hidden", true);
    }
    ov.on("pointermove", move).on("pointerdown", move).on("pointerleave", leave);
  }

  function toggles() {
    const box = document.getElementById("toggles"); if (!box) return;
    box.innerHTML = "";
    FAMS.forEach(f => {
      const b = document.createElement("button");
      b.type = "button"; b.setAttribute("aria-pressed", visible.has(f.id));
      b.style.setProperty("--c", `var(--f-${f.id})`);
      b.innerHTML = `<span class="sw"></span>${f.label}`;
      b.addEventListener("click", () => {
        visible.has(f.id) ? visible.delete(f.id) : visible.add(f.id);
        b.setAttribute("aria-pressed", visible.has(f.id)); figIntensity();
      });
      box.appendChild(b);
    });
  }

  // ---- Fig 2: where they split ---------------------------------------------
  function figSplit() {
    const host = document.getElementById("fig-split"); if (!host) return;
    host.innerHTML = "";
    [24, 36, 48].forEach(tau => {
      const el = document.createElement("div"); el.className = "chart"; host.appendChild(el);
      const m = { t: 40, r: 14, b: 34, l: 118 };
      const rows = FAMS.filter(f => f.id !== "base");
      const F = frame(el, .9, 250, 300, m);
      const x = d3.scaleLinear([0, 110], [0, F.iw]), yb = d3.scaleBand(rows.map(r => r.id), [0, F.ih]).padding(.2);
      SS.slice(0, 4).forEach(([lo, hi], i) => F.g.append("rect").attr("x", x(lo)).attr("width", x(Math.min(hi, 110)) - x(lo)).attr("y", 0).attr("height", F.ih).attr("fill", i % 2 ? "var(--band-strong)" : "var(--band)"));
      F.g.append("g").attr("class", "axis").attr("transform", `translate(0,${F.ih})`).call(d3.axisBottom(x).tickValues([0, 34, 64, 83, 96]).tickSize(4));
      F.g.append("text").attr("class", "lbl").attr("x", F.iw).attr("y", F.ih + 30).attr("text-anchor", "end").text("kt");
      F.svg.append("text").attr("class", "ann").attr("x", 12).attr("y", 18).attr("font-weight", 700).text(`+${tau} h`);
      F.svg.append("text").attr("class", "lbl").attr("x", 12).attr("y", 32).text(`${zLabel(tau)} · ${cdt(tau)}`);
      rows.forEach(r => F.g.append("text").attr("class", "lbl").attr("x", -10).attr("y", yb(r.id) + yb.bandwidth() / 2).attr("dy", ".35em").attr("text-anchor", "end").attr("fill", famColor(r.id)).text(r.label));
      const pts = shown.map(id => ({ id, fam: MODELS[id][0], v: at(series(A, id), tau) })).filter(d => d.v != null && d.fam !== "base");
      const seen = {};
      pts.forEach(d => { const k = d.fam + Math.round(d.v / 2); d.k = seen[k] = (seen[k] || 0) + 1; });
      const dots = F.g.selectAll(".d").data(pts).join("circle").attr("r", d => d.id === "OFCL" ? 6 : 5)
        .attr("cx", d => x(d.v)).attr("cy", d => yb(d.fam) + yb.bandwidth() / 2 + (d.k - 1) * 5 * (d.k % 2 ? 1 : -1))
        .attr("fill", d => famColor(d.fam)).attr("stroke", "var(--panel)").attr("stroke-width", 1.5).style("cursor", "pointer");
      dots.on("pointerenter pointerdown", (ev, d) => { const [cx, cy] = d3.pointer(ev, el); placeTip(F.tip, el, cx, cy, `<b>${d.id}</b> · ${MODELS[d.id][1]}<br><b>${d.v} kt</b> ${cat(d.v)}`); })
        .on("pointerleave", () => F.tip.attr("hidden", true));
      F.svg.attr("aria-label", `Model intensities at +${tau} hours: ` + pts.map(d => `${d.id} ${d.v} kt`).join(", "));
    });
  }

  // ---- Fig 3: raw vs interpolated DeepMind ---------------------------------
  function figGdm() {
    const el = document.getElementById("fig-gdm"); if (!el || !P.models.GDMN) return;
    const m = { t: 22, r: 48, b: 46, l: 38 };
    const F = frame(el, .62, 300, 420, m);
    const x = d3.scaleLinear([-12, 60], [0, F.iw]), y = d3.scaleLinear([0, 115], [F.ih, 0]);
    saffir(F.g, y, F.iw); hAxis(F.g, x, F.ih, F.iw, 12); kAxis(F.g, y); nowLine(F.g, x, F.ih);
    const line = d3.line().x(d => x(d.h)).y(d => y(d.v)).curve(d3.curveMonotoneX);
    const S = [
      { id: "OFCL", pts: series(A, "OFCL"), c: "var(--f-official)", w: 2.6, lab: "NHC official (12Z)" },
      { id: "GDMN", pts: series(P, "GDMN", -6), c: "var(--f-ai)", w: 2.2, dash: "6 3", lab: "DeepMind raw (06Z run)" },
      { id: "GDMI", pts: series(A, "GDMI"), c: "var(--f-ai)", w: 2.6, lab: "DeepMind interpolated (12Z)" },
    ].map(s => ({ ...s, pts: s.pts.filter(p => p.h >= -12 && p.h <= 60) }));
    const bt = best.filter(b => b.h >= -12 && b.h <= 0);
    F.g.append("path").datum(bt).attr("fill", "none").attr("stroke", "var(--ink)").attr("stroke-width", 2.5).attr("d", line);
    S.forEach(s => F.g.append("path").datum(s.pts).attr("fill", "none").attr("stroke", s.c).attr("stroke-width", s.w).attr("stroke-dasharray", s.dash || null).attr("d", line));
    // Starting miss: raw run at 12Z vs observed.
    const g0 = S[1].pts.find(p => p.h === 0), o0 = best.find(b => b.h === 0);
    if (g0 && o0) {
      F.g.append("line").attr("x1", x(0) + 4).attr("x2", x(0) + 4).attr("y1", y(g0.v)).attr("y2", y(o0.v)).attr("stroke", "var(--f-ai)").attr("stroke-width", 1.5);
      F.g.append("text").attr("class", "ann").attr("x", x(0) + 10).attr("y", (y(g0.v) + y(o0.v)) / 2).attr("dy", ".35em")
        .text(`raw run ${g0.v - o0.v > 0 ? "+" : ""}${g0.v - o0.v} kt vs. observed at 12Z`);
    }
    const lg = F.svg.append("g").attr("transform", `translate(${m.l + 8},${m.t + F.ih - 16 - 16 * (S.length - 1)})`);
    S.forEach((s, i) => {
      lg.append("line").attr("x1", 0).attr("x2", 22).attr("y1", i * 16).attr("y2", i * 16).attr("stroke", s.c).attr("stroke-width", s.w).attr("stroke-dasharray", s.dash || null);
      lg.append("text").attr("class", "ann").attr("x", 28).attr("y", i * 16).attr("dy", ".35em").text(s.lab);
    });
    F.svg.attr("aria-label", "Google DeepMind raw forecast from the 06Z run versus the interpolated 12Z aid and the NHC official forecast.");
  }

  // ---- Fig 4: tracks ------------------------------------------------------
  let geo = null;
  async function loadGeo() {
    if (geo || !window.topojson) return geo;
    const [w, s] = await Promise.all([
      fetch("https://cdn.jsdelivr.net/npm/world-atlas@2.0.2/countries-50m.json").then(r => r.json()),
      fetch("https://cdn.jsdelivr.net/npm/us-atlas@3.0.1/states-10m.json").then(r => r.json()),
    ]);
    geo = { land: topojson.feature(w, w.objects.land), states: topojson.mesh(s, s.objects.states, (a, b) => a !== b) };
    return geo;
  }
  async function figMap() {
    const el = document.getElementById("fig-map"); if (!el) return;
    const m = { t: 0, r: 0, b: 0, l: 0 };
    const F = frame(el, .75, 320, 640, m);
    const bounds = { type: "MultiPoint", coordinates: [[-97, 21], [-81, 21], [-97, 35.5], [-81, 35.5]] };
    const proj = d3.geoMercator().fitExtent([[10, 10], [F.w - 10, F.h - 10]], bounds), path = d3.geoPath(proj);
    F.g.append("path").datum(d3.geoGraticule().step([2, 2])()).attr("d", path).attr("fill", "none").attr("stroke", "var(--rule)").attr("stroke-width", .6);
    try {
      const G = await loadGeo();
      if (G) {
        F.g.append("path").datum(G.land).attr("d", path).attr("fill", "var(--band-strong)").attr("stroke", "var(--muted)").attr("stroke-width", .7);
        F.g.append("path").datum(G.states).attr("d", path).attr("fill", "none").attr("stroke", "var(--muted)").attr("stroke-width", .4).attr("stroke-opacity", .6);
      }
    } catch (e) { F.g.append("text").attr("class", "lbl").attr("x", 14).attr("y", 20).text("Coastline data could not load."); }
    const ll = d3.line().x(d => proj([d.lon, d.lat])[0]).y(d => proj([d.lon, d.lat])[1]).curve(d3.curveCatmullRom);
    const trk = shown.filter(id => !["consensus", "base"].includes(MODELS[id][0]))
      .map(id => ({ id, fam: MODELS[id][0], pts: series(A, id).filter(p => p.lat != null && p.h <= 72) })).filter(t => t.pts.length > 1);
    trk.sort((a, b) => (a.id === "OFCL") - (b.id === "OFCL"));
    const paths = F.g.selectAll(".trk").data(trk).join("path").attr("class", "series").attr("fill", "none")
      .attr("stroke", d => famColor(d.fam)).attr("stroke-width", d => d.id === "OFCL" ? 3 : 1.5).attr("stroke-dasharray", d => DASH[d.id] || null).attr("d", d => ll(d.pts));
    paths.append("title").text(d => `${d.id} · ${MODELS[d.id][1]}`);
    const of = trk.find(t => t.id === "OFCL");
    if (of) F.g.selectAll(".tk").data(of.pts.filter(p => p.h > 0 && p.h % 12 === 0)).join("g").each(function (p) {
      const [px, py] = proj([p.lon, p.lat]), g = d3.select(this);
      g.append("circle").attr("cx", px).attr("cy", py).attr("r", 3.5).attr("fill", "var(--panel)").attr("stroke", "var(--f-official)").attr("stroke-width", 2);
      g.append("text").attr("class", "lbl").attr("x", px + 7).attr("y", py + 4).attr("fill", "var(--ink)").text(`+${p.h}h ${p.v}kt`);
    });
    const bt = best.filter(b => b.h >= -96 && b.h <= 0 && b.lat != null);
    F.g.append("path").datum(bt).attr("d", ll).attr("fill", "none").attr("stroke", "var(--ink)").attr("stroke-width", 2.4);
    F.g.selectAll(".bt").data(bt).join("circle").attr("cx", d => proj([d.lon, d.lat])[0]).attr("cy", d => proj([d.lon, d.lat])[1]).attr("r", 2.4).attr("fill", "var(--ink)");
    const b0 = bt[bt.length - 1]; if (b0) { const [px, py] = proj([b0.lon, b0.lat]); F.g.append("text").attr("class", "ann").attr("x", px - 8).attr("y", py + 16).attr("text-anchor", "end").text("12Z Thu, 70 kt"); }
    [["New Orleans", 29.95, -90.07], ["Mobile", 30.69, -88.04], ["Pensacola", 30.42, -87.22], ["Panama City", 30.16, -85.66], ["Tampa", 27.95, -82.46], ["Houston", 29.76, -95.37]].forEach(([n, la, lo]) => {
      const [px, py] = proj([lo, la]);
      F.g.append("circle").attr("cx", px).attr("cy", py).attr("r", 2).attr("fill", "var(--muted)");
      F.g.append("text").attr("class", "lbl").attr("x", px + 4).attr("y", py - 4).text(n);
    });
    F.svg.attr("aria-label", "Map of model track forecasts for Hurricane Isaias over the Gulf of Mexico toward the north-central Gulf coast.");
  }

  // ---- Fig 5: is the spread unusual? ---------------------------------------
  function figSpread() {
    const host = document.getElementById("fig-spread"); if (!host) return;
    host.innerHTML = "";
    [24, 48, 72].forEach(tau => {
      const el = document.createElement("div"); el.className = "chart"; host.appendChild(el);
      const m = { t: 44, r: 14, b: 38, l: 34 };
      const F = frame(el, .7, 210, 260, m);
      const arr = CL.spread[tau], me = CL.storm[tau].sd, cap = 25;
      const bins = d3.bin().domain([0, cap]).thresholds(d3.range(0, cap, 1))(arr.map(v => Math.min(v, cap - .001)));
      const x = d3.scaleLinear([0, cap], [0, F.iw]), y = d3.scaleLinear([0, d3.max(bins, b => b.length)], [F.ih, 0]).nice();
      F.g.selectAll("rect").data(bins).join("rect").attr("x", b => x(b.x0) + .5).attr("width", b => Math.max(0, x(b.x1) - x(b.x0) - 1))
        .attr("y", b => y(b.length)).attr("height", b => F.ih - y(b.length)).attr("fill", "var(--f-consensus)").attr("fill-opacity", .55);
      F.g.append("g").attr("class", "axis").attr("transform", `translate(0,${F.ih})`).call(d3.axisBottom(x).tickValues([0, 5, 10, 15, 20, 25]).tickFormat(v => v === 25 ? "25+" : v).tickSize(4));
      F.g.append("g").attr("class", "axis").call(d3.axisLeft(y).ticks(4).tickSize(3));
      F.g.append("text").attr("class", "lbl").attr("x", F.iw).attr("y", F.ih + 32).attr("text-anchor", "end").text("spread across 8 core aids (kt, s.d.)");
      F.g.append("line").attr("x1", x(me)).attr("x2", x(me)).attr("y1", -6).attr("y2", F.ih).attr("stroke", "var(--f-ai)").attr("stroke-width", 2.5);
      F.svg.append("text").attr("class", "ann").attr("x", 12).attr("y", 18).attr("font-weight", 700).text(`+${tau} h`);
      F.svg.append("text").attr("class", "ann").attr("x", 12).attr("y", 34).attr("fill", "var(--f-ai)")
        .text(`Isaias ${fmt(me)} kt · ${ord(pct(arr, me))} percentile`);
      F.svg.append("text").attr("class", "lbl").attr("x", F.w - 12).attr("y", 18).attr("text-anchor", "end").text(`n = ${arr.length} cycles`);
      F.svg.attr("aria-label", `Histogram of model spread at +${tau} hours for 2023 to 2025 hurricanes; Isaias is at the ${ord(pct(arr, me))} percentile.`);
    });
    // Spread when the outlying groups are added back (not comparable to the climatology; shown for scale).
    const core = ["HFAI", "HFBI", "HWFI", "HMNI", "CTCI", "AVNI", "DSHP", "LGEM"], wide = core.concat(["GDMI", "UKX2", "CEM2", "SHIP"]);
    const v = ids => ids.map(id => at(series(A, id), 48)).filter(x => x != null);
    const e = document.getElementById("wide48");
    if (e) e.textContent = `${fmt(sd(v(core)))} kt to ${fmt(sd(v(wide)))} kt`;
  }

  // ---- Fig 6: GEFS plume ---------------------------------------------------
  function figGefs() {
    const el = document.getElementById("fig-gefs"); if (!el) return;
    const ids = Object.keys(P.models).filter(k => /^A(P\d\d|C00)$/.test(k));
    const mem = ids.map(id => series(P, id, -6).filter(p => p.h <= 120));
    const m = { t: 22, r: 48, b: 46, l: 38 };
    const F = frame(el, .5, 300, 440, m);
    const x = d3.scaleLinear([-12, 120], [0, F.iw]), y = d3.scaleLinear([0, 115], [F.ih, 0]);
    saffir(F.g, y, F.iw); hAxis(F.g, x, F.ih, F.iw, F.w < 640 ? 48 : 24); kAxis(F.g, y); nowLine(F.g, x, F.ih);
    const line = d3.line().x(d => x(d.h)).y(d => y(d.v)).curve(d3.curveMonotoneX);
    const hs = d3.range(-6, 121, 6), q = hs.map(h => {
      const vals = mem.map(s => at(s, h)).filter(v => v != null).sort(d3.ascending);
      return vals.length >= 10 ? { h, lo: d3.quantile(vals, .1), md: d3.quantile(vals, .5), hi: d3.quantile(vals, .9) } : null;
    }).filter(Boolean);
    F.g.append("path").datum(q).attr("fill", "var(--f-global)").attr("fill-opacity", .16).attr("d", d3.area().x(d => x(d.h)).y0(d => y(d.lo)).y1(d => y(d.hi)).curve(d3.curveMonotoneX));
    F.g.selectAll(".mem").data(mem).join("path").attr("fill", "none").attr("stroke", "var(--f-global)").attr("stroke-opacity", .35).attr("stroke-width", .9).attr("d", line);
    F.g.append("path").datum(q.map(d => ({ h: d.h, v: d.md }))).attr("fill", "none").attr("stroke", "var(--f-global)").attr("stroke-width", 2.8).attr("d", line);
    const bt = best.filter(b => b.h >= -12 && b.h <= 0);
    F.g.append("path").datum(bt).attr("fill", "none").attr("stroke", "var(--ink)").attr("stroke-width", 2.5).attr("d", line);
    F.g.append("path").datum(series(A, "OFCL")).attr("fill", "none").attr("stroke", "var(--f-official)").attr("stroke-width", 2.4).attr("stroke-dasharray", "1 4").attr("stroke-linecap", "round").attr("d", line);
    const lg = F.svg.append("g").attr("transform", `translate(${F.w - m.r - 210},${m.t + 14})`);
    [["var(--f-global)", 2.8, null, `GEFS median, ${mem.length} members (06Z)`], ["var(--f-global)", 10, null, "10th–90th percentile"], ["var(--f-official)", 2.4, "1 4", "NHC official (12Z)"]].forEach(([c, w, d, t], i) => {
      lg.append("line").attr("x1", 0).attr("x2", 22).attr("y1", i * 16).attr("y2", i * 16).attr("stroke", c).attr("stroke-width", w).attr("stroke-opacity", w === 10 ? .2 : 1).attr("stroke-dasharray", d).attr("stroke-linecap", d ? "round" : null);
      lg.append("text").attr("class", "ann").attr("x", 28).attr("y", i * 16).attr("dy", ".35em").text(t);
    });
    F.svg.attr("aria-label", "GEFS ensemble intensity plume for Isaias from the 06Z run.");
  }

  // ---- boot ----------------------------------------------------------------
  function all() { readout(); figIntensity(); figSplit(); figGdm(); figMap(); figSpread(); figGefs(); }
  toggles(); all();
  let rt; addEventListener("resize", () => { clearTimeout(rt); rt = setTimeout(all, 150); });
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", all);
  new MutationObserver(all).observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
})();
