// Araba trafiği ve sokak düzeni: şeritler, kavşak geçişleri, trafik ışıkları, yaya geçitleri,
// tabelalar ve reklam panoları. ada_export.js çağırır (kaldırımlar ve adalar hazır olduktan sonra).
//
// Sağdan trafik: her yolda iki şerit (yolun ortasından w/4 sağda); meydan göbeği tek yönlü
// (saat yönünün tersine). Kavşakta her kola ("arm": kavşaktan çıkan yön) gelen şerit, yaya
// geçidinden önceki dur çizgisinde biter; kavşak içini Bezier geçişler (sağa, düz, sola) bağlar.
// Çıkmaz uçlarda U dönüşü. Işık fazları: kollar sırayla yeşil, en sonda tüm yayalara yeşil
// (o sırada bütün arabalar kırmızıda).
//
// Koordinatlar plan düzleminde (x doğu, y kuzey, h). trafik.json Godot düzleminde (x, h, -y).

// Aynı yolun iki kolu birlikte yeşil (ana yol uzun, yan yol kısa); sola dönen karşıdan gelene yol verir
const TIMING = { greenMain: 22.0, greenSide: 12.0, yellow: 2.0, allRed: 1.0, pedWalk: 6.0, pedFlash: 3.0 };
const LIMIT = { ring: 13.9, avenue: 11.1, street: 8.3, serp: 9.7, plaza: 6.5 };
const LIMIT_ID = { port: 5.5, summit: 5.5 };
const KMH = (v) => Math.round(v * 3.6 / 10) * 10;
const DEST = [
  { key: "Meydan", roads: ["plaza"] },
  { key: "Tepe", roads: ["summit"] },
  { key: "Liman", roads: ["port"] },
];

module.exports = function buildTraffic(ctx) {
  const { M, ROADS, JUNC, nearestRoad, SW, CURB, r3, sidewalkRuns, islandAt } = ctx;
  const byId = new Map(ROADS.map((r) => [r.id, r]));

  // ---------- Yol boyunca örnekleme ----------
  const cum = new Map();
  for (const r of ROADS) {
    const c = [0];
    for (let i = 1; i < r.pts.length; i++) c.push(c[i - 1] + Math.hypot(r.pts[i].x - r.pts[i - 1].x, r.pts[i].y - r.pts[i - 1].y));
    if (r.closed) c.push(c[c.length - 1] + Math.hypot(r.pts[0].x - r.pts[r.pts.length - 1].x, r.pts[0].y - r.pts[r.pts.length - 1].y));
    cum.set(r, c);
  }
  const lenOf = (r) => cum.get(r)[cum.get(r).length - 1];
  function at(r, s) {
    const c = cum.get(r), n = r.pts.length, L = lenOf(r);
    if (r.closed) s = ((s % L) + L) % L; else s = Math.max(0, Math.min(L, s));
    let lo = 0, hi = c.length - 1;
    while (hi - lo > 1) { const m = (lo + hi) >> 1; if (c[m] <= s) lo = m; else hi = m; }
    const a = r.pts[lo % n], b = r.pts[hi % n], ha = r.prof.h[lo % n], hb = r.prof.h[hi % n];
    const t = (s - c[lo]) / ((c[hi] - c[lo]) || 1);
    const dx = b.x - a.x, dy = b.y - a.y, L2 = Math.hypot(dx, dy) || 1;
    return { x: a.x + dx * t, y: a.y + dy * t, h: ha + (hb - ha) * t, dx: dx / L2, dy: dy / L2 };
  }
  // Yolun tek yönlü dolaşım yönü (meydan göbeği saat yönünün tersine): +1 / -1, iki yönlüde 0
  const oneWay = new Map();
  for (const r of ROADS) {
    if (r.kind !== "plaza") continue;
    let A = 0;
    for (let i = 0; i < r.pts.length; i++) { const p = r.pts[i], q = r.pts[(i + 1) % r.pts.length]; A += p.x * q.y - q.x * p.y; }
    oneWay.set(r, A > 0 ? 1 : -1);
  }
  const limitOf = (r) => LIMIT_ID[r.id] || LIMIT[r.kind] || 8.3;

  // ---------- Düğümler (kavşaklar ve çıkmaz uçlar), kollar ----------
  const nodesOn = new Map(ROADS.map((r) => [r, []]));
  JUNC.forEach((j, ji) => {
    for (const m of j.members) nodesOn.get(m.r).push({ s: cum.get(m.r)[m.i], j: ji });
  });
  for (const r of ROADS) {
    const L = nodesOn.get(r);
    if (!r.closed) {
      if (!L.some((q) => q.s < 1)) L.push({ s: 0, j: -1 });
      if (!L.some((q) => q.s > lenOf(r) - 1)) L.push({ s: lenOf(r), j: -1 });
    }
    L.sort((a, b) => a.s - b.s);
  }
  // Bir düğümden dir yönünde bir sonraki düğüme uzaklık
  function nextGap(r, s, dir) {
    const L = nodesOn.get(r), T = lenOf(r);
    let best = Infinity;
    for (const q of L) {
      let d = (q.s - s) * dir;
      if (r.closed) d = ((d % T) + T) % T;
      if (d > 0.5 && d < best) best = d;
    }
    return best;
  }

  const junctions = JUNC.map((j, ji) => ({ ji, x: j.x, y: j.y, h: j.h, arms: [], roundabout: !!j.roundabout }));
  const armKey = (ji, r, dir) => `${ji}|${r.id}|${dir}`;
  const arms = new Map();
  JUNC.forEach((j, ji) => {
    for (const m of j.members) {
      const r = m.r, n = r.pts.length, s0 = cum.get(r)[m.i];
      const dirs = r.closed || (m.i > 0 && m.i < n - 1) ? [1, -1] : [m.i === 0 ? 1 : -1];
      for (const dir of dirs) {
        const gap = nextGap(r, s0, dir);
        const p = at(r, s0 + dir * Math.min(8, gap * 0.5));
        let ax = p.x - j.x, ay = p.y - j.y; const L = Math.hypot(ax, ay) || 1; ax /= L; ay /= L;
        const ow = oneWay.get(r) || 0;
        const arm = { ji, r, dir, s0, gap, ax, ay, w: r.width, idx: junctions[ji].arms.length,
          incoming: ow === 0 || ow === -dir, outgoing: ow === 0 || ow === dir };
        junctions[ji].arms.push(arm);
        arms.set(armKey(ji, r, dir), arm);
      }
    }
  });

  // Kaldırım var mı? (yaya geçidi uçları için)
  // Kaldırım orta çizgisi parçaları (uzaklık < yarım genişlik + pay ise kaldırımdadır)
  const swSegs = [];
  for (const run of sidewalkRuns) {
    for (let i = 0; i < run.pts.length - 1; i++) {
      const p = run.pts[i], q = run.pts[i + 1];
      swSegs.push([(p[0] + p[2]) / 2, (p[1] + p[3]) / 2, (q[0] + q[2]) / 2, (q[1] + q[3]) / 2,
        Math.max(Math.hypot(p[0] - p[2], p[1] - p[3]), Math.hypot(q[0] - q[2], q[1] - q[3])) / 2]);
    }
  }
  const walkable = (x, y) => {
    const is = islandAt(x, y);
    if (is && is.d === 0) return true;
    for (const [ax, ay, bx, by, hw] of swSegs) {
      if (Math.min(ax, bx) - 6 > x || Math.max(ax, bx) + 6 < x || Math.min(ay, by) - 6 > y || Math.max(ay, by) + 6 < y) continue;
      const dx = bx - ax, dy = by - ay, t = Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy || 1)));
      if (Math.hypot(ax + dx * t - x, ay + dy * t - y) < Math.min(hw, 4) + 0.5) return true;
    }
    return false;
  };

  // Kol başına yaya geçidi uzaklığı (c) ve dur çizgisi (st)
  for (const J of junctions) {
    const otherHalf = (arm) => Math.max(0, ...J.arms.filter((a) => a.r !== arm.r).map((a) => a.w / 2));
    for (const arm of J.arms) {
      // Bu kolun iki yanındaki kaldırım uçları (köşe dönüşünün bittiği yer)
      let cL = null, cR = null;
      for (const run of sidewalkRuns) {
        if (run.road !== arm.r.id) continue;
        for (const e of [run.pts[0], run.pts[run.pts.length - 1]]) {
          const mx = (e[0] + e[2]) / 2 - J.x, my = (e[1] + e[3]) / 2 - J.y;
          const along = mx * arm.ax + my * arm.ay, lat = -mx * arm.ay + my * arm.ax;
          if (along < 2 || along > 32 || Math.abs(lat) > arm.w / 2 + SW + 2) continue;
          if (lat > 0) cL = cL === null ? along : Math.min(cL, along); else cR = cR === null ? along : Math.min(cR, along);
        }
      }
      let c = cL !== null && cR !== null ? Math.max(cL, cR) + 1.6 : otherHalf(arm) + 5.6;
      c = Math.max(4.5, Math.min(c, arm.gap * 0.5 - 3));
      arm.c = c;
      arm.st = c + 2.5;
      // Yaya geçidi: iki ucu da kaldırımda (ya da adada) olmalı
      const p = at(arm.r, arm.s0 + arm.dir * c), Rx = -arm.ay, Ry = arm.ax, o = arm.w / 2 + SW * 0.5;
      const A = { x: p.x + Rx * o, y: p.y + Ry * o, h: p.h }, B = { x: p.x - Rx * o, y: p.y - Ry * o, h: p.h };
      arm.cw = arm.gap > 2 * c + 2 && walkable(A.x, A.y) && walkable(B.x, B.y) ? { p, A, B } : null;
      if (process.env.TR_DBG && !arm.cw) console.log("geçit yok", J.ji, arm.r.id, arm.dir, "gap", arm.gap.toFixed(1), "c", c.toFixed(1), "A", walkable(A.x, A.y), "B", walkable(B.x, B.y), Math.round(A.x), Math.round(A.y));
    }
  }

  // ---------- Şeritler ----------
  const lanes = [];
  function sampleLane(r, s0, s1, off) {
    // s0 -> s1 (s1 < s0 olabilir: ters yön), yol yönüne göre sağa off (ters yönde de sürüş yönünün sağı)
    const dir = s1 >= s0 ? 1 : -1, L = Math.abs(s1 - s0), n = Math.max(2, Math.ceil(L / 2) + 1), pts = [];
    for (let k = 0; k < n; k++) {
      const q = at(r, s0 + dir * L * k / (n - 1));
      const tx = q.dx * dir, ty = q.dy * dir;
      pts.push({ x: q.x + ty * off, y: q.y - tx * off, h: q.h });
    }
    return pts;
  }
  const endInfo = (r, node, dir) => node.j >= 0 ? arms.get(armKey(node.j, r, dir)) : null;
  for (const r of ROADS) {
    const L = nodesOn.get(r), T = lenOf(r), ow = oneWay.get(r) || 0;
    const pairs = [];
    for (let k = 0; k < L.length - 1; k++) pairs.push([L[k], L[k + 1], L[k + 1].s - L[k].s]);
    if (r.closed && L.length) pairs.push([L[L.length - 1], L[0], L[0].s + T - L[L.length - 1].s]);
    if (r.closed && L.length === 0) continue;
    for (const [A, B, gap] of pairs) {
      const armA = endInfo(r, A, 1), armB = endInfo(r, B, -1);
      const stA = armA ? armA.st : 3, stB = armB ? armB.st : 3;
      let sa = A.s + stA, sb = A.s + gap - stB;
      if (sb - sa < 2) { const m = A.s + gap / 2; sa = m - 1; sb = m + 1; }
      const off = ow ? 0 : r.width / 4;
      if (ow >= 0) lanes.push({ road: r, pts: sampleLane(r, sa, sb, off), from: armA, to: armB, deadStart: !armA, deadEnd: !armB });
      if (ow <= 0) lanes.push({ road: r, pts: sampleLane(r, sb, sa, off), from: armB, to: armA, deadStart: !armB, deadEnd: !armA });
    }
  }
  lanes.forEach((l, i) => { l.id = i; l.kind = "lane"; l.next = []; l.weights = []; });

  // ---------- Kavşak geçişleri ----------
  const bez = (P0, P1, P2, P3, t) => {
    const u = 1 - t;
    return { x: u * u * u * P0.x + 3 * u * u * t * P1.x + 3 * u * t * t * P2.x + t * t * t * P3.x,
             y: u * u * u * P0.y + 3 * u * u * t * P1.y + 3 * u * t * t * P2.y + t * t * t * P3.y };
  };
  const dirOf = (pts, end) => {
    const a = end ? pts[pts.length - 2] : pts[0], b = end ? pts[pts.length - 1] : pts[1];
    const L = Math.hypot(b.x - a.x, b.y - a.y) || 1;
    return { x: (b.x - a.x) / L, y: (b.y - a.y) / L };
  };
  // Aracın yan kenarları (yoldan 0,95 m) kaldırıma / adaya basıyorsa 1, basmıyorsa 0
  const curbHit = (pts, q) => {
    const a = pts[q - 1], b = pts[q + 1], p = pts[q], L = Math.hypot(b.x - a.x, b.y - a.y) || 1;
    const nx = -(b.y - a.y) / L, ny = (b.x - a.x) / L;
    return walkable(p.x + nx * 0.95, p.y + ny * 0.95) || walkable(p.x - nx * 0.95, p.y - ny * 0.95) ? 1 : 0;
  };
  function connector(inL, outL, turn, jh) {
    const P0 = inL.pts[inL.pts.length - 1], P3 = outL.pts[0];
    const d0 = dirOf(inL.pts, true), d3 = dirOf(outL.pts, false);
    const D = Math.hypot(P3.x - P0.x, P3.y - P0.y);
    const n = Math.max(4, Math.ceil(D * 1.3));
    // Kavşağın iç köşesindeki kaldırıma taşmayan en uygun kol uzunluğu (araba yarı genişliği + pay)
    const make = (k) => {
      const P1 = { x: P0.x + d0.x * k, y: P0.y + d0.y * k }, P2 = { x: P3.x - d3.x * k, y: P3.y - d3.y * k };
      const pts = [];
      let worst = -99;
      for (let q = 0; q <= n; q++) {
        const t = q / n, b = bez(P0, P1, P2, P3, t);
        let h = P0.h + (P3.h - P0.h) * t;
        const o = nearestRoad(b.x, b.y);
        if (jh !== null && o && o.e < 0.5) h = o.h;
        pts.push({ x: b.x, y: b.y, h });
      }
      for (let q = 2; q < pts.length - 2; q++) worst = Math.max(worst, curbHit(pts, q));
      return { pts, worst };
    };
    // Dönüş: düz + yay + düz (şerit çizgilerinin kesiştiği köşe etrafında, sığan en büyük yay)
    const arcTurn = () => {
      const den = d0.x * d3.y - d0.y * d3.x;
      if (Math.abs(den) < 0.2) return null;
      const t0 = ((P3.x - P0.x) * d3.y - (P3.y - P0.y) * d3.x) / den;     // X = P0 + d0 t0
      const X = { x: P0.x + d0.x * t0, y: P0.y + d0.y * t0 };
      const a3 = (X.x - P3.x) * d3.x + (X.y - P3.y) * d3.y;              // X = P3 + d3 a3 (a3 < 0: önünde)
      if (t0 <= 0.5 || a3 >= -0.5) return null;
      const theta = Math.acos(Math.max(-1, Math.min(1, d0.x * d3.x + d0.y * d3.y)));
      const tl = Math.min(t0, -a3) * 0.97, R = tl / Math.tan(theta / 2);
      const T0 = { x: X.x - d0.x * tl, y: X.y - d0.y * tl }, T3 = { x: X.x + d3.x * tl, y: X.y + d3.y * tl };
      const side = Math.sign(den);                                       // + sola
      const C = { x: T0.x - d0.y * R * side, y: T0.y + d0.x * R * side };
      const raw = [];
      const L0 = Math.hypot(T0.x - P0.x, T0.y - P0.y);
      for (let q = 0, m = Math.max(1, Math.ceil(L0)); q < m; q++) raw.push({ x: P0.x + (T0.x - P0.x) * q / m, y: P0.y + (T0.y - P0.y) * q / m });
      const a0 = Math.atan2(T0.y - C.y, T0.x - C.x), m2 = Math.max(3, Math.ceil(theta * R));
      for (let q = 0; q < m2; q++) { const a = a0 + side * theta * q / m2; raw.push({ x: C.x + Math.cos(a) * R, y: C.y + Math.sin(a) * R }); }
      const L3 = Math.hypot(P3.x - T3.x, P3.y - T3.y);
      for (let q = 0, m = Math.max(1, Math.ceil(L3)); q <= m; q++) raw.push({ x: T3.x + (P3.x - T3.x) * q / m, y: T3.y + (P3.y - T3.y) * q / m });
      let worst = -99;
      const pts = raw.map((b, q) => {
        const t = q / (raw.length - 1);
        let h = P0.h + (P3.h - P0.h) * t;
        const o = nearestRoad(b.x, b.y);
        if (jh !== null && o && o.e < 0.5) h = o.h;
        if (q > 1 && q < raw.length - 2) worst = Math.max(worst, curbHit(raw, q));
        return { x: b.x, y: b.y, h };
      });
      return { pts, worst };
    };
    let best = turn === "sag" || turn === "sol" ? arcTurn() : null;
    if (best && best.worst <= 0) best.done = true;
    const ks = best && best.done ? [] : turn === "u" ? [Math.max(inL.road.width * 0.7, 3)] : [0.42, 0.36, 0.3, 0.24, 0.18, 0.12, 0.5, 0.6].map((f) => f * D);
    for (const k of ks) {
      const c = make(k);
      if (best && best.done) break;
      if (!best || c.worst < best.worst) best = c;
      if (c.worst <= 0) { best = c; break; }
    }
    const c = { id: lanes.length, kind: "conn", road: inL.road, pts: best.pts, next: [outL.id], weights: [1], turn,
      ji: inL.to ? inL.to.ji : -1, fromArm: inL.to ? inL.to.idx : -1, clip: best.worst };
    lanes.push(c);
    return c;
  }
  const W = { duz: 3, sag: 2, sol: 1.5, u: 1 };
  const baseLanes = lanes.slice();
  for (const inL of baseLanes) {
    if (inL.deadEnd) {
      // Çıkmaz: aynı yolun karşı şeridine U dönüşü
      const back = baseLanes.find((o) => o.road === inL.road && o.deadStart && o !== inL &&
        Math.hypot(o.pts[0].x - inL.pts[inL.pts.length - 1].x, o.pts[0].y - inL.pts[inL.pts.length - 1].y) < inL.road.width);
      if (back) { const c = connector(inL, back, "u", null); inL.next.push(c.id); inL.weights.push(1); }
      continue;
    }
    const J = junctions[inL.to.ji];
    const outs = baseLanes.filter((o) => o.from && o.from.ji === J.ji && o.from !== inL.to);
    const d0 = dirOf(inL.pts, true);
    for (const o of outs) {
      const d3 = dirOf(o.pts, false);
      const ang = Math.atan2(d0.x * d3.y - d0.y * d3.x, d0.x * d3.x + d0.y * d3.y);
      if (Math.abs(ang) > M.rad(165)) continue;
      const turn = Math.abs(ang) < M.rad(35) ? "duz" : ang > 0 ? "sol" : "sag";
      const c = connector(inL, o, turn, J.h);
      inL.next.push(c.id); inL.weights.push(W[turn]);
    }
    if (!inL.next.length) {
      // Tek çıkış kendi kolu: U dönüşü
      const back = baseLanes.find((o) => o.from === inL.to);
      if (back) { const c = connector(inL, back, "u", J.h); inL.next.push(c.id); inL.weights.push(1); }
    }
  }

  // Kavşak geçişi kaldırıma taşıyor mu? (araba yarı genişliği 0,9 m)
  if (process.env.TR_DBG) {
    const bad = {};
    for (const l of lanes) {
      if (l.kind !== "conn") continue;
      let worst = -99;
      for (let i = 2; i < l.pts.length - 2; i++) worst = Math.max(worst, curbHit(l.pts, i));
      if (worst > 0) { bad[l.turn] = (bad[l.turn] || 0) + 1; bad["j" + l.ji + (junctions[l.ji] && junctions[l.ji].roundabout ? "G" : "")] = (bad["j" + l.ji + (junctions[l.ji] && junctions[l.ji].roundabout ? "G" : "")] || 0) + 1; }
    }
    console.log("kaldırıma taşan geçiş:", JSON.stringify(bad), "/", lanes.filter((l) => l.kind === "conn").length);
  }

  // ---------- Hız: yol sınırı ve viraj (yanal ivme 2,8 m/sn²) ----------
  for (const l of lanes) {
    const lim = l.kind === "conn" ? (l.turn === "duz" ? limitOf(l.road) : l.turn === "u" ? 3 : 7) : limitOf(l.road);
    l.v = l.pts.map((p, i) => {
      const a = l.pts[Math.max(0, i - 2)], b = l.pts[Math.min(l.pts.length - 1, i + 2)];
      if (a === p || b === p) return lim;
      const A = Math.hypot(b.x - a.x, b.y - a.y), B = Math.hypot(p.x - a.x, p.y - a.y), C = Math.hypot(b.x - p.x, b.y - p.y);
      const area2 = Math.abs((p.x - a.x) * (b.y - a.y) - (p.y - a.y) * (b.x - a.x));
      const R = area2 > 1e-6 ? A * B * C / (2 * area2) : 1e9;
      return Math.min(lim, Math.max(2.5, Math.sqrt(2.8 * R)));
    });
    l.len = l.pts.reduce((u, q, i) => i ? u + Math.hypot(q.x - l.pts[i - 1].x, q.y - l.pts[i - 1].y) : 0, 0);
  }

  // ---------- Işık fazları ----------
  const hash = (k) => { let h = 2166136261; for (const ch of String(k)) { h ^= ch.charCodeAt(0); h = Math.imul(h, 16777619); } return (h >>> 0) / 4294967296; };
  for (const J of junctions) {
    const inArms = J.arms.filter((a) => a.incoming && lanes.some((l) => l.kind === "lane" && l.to === a));
    J.phases = inArms.map((a) => a.idx);
    // Faz grupları: aynı yolun kolları birlikte
    const byRoad = new Map();
    for (const a of inArms) { if (!byRoad.has(a.r)) byRoad.set(a.r, []); byRoad.get(a.r).push(a.idx); }
    // Ana yol: iki kolu olan ya da göbeğin dolaşım yolu
    const isMain = (arms) => arms.length > 1 || J.arms[arms[0]].r.kind === "plaza";
    J.groups = [...byRoad.values()].map((arms) => ({ arms, g: isMain(arms) ? TIMING.greenMain : TIMING.greenSide }));
    J.groups.sort((a, b) => (isMain(b.arms) ? 1 : 0) - (isMain(a.arms) ? 1 : 0));
    const cyc = J.groups.reduce((u, g) => u + g.g + TIMING.yellow + TIMING.allRed, 0) + TIMING.pedWalk + TIMING.pedFlash + TIMING.allRed;
    J.cycle = cyc;
    J.offset = hash(J.ji * 7.13) * cyc;
    // Göbek: yeşil dalga. Dolaşan araba her girişe yeşilin başında varsın (aynı döngü süresi)
    const pa = J.roundabout && J.arms.find((a) => a.r.kind === "plaza" && a.incoming);
    if (pa) {
      const ow = oneWay.get(pa.r) || 1, vp = 5.5;
      J.offset = ((-(pa.s0 * ow) / vp) % cyc + cyc) % cyc;
    }
  }

  // ---------- Yaya geçitleri, dur çizgileri, ışık direkleri ----------
  const crosswalks = [], stopLines = [], lights = [];
  for (const J of junctions) {
    for (const arm of J.arms) {
      const Rx = -arm.ay, Ry = arm.ax;          // kolun soluna (kavşaktan dışa bakınca)
      if (arm.cw) {
        crosswalks.push({ ji: J.ji, arm: arm.idx, c: arm.cw.p, A: arm.cw.A, B: arm.cw.B, ax: arm.ax, ay: arm.ay, w: arm.w });
        arm.cwId = crosswalks.length - 1;
        // Yaya ışıkları iki uçta, karşıya bakar (geçidin kavşak tarafının biraz dışında)
        for (const [P, Q] of [[arm.cw.A, arm.cw.B], [arm.cw.B, arm.cw.A]]) {
          lights.push({ kind: "yaya", ji: J.ji, arm: arm.idx, x: P.x + arm.ax * 1.9, y: P.y + arm.ay * 1.9, h: P.h + CURB, fx: Q.x - P.x, fy: Q.y - P.y });
        }
      }
      if (!arm.incoming || !J.phases.includes(arm.idx)) continue;
      // Gelen araç kavşağa doğru (-a) gider; sürüş yönünün sağı (-ay, ax) = R: gelen şerit R yanında
      const inSide = 1;
      const p = at(arm.r, arm.s0 + arm.dir * (arm.st - 0.4));
      const ow = oneWay.get(arm.r) || 0;
      const half = arm.w / 2;
      const from = ow ? -half : 0, to = half;
      stopLines.push({ a: { x: p.x + Rx * inSide * from, y: p.y + Ry * inSide * from, h: p.h }, b: { x: p.x + Rx * inSide * to, y: p.y + Ry * inSide * to, h: p.h } });
      // Araç ışığı: dur çizgisinde, gelen şeridin sağ kaldırımında, gelen trafiğe bakar
      const q = at(arm.r, arm.s0 + arm.dir * arm.st);
      const o = half + 0.55;
      lights.push({ kind: "arac", ji: J.ji, arm: arm.idx, x: q.x + Rx * inSide * o, y: q.y + Ry * inSide * o, h: q.h + CURB, fx: arm.ax, fy: arm.ay });
    }
  }

  // ---------- Yön (hedeflere en kısa yol) ----------
  const distTo = DEST.map((d) => {
    const dist = new Array(lanes.length).fill(Infinity), prev = lanes.map(() => []);
    lanes.forEach((l) => l.next.forEach((n) => prev[n].push(l.id)));
    const q = [];
    lanes.forEach((l) => { if (d.roads.includes(l.road.id) && l.kind === "lane") { dist[l.id] = 0; q.push(l.id); } });
    while (q.length) {
      q.sort((a, b) => dist[b] - dist[a]);
      const u = q.pop();
      for (const p of prev[u]) { const nd = dist[u] + lanes[p].len; if (nd < dist[p]) { dist[p] = nd; q.push(p); } }
    }
    return dist;
  });

  // ---------- Tabelalar ----------
  const signs = [];
  const placeRight = (l, s, extra = 0) => {
    // Şeridin s metresindeki noktanın sağ kaldırımı (sürüş yönüne göre)
    let acc = 0;
    for (let i = 1; i < l.pts.length; i++) {
      const a = l.pts[i - 1], b = l.pts[i], d = Math.hypot(b.x - a.x, b.y - a.y);
      if (acc + d >= s) {
        const t = (s - acc) / (d || 1), tx = (b.x - a.x) / (d || 1), ty = (b.y - a.y) / (d || 1);
        const off = (oneWay.get(l.road) ? 0 : 0) + l.road.width / 4 + SW * 0.72 + extra;
        const x = a.x + (b.x - a.x) * t + ty * off, y = a.y + (b.y - a.y) * t - tx * off;
        return { x, y, h: a.h + (b.h - a.h) * t + CURB, fx: -tx, fy: -ty };
      }
      acc += d;
    }
    return null;
  };
  const near = (x, y, key, R) => signs.some((s) => (!key || s.key === key) && Math.hypot(s.x - x, s.y - y) < R);
  const inShop = ctx.inShop || (() => false);
  const okSpot = (P) => P && walkable(P.x, P.y) && !inShop(P.x, P.y, 3) && !lights.some((L) => Math.hypot(L.x - P.x, L.y - P.y) < 2.5);
  for (const l of lanes) {
    if (l.kind !== "lane" || l.len < 45) continue;
    // Hız sınırı: şeridin başında (kavşaktan çıkınca)
    const kmh = KMH(limitOf(l.road));
    const P = placeRight(l, Math.min(18, l.len * 0.3));
    if (okSpot(P) && !near(P.x, P.y, `hiz_${kmh}`, 60)) signs.push({ key: `hiz_${kmh}`, ...P, kind: "levha" });
    // Dönel kavşak: meydana giden caddelerde
    if (l.to && junctions[l.to.ji].roundabout && l.road.kind !== "plaza") {
      const Q = placeRight(l, l.len - 30);
      if (okSpot(Q)) signs.push({ key: "donel_kavsak", ...Q, kind: "levha" });
    }
    // Yön tabelası: kavşaktan önce, hedeflere hangi yoldan gidilir
    if (l.to && l.next.length >= 2 && l.len > 70) {
      const lines = [];
      for (let di = 0; di < DEST.length; di++) {
        if (distTo[di][l.id] < 90 || !isFinite(distTo[di][l.id])) continue;
        let best = null;
        for (const cid of l.next) {
          const c = lanes[cid], tot = c.len + distTo[di][c.next[0]];
          if (!best || tot < best.tot) best = { tot, turn: c.turn };
        }
        if (best && isFinite(best.tot)) lines.push(`${DEST[di].key}:${best.turn}`);
      }
      const Q = placeRight(l, l.len - 34, 0.2);
      if (lines.length && okSpot(Q)) signs.push({ key: `yon|${lines.join("|")}`, ...Q, kind: "yon" });
    }
    // Viraj uyarısı: sıkı virajdan 40 m önce
    for (let i = 0; i < l.pts.length; i++) {
      if (l.v[i] > 6.2) continue;
      let s = 0;
      for (let k = 1; k <= i; k++) s += Math.hypot(l.pts[k].x - l.pts[k - 1].x, l.pts[k].y - l.pts[k - 1].y);
      if (s < 45) continue;
      // Virajın yönü
      const a = l.pts[Math.max(0, i - 3)], b = l.pts[i], c = l.pts[Math.min(l.pts.length - 1, i + 3)];
      const cr = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      const key = cr > 0 ? "viraj_sol" : "viraj_sag";
      const Q = placeRight(l, s - 40);
      if (okSpot(Q) && !near(Q.x, Q.y, null, 50)) signs.push({ key, ...Q, kind: "levha" });
      i += 15;
    }
  }
  // Yaya geçidi levhası: geçidin gelen trafik tarafında
  for (const cw of crosswalks) {
    const J = junctions[cw.ji], arm = J.arms[cw.arm];
    if (!arm.incoming) continue;
    const Rx = -arm.ay, Ry = arm.ax, o = arm.w / 2 + SW * 0.72;
    const P = { x: cw.c.x + Rx * o + arm.ax * 4.6, y: cw.c.y + Ry * o + arm.ay * 4.6, h: cw.c.h + CURB, fx: arm.ax, fy: arm.ay };
    if (okSpot(P)) signs.push({ key: "yaya_gecidi", ...P, kind: "levha" });
  }
  // Sokak adı: kavşak köşesinde, yola paralel
  const named = [];
  for (const J of junctions) {
    for (const arm of J.arms) {
      if (arm.r.kind === "plaza") continue;
      // Çıkan şerit yanında (gelen yanda araç ışığı var), yaya ışığının biraz ötesinde
      const Rx = arm.ay, Ry = -arm.ax, o = arm.w / 2 + SW * 0.55;
      const d = (arm.cw ? arm.c : arm.st) + 4.6;
      const p = at(arm.r, arm.s0 + arm.dir * d);
      const P = { x: p.x + Rx * o, y: p.y + Ry * o, h: p.h + CURB, fx: Rx, fy: Ry };
      if (!okSpot(P) || named.some((q) => q.name === arm.r.name && Math.hypot(q.x - P.x, q.y - P.y) < 30)) continue;
      named.push({ name: arm.r.name, x: P.x, y: P.y });
      signs.push({ key: `ad|${arm.r.name}`, ...P, kind: "ad" });
    }
  }
  // Reklam panoları: çevre yolunun iç yanında ve caddelerde, yoldan geride, yola bakar
  const boards = [];
  const tryBoard = (r, s, side) => {
    const p = at(r, s), Rx = -p.dy * side, Ry = p.dx * side, o = r.width / 2 + SW + 6;
    const x = p.x + Rx * o, y = p.y + Ry * o;
    const nr = nearestRoad(x, y);
    if (M.inland(x, y) < 12 || (nr && nr.e < 4.5) || JUNC.some((j) => Math.hypot(j.x - x, j.y - y) < 45) || inShop(x, y, 12)) return false;
    if (boards.some((b) => Math.hypot(b.x - x, b.y - y) < 160)) return false;
    boards.push({ x, y, h: p.h, fx: -Rx * 0.9 + p.dx * 0.44 * side, fy: -Ry * 0.9 + p.dy * 0.44 * side, idx: boards.length });
    return true;
  };
  const ring = ROADS[0];
  const inlandSide = (() => { const p = at(ring, 10); return M.inland(p.x - p.dy * 20, p.y + p.dx * 20) > M.inland(p.x + p.dy * 20, p.y - p.dx * 20) ? 1 : -1; })();
  for (let s = 60; s < lenOf(ring) && boards.length < 8; s += 110) tryBoard(ring, s, inlandSide);
  for (const r of ROADS.filter((q) => q.kind === "avenue")) for (const s of [lenOf(r) * 0.45, lenOf(r) * 0.7]) if (boards.length < 12) tryBoard(r, s, 1) || tryBoard(r, s, -1);

  // ---------- Sokak eşyaları (Poly Haven, assets/props) ----------
  // Lamba: kaldırımın dış kenarında ~36 m'de bir (yanlar sırayla); bank: ~90 m'de bir, yola bakar,
  // yanında çöp kovası; yangın musluğu: bordür yanında ~130 m'de bir. Kavşak, yaya geçidi ucu,
  // ışık ve tabelalardan uzak; yalnız kaldırımda.
  const props = [];
  const busy = (x, y, R) => props.some((q) => Math.hypot(q.x - x, q.y - y) < R) ||
    lights.some((L) => Math.hypot(L.x - x, L.y - y) < R + 0.5) || signs.some((q) => Math.hypot(q.x - x, q.y - y) < R) ||
    crosswalks.some((c) => Math.hypot(c.A.x - x, c.A.y - y) < 3.5 || Math.hypot(c.B.x - x, c.B.y - y) < 3.5);
  const nearJ = (x, y, R) => JUNC.some((j) => Math.hypot(j.x - x, j.y - y) < R);
  const put = (t, x, y, h, fx, fy, R = 1.6) => {
    if (!walkable(x, y) || busy(x, y, R) || nearJ(x, y, 13) || inShop(x, y, 3)) return false;
    props.push({ t, x, y, h, fx, fy });
    return true;
  };
  for (const r of ROADS) {
    if (r.kind === "plaza" || r.id === "port") continue;
    const L = lenOf(r), half = r.width / 2;
    let side = 1, k = 0;
    for (let s = 18; s < L - 6; s += 36, k++) {
      const p = at(r, s), Rx = -p.dy * side, Ry = p.dx * side;
      const o = half + SW - 0.4;
      // Lamba (yola bakar)
      if (put("street_lamp_01", p.x + Rx * o, p.y + Ry * o, p.h + CURB, -Rx, -Ry, 2.0) && k % 5 === 2) {
        const q = at(r, s + 1.6);
        put("metal_trash_can", q.x + Rx * o, q.y + Ry * o, q.h + CURB, -Rx, -Ry, 1.0);
      }
      side = -side;
    }
    if (["avenue", "street"].includes(r.kind)) {
      side = 1;
      for (let s = 45; s < L - 20; s += 90) {
        const p = at(r, s), Rx = -p.dy * side, Ry = p.dx * side, o = half + SW - 0.45;
        if (put("painted_wooden_bench", p.x + Rx * o, p.y + Ry * o, p.h + CURB, -Rx, -Ry, 2.0)) {
          const q = at(r, s + 1.5);
          put("metal_trash_can", q.x + Rx * o, q.y + Ry * o, q.h + CURB, -Rx, -Ry, 0.9);
        }
        side = -side;
      }
    }
    if (r.kind !== "serp") {
      side = -1;
      for (let s = 60; s < L - 20; s += 130) {
        const p = at(r, s), Rx = -p.dy * side, Ry = p.dx * side, o = half + 0.45;
        put("fire_hydrant", p.x + Rx * o, p.y + Ry * o, p.h + CURB, Rx, Ry, 1.5);
        side = -side;
      }
    }
  }
  // Meydan: kenarda halka halinde bank (içe bakar), aralarında saksı kutusu; birkaç çöp kovası
  {
    const P = ctx.S.plaza, ph = ctx.M.plazaH + 0.03;
    for (let k = 0; k < 10; k++) {
      const a = M.TAU * (k + 0.5) / 10, rr = P.r - 2.2;
      const x = P.x + Math.cos(a) * rr, y = P.y + Math.sin(a) * rr;
      props.push({ t: "painted_wooden_bench", x, y, h: ph, fx: -Math.cos(a), fy: -Math.sin(a) });
      const b = a + M.TAU / 20, x2 = P.x + Math.cos(b) * rr, y2 = P.y + Math.sin(b) * rr;
      props.push({ t: k % 3 === 0 ? "metal_trash_can" : "planter_box_01", x: x2, y: y2, h: ph, fx: -Math.cos(b), fy: -Math.sin(b) });
    }
  }
  // Liman: iskelelerin kara ucunda fıçı ve kasa yığınları
  for (const pr of ctx.piers || []) {
    const ax = Math.cos(pr.angle), ay = Math.sin(pr.angle), sx = -ay, sy = ax;
    const base = { x: pr.x - ax * pr.length / 2, y: pr.y - ay * pr.length / 2 };
    const items = [["barrel_03", 5, 2.6], ["barrel_03", 5.8, 2.0], ["plastic_crate_02", 6.4, 2.7], ["barrel_03", 14, -2.6],
      ["plastic_crate_02", 14.6, -2.2], ["plastic_crate_02", 14.6, -2.2, 0.25], ["barrel_03", 26, 2.5]];
    for (const [t, d, off, lift = 0] of items) {
      props.push({ t, x: base.x + ax * d + sx * off, y: base.y + ay * d + sy * off, h: pr.h + lift, fx: Math.cos(d), fy: Math.sin(d) });
    }
  }

  // ---------- Çıktı ----------
  const G = (p) => [r3(p.x), r3(p.h), r3(-p.y)];
  const trafik = {
    timing: TIMING,
    lanes: lanes.map((l) => ({
      k: l.kind === "conn" ? 1 : 0, road: l.road.id, p: l.pts.flatMap(G), v: l.v.map((v) => r3(v)),
      next: l.next, w: l.weights, len: r3(l.len),
      // Bu şeridin sonu bir ışığa mı bağlı? (kavşak, kol)
      j: l.kind === "lane" && l.to ? l.to.ji : -1, arm: l.kind === "lane" && l.to ? l.to.idx : -1,
      cj: l.kind === "conn" ? l.ji : -1, t: l.kind === "conn" ? l.turn : "", fa: l.kind === "conn" ? l.fromArm : -1,
    })),
    junctions: junctions.map((J) => ({ p: G(J), phases: J.phases, groups: J.groups, cycle: r3(J.cycle), offset: r3(J.offset), arms: J.arms.length })),
    crosswalks: crosswalks.map((c) => ({ j: c.ji, arm: c.arm, a: G({ ...c.A, h: c.A.h + CURB }), b: G({ ...c.B, h: c.B.h + CURB }) })),
  };
  const street = {
    crosswalks: crosswalks.map((c) => ({ c: [r3(c.c.x), r3(c.c.y), r3(c.c.h)], ax: r3(c.ax), ay: r3(c.ay), w: r3(c.w) })),
    stopLines: stopLines.map((s) => [r3(s.a.x), r3(s.a.y), r3(s.a.h), r3(s.b.x), r3(s.b.y), r3(s.b.h)]),
    lights: lights.map((L) => ({ kind: L.kind, j: L.ji, arm: L.arm, p: [r3(L.x), r3(L.y), r3(L.h)], f: [r3(L.fx), r3(L.fy)] })),
    signs: signs.map((s) => ({ key: s.key, kind: s.kind, p: [r3(s.x), r3(s.y), r3(s.h)], f: [r3(s.fx), r3(s.fy)] })),
    billboards: boards.map((b) => ({ idx: b.idx, p: [r3(b.x), r3(b.y), r3(b.h)], f: [r3(b.fx), r3(b.fy)] })),
    props: props.map((q) => ({ t: q.t, p: [r3(q.x), r3(q.y), r3(q.h)], f: [r3(q.fx), r3(q.fy)] })),
  };
  console.log(`TRAFİK: ${lanes.filter((l) => l.kind === "lane").length} şerit, ${lanes.filter((l) => l.kind === "conn").length} geçiş,`,
    `${junctions.filter((J) => J.phases.length).length} ışıklı kavşak, ${crosswalks.length} yaya geçidi, ${lights.length} ışık başı,`,
    `${signs.length} tabela, ${boards.length} reklam panosu, ${props.length} sokak eşyası`);
  return { trafik, street, crosswalks };
};
