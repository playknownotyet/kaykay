// Ada verisini üretir: onaylı plan (tools/ada/plan.json) + önizleme modeli (tools/ada/ada_plani.html,
// tek gerçek kaynak) -> assets/ada/ada.json (yollar, kaldırımlar, kavşaklar, bariyer, iskeleler,
// meydan, başlangıç noktası, yaya ağı) + assets/ada/ada_h.bin (yükseklik ızgaraları, zemin türü).
//
//   node tools/ada/ada_export.js
//
// Koordinatlar plan düzleminde: x doğu, y kuzey, h yükseklik (metre). Godot'ta (x, h, -y).
"use strict";
const fs = require("fs");
const path = require("path");

const HERE = __dirname, ROOT = path.resolve(HERE, "..", "..");
const OUT_DIR = path.join(ROOT, "assets", "ada");

// Sayfanın betiği tarayıcısız çalışsın diye boş DOM
const fake = () => new Proxy(function () {}, {
  get: (t, k) => {
    if (k === "getBoundingClientRect") return () => ({ width: 900, height: 600 });
    if (k === "createImageData") return (w, h) => ({ data: new Uint8ClampedArray(w * h * 4) });
    if (k === "getContext") return () => fake();
    if (k === "classList") return { toggle() {}, add() {} };
    if (k === "dataset") return {};
    if (k === "querySelectorAll") return () => [];
    if (k === Symbol.toPrimitive) return () => 0;
    return fake();
  },
  apply: () => fake(), set: () => true,
});
global.document = { getElementById: () => fake(), createElement: () => fake(), documentElement: {}, head: fake() };
global.getComputedStyle = () => ({ getPropertyValue: () => "#808080" });
global.localStorage = { getItem: () => null, setItem() {} };
global.window = { addEventListener() {}, devicePixelRatio: 1 };
global.requestAnimationFrame = () => 0;
global.performance = { now: () => 0 };

const html = fs.readFileSync(path.join(HERE, "ada_plani.html"), "utf8");
const src = html.slice(html.indexOf("<script>") + 8, html.lastIndexOf("</script>"));
global.PLAN = JSON.parse(fs.readFileSync(path.join(HERE, "plan.json"), "utf8"));
// Model çalışır, iç değerleri dışarı verir
eval(src + `
;S = merge(DEFAULTS, migrate(PLAN));
buildGrid(); buildRoads();
global.M = { S, ROADS, JUNC, SERP_INFO, FLOW, height, inland, coastR, gridH, dirAt, nearestOn, plazaH, ETEK_H, harborPt, rad, TAU };
`);

const { S, ROADS, JUNC } = M;
// Sokak adları (tabelalarda görünür): hayvanlar şehri
const NAMES = {
  ring: "Sahil Yolu", plaza: "Meydan", etek0: "Etek Yolu", serp: "Serpantin Yolu", summit: "Seyir Tepesi",
  port: "İskele Sokak", in0_0: "Halka Sokak", in1_0: "Zeytin Sokak", in1_1: "İncir Sokak",
  av0: "Kedi Caddesi", av1: "Papağan Caddesi", av2: "Tilki Caddesi", av3: "Aslan Bulvarı", av4: "Fil Caddesi",
  av5: "Kurbağa Caddesi", av6: "Güvercin Caddesi", av7: "Tavşan Caddesi", av8: "Köpek Caddesi",
};
for (const r of ROADS) if (NAMES[r.id]) r.name = NAMES[r.id];
const r3 = (v) => Math.round(v * 1000) / 1000;
const SW = S.build.sidewalk, CURB = S.build.curb;

// ---------------------------------------------------------------------------
// Segment uzaysal dizini (yakın yol araması)
// ---------------------------------------------------------------------------
const CELL = 16, buckets = new Map();
const segs = [];
for (const r of ROADS) {
  for (let i = 0; i < r.pts.length - 1; i++) {
    const a = r.pts[i], b = r.pts[i + 1];
    const s = { r, i, ax: a.x, ay: a.y, bx: b.x, by: b.y, ha: r.prof.h[i], hb: r.prof.h[i + 1], half: r.width / 2,
      first: !r.closed && i === 0, last: !r.closed && i === r.pts.length - 2 };
    segs.push(s);
    const x0 = Math.floor((Math.min(a.x, b.x) - 40) / CELL), x1 = Math.floor((Math.max(a.x, b.x) + 40) / CELL);
    const y0 = Math.floor((Math.min(a.y, b.y) - 40) / CELL), y1 = Math.floor((Math.max(a.y, b.y) + 40) / CELL);
    for (let gx = x0; gx <= x1; gx++) for (let gy = y0; gy <= y1; gy++) {
      const k = gx + "," + gy; if (!buckets.has(k)) buckets.set(k, []); buckets.get(k).push(s);
    }
  }
}
// En "içte" kalan yol: (merkez çizgisine uzaklık − yarı genişlik) en küçük olan.
// lateral: yalnız yolun boyu içinde kalan noktalar sayılır (bitiş ucunun ötesi değil): T kavşağında
// karşı kaldırım, bağlanan yolun "ucuna yakın" diye kesilmez.
function nearestRoad(x, y, skip, lateral) {
  const list = buckets.get(Math.floor(x / CELL) + "," + Math.floor(y / CELL));
  if (!list) return null;
  let best = null;
  for (const s of list) {
    if (skip && s.r === skip) continue;
    const dx = s.bx - s.ax, dy = s.by - s.ay, L2 = dx * dx + dy * dy || 1;
    const tr = ((x - s.ax) * dx + (y - s.ay) * dy) / L2;
    if (lateral && ((s.first && tr < 0) || (s.last && tr > 1))) continue;
    const t = Math.max(0, Math.min(1, tr));
    const d = Math.hypot(s.ax + dx * t - x, s.ay + dy * t - y);
    const e = d - s.half;
    if (!best || e < best.e) best = { e, d, h: s.ha + (s.hb - s.ha) * t, r: s.r, half: s.half };
  }
  return best;
}

// ---------------------------------------------------------------------------
// Kavşak diskleri: kavşak alanı tek parça asfalt (yolların kesiştiği köşeler dolar)
// ---------------------------------------------------------------------------
const discs = JUNC.map((j) => {
  const wmax = Math.max(...j.members.map((m) => m.r.width));
  // Yalnız kesişme karesi: köşe asfaltını köşe dolguları verir (bkz. köşe dönüşleri)
  return { x: j.x, y: j.y, h: j.h, r: wmax / 2 + 0.5, roads: j.members.map((m) => m.r.id), plaza: !!j.roundabout };
});
const inDisc = (x, y, pad = 0) => discs.some((d) => Math.hypot(x - d.x, y - d.y) < d.r + pad);

// ---------------------------------------------------------------------------
// Yol yüzeyi yüksekliği: kavşaklarda yollar üst üste biner. Eğimde iki yolun yüzeyi farklı
// yükseklikte kalınca kenarda basamak oluşuyordu (kaykay takılıyordu). Bir noktanın yüzeyi:
// onu içeren yollardan kavşaktan "devam eden"inin yüksekliği (orada biten yolun ucu ona uyar);
// eşitse merkez çizgisine en yakın olanın. Yol şeritleri, kavşak diskleri ve köşe dolguları
// köşelerini bu yüzeye oturtur.
// ---------------------------------------------------------------------------
const endZone = new Map();          // yol -> [başta biten bölge uzunluğu, sonda]
{
  const cumOf = (r) => { const c = [0]; for (let i = 1; i < r.pts.length; i++) c.push(c[i - 1] + Math.hypot(r.pts[i].x - r.pts[i - 1].x, r.pts[i].y - r.pts[i - 1].y)); return c; };
  for (const r of ROADS) {
    const z = [0, 0];
    if (!r.closed) {
      for (const j of JUNC) {
        const m = j.members.find((q) => q.r === r);
        if (!m || (m.i !== 0 && m.i !== r.pts.length - 1)) continue;
        const other = Math.max(...j.members.filter((q) => q.r !== r).map((q) => q.r.width / 2), 0);
        z[m.i === 0 ? 0 : 1] = other + 8;
      }
    }
    r._cum = cumOf(r);
    endZone.set(r, z);
  }
}
function surfH(x, y) {
  // Yol başına en içteki parça; ağırlık: içeride olma derinliği (kenarda sıfıra iner) ve
  // öncelik (biten yolun ucu, bölgeye girdikçe 3 m'de yumuşakça geri çekilir): yüzey süreklidir.
  const list = buckets.get(Math.floor(x / CELL) + "," + Math.floor(y / CELL));
  const per = new Map();
  if (list) {
    for (const sg of list) {
      const dx = sg.bx - sg.ax, dy = sg.by - sg.ay, L2 = dx * dx + dy * dy || 1;
      const t = Math.max(0, Math.min(1, ((x - sg.ax) * dx + (y - sg.ay) * dy) / L2));
      const d = Math.hypot(sg.ax + dx * t - x, sg.ay + dy * t - y), e = d - sg.half;
      if (e > 0.6) continue;
      const cur = per.get(sg.r);
      if (cur && cur.e <= e) continue;
      const r = sg.r, z = endZone.get(r), sAt = r._cum[sg.i] + Math.sqrt(L2) * t, L = r._cum[r._cum.length - 1];
      let into = 0;
      if (z[0]) into = Math.max(into, z[0] - sAt);
      if (z[1]) into = Math.max(into, sAt - (L - z[1]));
      const pri = 1 + 7 * (1 - Math.max(0, Math.min(1, into / 3)));
      per.set(sg.r, { e, pri, h: sg.ha + (sg.hb - sg.ha) * t });
    }
  }
  let ws = 0, hs = 0;
  for (const c of per.values()) {
    const k = Math.max(0, Math.min(1, (0.6 - c.e) / 2.0));
    const w = k * k * c.pri;
    ws += w; hs += w * c.h;
  }
  if (ws > 1e-6) return hs / ws;
  const nr = nearestRoad(x, y);
  return nr ? nr.h : M.height(x, y);
}

// ---------------------------------------------------------------------------
// Yollar, kaldırımlar, orta çizgiler
// ---------------------------------------------------------------------------
const roadsOut = [], walkRuns = [], centerRuns = [], sidewalkRuns = [];
const SETBACK = S.build.fillet * 0.55;
for (const r of ROADS) {
  const n = r.pts.length, half = r.width / 2;
  // Şerit kaplaması: satır satır sol / orta / sağ köşeler yol yüzeyinde. Kavşak çevresinde 1 m'de
  // bir (yüzey orada kıvrılır; kavşak kaplamasıyla aynı yüzeye otursun), başka yerde 4 m'de bir.
  const rib = [];
  {
    const c = r._cum, L = c[c.length - 1] + (r.closed ? Math.hypot(r.pts[0].x - r.pts[n - 1].x, r.pts[0].y - r.pts[n - 1].y) : 0);
    const P = (sq) => {
      sq = r.closed ? ((sq % L) + L) % L : Math.max(0, Math.min(L, sq));
      let i = 0; while (i < n - 1 && c[i + 1] < sq) i++;
      const a = r.pts[i], b = r.pts[(i + 1) % n], ca = c[i], cb = i + 1 < n ? c[i + 1] : L;
      const t = Math.max(0, Math.min(1, (sq - ca) / ((cb - ca) || 1)));
      return { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t };
    };
    const nearJ = (q) => JUNC.some((j) => Math.hypot(j.x - q.x, j.y - q.y) < 22);
    let sq = 0;
    while (true) {
      const q = P(sq), q2 = P(sq + 0.5), q1 = P(sq - 0.5);
      let dx = q2.x - q1.x, dy = q2.y - q1.y; const dl = Math.hypot(dx, dy) || 1; dx /= dl; dy /= dl;
      const lx = q.x - dy * half, ly = q.y + dx * half, rx = q.x + dy * half, ry = q.y - dx * half;
      rib.push([r3(lx), r3(ly), r3(surfH(lx, ly)), r3(q.x), r3(q.y), r3(surfH(q.x, q.y)), r3(rx), r3(ry), r3(surfH(rx, ry))]);
      if (sq >= L - 1e-3) break;
      sq = Math.min(L, sq + (nearJ(q) ? 1.0 : 4.0));
    }
  }
  roadsOut.push({ id: r.id, name: r.name, kind: r.kind, width: r.width, closed: !!r.closed, rib,
    pts: r.pts.map((p, i) => [r3(p.x), r3(p.y), r3(r.prof.h[i])]) });
  // Kaldırımlar: iki yanda; başka yolun asfaltına ya da kavşak diskine giren yerlerde kesilir
  for (const side of [1, -1]) {
    let run = [], first = null, startsAt0 = false;
    const flush = () => {
      if (run.length >= 2) { const o = { road: r.id, side, pts: run }; sidewalkRuns.push(o); if (!first) first = o; }
      run = [];
    };
    for (let i = 0; i < n; i++) {
      const d = M.dirAt(r.pts, i), nx = -d.y * side, ny = d.x * side, p = r.pts[i], h = r.prof.h[i];
      const ix = p.x + nx * half, iy = p.y + ny * half, ox = p.x + nx * (half + SW), oy = p.y + ny * (half + SW);
      const mx = (ix + ox) / 2, my = (iy + oy) / 2;
      // Başka bir yol yanından geçiyorsa kesilir; köşe dönüşüne yer kalsın diye o yolun
      // kenarından SETBACK kadar önce (yolun ucunun ötesindeki karşı kaldırım kesilmez)
      const other = nearestRoad(mx, my, r, true);
      const blocked = other && other.e < SETBACK;
      if (blocked) flush();
      else { if (i === 0) startsAt0 = true; run.push([r3(ix), r3(iy), r3(ox), r3(oy), r3(h)]); }
    }
    // Kapalı yolda son parça dikişe kadar geliyorsa ilk parçayla birleşir
    if (r.closed && startsAt0 && first && run.length >= 1 && first !== null) {
      first.pts = run.concat(first.pts.slice(Math.hypot(run[run.length - 1][0] - first.pts[0][0], run[run.length - 1][1] - first.pts[0][1]) < 0.05 ? 1 : 0));
      run = [];
    }
    // Hiç kesilmeyen kapalı halka (meydan göbeğinin iç kaldırımı): başa dönerek kapanır
    if (r.closed && !first && run.length === n) run.push(run[0]);
    flush();
  }
  // Orta kesikli çizgi: cadde, çevre yolu, serpantin, etek yolu
  if (["ring", "avenue", "serp"].includes(r.kind) || r.id.startsWith("etek")) {
    let run = [];
    for (let i = 0; i < n; i++) {
      const p = r.pts[i];
      if (inDisc(p.x, p.y, 7)) { if (run.length >= 2) centerRuns.push(run); run = []; continue; }
      run.push([r3(p.x), r3(p.y), r3(r.prof.h[i])]);
    }
    if (run.length >= 2) centerRuns.push(run);
  }
}

// ---------------------------------------------------------------------------
// Üçgen adalar
// ---------------------------------------------------------------------------
const segX = (a, b, c, d) => {
  const rx = b.x - a.x, ry = b.y - a.y, sx = d.x - c.x, sy = d.y - c.y, den = rx * sy - ry * sx;
  if (Math.abs(den) < 1e-9) return null;
  const t = ((c.x - a.x) * sy - (c.y - a.y) * sx) / den, u = ((c.x - a.x) * ry - (c.y - a.y) * rx) / den;
  return t >= 0 && t <= 1 && u >= 0 && u <= 1 ? { x: a.x + rx * t, y: a.y + ry * t, t, u } : null;
};
const inPoly = (poly, x, y) => {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const a = poly[j], b = poly[i];
    if ((a.y > y) !== (b.y > y) && x < a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y)) inside = !inside;
  }
  return inside;
};
function triangleIslands() {
  const J = JUNC.filter((j) => !j.roundabout);
  const shared = (a, b) => { for (const m of a.members) { const o = b.members.find((q) => q.r === m.r); if (o) return { r: m.r, ia: m.i, ib: o.i }; } return null; };
  const done = new Set();
  for (let a = 0; a < J.length; a++) for (let b = a + 1; b < J.length; b++) for (let c = b + 1; c < J.length; c++) {
    const T = [J[a], J[b], J[c]];
    const per = Math.hypot(T[0].x - T[1].x, T[0].y - T[1].y) + Math.hypot(T[1].x - T[2].x, T[1].y - T[2].y) + Math.hypot(T[2].x - T[0].x, T[2].y - T[0].y);
    if (per > 150) continue;
    const E = [shared(T[0], T[1]), shared(T[1], T[2]), shared(T[2], T[0])];
    if (E.some((e) => !e) || new Set(E.map((e) => e.r)).size < 3) continue;
    const cx = (T[0].x + T[1].x + T[2].x) / 3, cy = (T[0].y + T[1].y + T[2].y) / 3;
    // Her kenar: yolun iki kavşak arası kısmı, üçgenin içine doğru yarı genişlik kaydırılmış
    const lines = E.map((e) => {
      const n = e.r.pts.length, out = [];
      let i0 = e.ia, i1 = e.ib;
      if (e.r.closed && Math.abs(i1 - i0) > n / 2) return null;
      const st = i1 >= i0 ? 1 : -1;
      for (let i = i0; ; i += st) {
        const p = e.r.pts[i], d = M.dirAt(e.r.pts, i);
        let nx = -d.y, ny = d.x;
        if (nx * (cx - p.x) + ny * (cy - p.y) < 0) { nx = -nx; ny = -ny; }
        out.push({ x: p.x + nx * e.r.width / 2, y: p.y + ny * e.r.width / 2, h: e.r.prof.h[i] });
        if (i === i1) break;
      }
      return out;
    });
    if (lines.some((l) => !l || l.length < 2)) continue;
    // Ardışık kenarların kesiştiği köşeler (yol kenarlarının buluştuğu yer)
    const cut = [];
    for (let k = 0; k < 3; k++) {
      const A = lines[k], B = lines[(k + 1) % 3];
      let hit = null;
      for (let i = A.length - 2; i >= 0 && !hit; i--) for (let j = 0; j < B.length - 1 && !hit; j++) {
        const q = segX(A[i], A[i + 1], B[j], B[j + 1]);
        if (q) hit = { x: q.x, y: q.y, h: A[i].h + (A[i + 1].h - A[i].h) * q.t, ia: i, jb: j };
      }
      if (!hit) break;
      cut.push(hit);
    }
    if (cut.length < 3) continue;
    const key = E.map((e) => e.r.id).sort().join("|") + Math.round(cx) + "," + Math.round(cy);
    if (done.has(key)) continue;
    done.add(key);
    // Kenar (köşeden köşeye) ve köşe yuvarlakları
    const RF = 3, loop = [];
    for (let k = 0; k < 3; k++) {
      const st = cut[(k + 2) % 3], en = cut[k], L = lines[k];
      const pts = [{ x: st.x, y: st.y, h: st.h }];
      for (let i = st.jb + 1; i <= en.ia; i++) pts.push(L[i]);
      pts.push({ x: en.x, y: en.y, h: en.h });
      loop.push(pts);
    }
    // Köşe yuvarlakları: köşeye giren / çıkan yön (köşeden >= 2 m uzaktaki noktaya göre)
    const plen = (pts) => pts.reduce((u, q, i) => i ? u + Math.hypot(q.x - pts[i - 1].x, q.y - pts[i - 1].y) : 0, 0);
    const far = (pts, C, back) => {
      const seq = back ? pts.slice().reverse() : pts;
      return seq.find((q) => Math.hypot(q.x - C.x, q.y - C.y) >= 2) || seq[seq.length - 1];
    };
    const corners = [];
    for (let k = 0; k < 3; k++) {
      const cur = loop[k], nxt = loop[(k + 1) % 3], C = cur[cur.length - 1];
      const pin = far(cur, C, true), pout = far(nxt, C, false);
      const lu = Math.hypot(C.x - pin.x, C.y - pin.y) || 1, lv = Math.hypot(pout.x - C.x, pout.y - C.y) || 1;
      const ux = (C.x - pin.x) / lu, uy = (C.y - pin.y) / lu, vx = (pout.x - C.x) / lv, vy = (pout.y - C.y) / lv;
      const half = (Math.PI - Math.acos(Math.max(-1, Math.min(1, ux * vx + uy * vy)))) / 2;
      const tmax = 0.4 * Math.min(plen(cur), plen(nxt));
      let r = RF, t = r / Math.tan(half);
      if (t > tmax) { t = tmax; r = t * Math.tan(half); }
      corners.push({ C, ux, uy, vx, vy, r, t: r > 0.2 && isFinite(t) ? t : 0 });
    }
    const ring = [];
    for (let k = 0; k < 3; k++) {
      const cur = loop[k], cp = corners[(k + 2) % 3], cn = corners[k];
      for (const q of cur) {
        if (Math.hypot(q.x - cp.C.x, q.y - cp.C.y) <= cp.t + 0.05 || Math.hypot(q.x - cn.C.x, q.y - cn.C.y) <= cn.t + 0.05) continue;
        ring.push(q);
      }
      const { C, ux, uy, vx, vy, r, t } = cn;
      if (!t) { ring.push(C); continue; }
      const T1 = { x: C.x - ux * t, y: C.y - uy * t }, T2 = { x: C.x + vx * t, y: C.y + vy * t };
      let nx = -uy, ny = ux;
      if (nx * (cx - C.x) + ny * (cy - C.y) < 0) { nx = -nx; ny = -ny; }
      const ox = T1.x + nx * r, oy = T1.y + ny * r;
      const a0 = Math.atan2(T1.y - oy, T1.x - ox), a1 = Math.atan2(T2.y - oy, T2.x - ox);
      let da = a1 - a0; while (da > Math.PI) da -= M.TAU; while (da < -Math.PI) da += M.TAU;
      const n = Math.max(3, Math.ceil(Math.abs(da) * r / 0.7)), arcPts = [];
      for (let q = 0; q <= n; q++) arcPts.push({ x: ox + Math.cos(a0 + da * q / n) * r, y: oy + Math.sin(a0 + da * q / n) * r, h: C.h });
      // Köşe yuvarlağı arkası (keskin köşe ile yay arası) asfalt
      cornerFills.push({ c: [r3(C.x), r3(C.y), r3(C.h)], pts: arcPts.map((q) => [r3(q.x), r3(q.y), r3(q.h)]) });
      for (const q of arcPts) ring.push(q);
    }
    // Üçgenin içindeki eski kaldırım parçaları atılır
    const poly = ring.map((q) => ({ x: q.x, y: q.y }));
    for (let i = sidewalkRuns.length - 1; i >= 0; i--) {
      const run = sidewalkRuns[i];
      const inside = run.pts.filter((v) => inPoly(poly, (v[0] + v[2]) / 2, (v[1] + v[3]) / 2)).length;
      if (inside > run.pts.length / 2) sidewalkRuns.splice(i, 1);
    }
    // Ada: bordür halkası ile ağırlık merkezi arası yelpaze (kaldırım parçası biçiminde)
    const hm = ring.reduce((u, q) => u + q.h, 0) / ring.length;
    const pts = ring.concat([ring[0]]).map((q) => [r3(q.x), r3(q.y), r3(cx), r3(cy), r3(q.h)]);
    sidewalkRuns.push({ road: "ada", side: 0, pts });
    islands.push({ h: hm, poly: ring.map((q) => [q.x, q.y]) });
  }
}

// ---------------------------------------------------------------------------
// Artakalan köşeler: kavşak köşe dönüşüyle birleşemeyen uçlar. Çok dar açılı kavşak (iki yol
// birbirine 20-30° ile katılır) ya da arada kaldırım sığmayacak kadar kısa bir yol parçası
// (iki kavşak arası) varsa, bordür yolların kenarını izleyerek bir uçtan öbürüne gider.
// Geniş köşede normal kaldırım şeridi, dar kamada dolu yaya adası olur.
// ---------------------------------------------------------------------------
function roadEdge(r, i0, i1, sideOf) {
  const out = [], st = i1 >= i0 ? 1 : -1;
  for (let i = i0; ; i += st) {
    const p = r.pts[i], d = M.dirAt(r.pts, i), sg = sideOf(p, d);
    out.push({ x: p.x - d.y * sg * r.width / 2, y: p.y + d.x * sg * r.width / 2, h: r.prof.h[i] });
    if (i === i1) break;
  }
  return out;
}
const nearestIdx = (r, x, y) => { let b = 0, bd = Infinity; r.pts.forEach((p, i) => { const d = Math.hypot(p.x - x, p.y - y); if (d < bd) { bd = d; b = i; } }); return b; };
function leftoverCorners(ends) {
  const free = ends.filter((e) => !e.used && e.road !== "ada" && e.road !== "kose");
  const byId = new Map(ROADS.map((r) => [r.id, r]));
  // Bir ucun kendi yolundaki en yakın kavşağı (40 m içinde)
  const juncOf = (e) => {
    let best = null;
    for (const j of JUNC) {
      const m = j.members.find((q) => q.r.id === e.road);
      const d = Math.hypot(j.x - e.ix, j.y - e.iy);
      if (m && d < 40 && (!best || d < best.d)) best = { j, m, d };
    }
    return best;
  };
  const tries = [];
  for (const A of free) for (const B of free) {
    if (A === B || A.road === B.road) continue;
    const ja = juncOf(A), jb = juncOf(B);
    if (!ja || !jb) continue;
    const rA = byId.get(A.road), rB = byId.get(B.road);
    const sideA = (p, d) => A.side, sideB = (p, d) => B.side;
    let lines;
    if (ja.j === jb.j) {
      const mb = ja.j.members.find((q) => q.r === rB);
      if (!mb) continue;
      lines = [roadEdge(rA, nearestIdx(rA, A.ix, A.iy), ja.m.i, sideA), roadEdge(rB, mb.i, nearestIdx(rB, B.ix, B.iy), sideB)];
    } else {
      // Aradaki yol: iki kavşağı bağlayan, uçların ikisinin de aynı yanında kaldığı yol
      const R = ja.j.members.map((q) => q.r).find((r) => r !== rA && r !== rB && jb.j.members.some((q) => q.r === r));
      if (!R || Math.hypot(ja.j.x - jb.j.x, ja.j.y - jb.j.y) > 60) continue;
      const i0 = ja.j.members.find((q) => q.r === R).i, i1 = jb.j.members.find((q) => q.r === R).i;
      const mid = R.pts[Math.round((i0 + i1) / 2)], dm = M.dirAt(R.pts, Math.round((i0 + i1) / 2));
      const sa = Math.sign(-dm.y * (A.ix - mid.x) + dm.x * (A.iy - mid.y)), sb = Math.sign(-dm.y * (B.ix - mid.x) + dm.x * (B.iy - mid.y));
      if (sa !== sb) continue;
      const mbB = jb.j.members.find((q) => q.r === rB);
      if (!mbB) continue;
      lines = [roadEdge(rA, nearestIdx(rA, A.ix, A.iy), ja.m.i, sideA), roadEdge(R, i0, i1, () => sa), roadEdge(rB, mbB.i, nearestIdx(rB, B.ix, B.iy), sideB)];
    }
    if (lines.some((l) => l.length < 2)) continue;
    tries.push({ A, B, lines });
  }
  const built = [];
  for (const T of tries) {
    const { A, B, lines } = T;
    if (A.used || B.used) continue;
    // Ardışık kenarların kesişimi
    const cuts = [];
    for (let k = 0; k < lines.length - 1; k++) {
      const L1 = lines[k], L2 = lines[k + 1];
      let hit = null;
      for (let i = L1.length - 2; i >= 0 && !hit; i--) for (let j = 0; j < L2.length - 1 && !hit; j++) {
        const q = segX(L1[i], L1[i + 1], L2[j], L2[j + 1]);
        if (q) hit = { x: q.x, y: q.y, h: L1[i].h + (L1[i + 1].h - L1[i].h) * q.t, ia: i, jb: j };
      }
      if (!hit) break;
      cuts.push(hit);
    }
    if (cuts.length < lines.length - 1) continue;
    const pieces = lines.map((L, k) => {
      const st = k ? cuts[k - 1] : null, en = k < cuts.length ? cuts[k] : null;
      const pts = [];
      if (st) pts.push({ x: st.x, y: st.y, h: st.h });
      for (let i = st ? st.jb + 1 : 0; i <= (en ? en.ia : L.length - 1); i++) pts.push(L[i]);
      if (en) pts.push({ x: en.x, y: en.y, h: en.h });
      return pts;
    });
    // Uçlar tam kaldırım ucundan başlasın
    pieces[0][0] = { x: A.ix, y: A.iy, h: A.h };
    const lp = pieces[pieces.length - 1];
    lp[lp.length - 1] = { x: B.ix, y: B.iy, h: B.h };
    // Köşe yuvarlakları
    const plen = (pts) => pts.reduce((u, q, i) => i ? u + Math.hypot(q.x - pts[i - 1].x, q.y - pts[i - 1].y) : 0, 0);
    const far = (pts, C, back) => { const seq = back ? pts.slice().reverse() : pts; return seq.find((q) => Math.hypot(q.x - C.x, q.y - C.y) >= 2) || seq[seq.length - 1]; };
    const chain = [], fills = [];
    let acute = false, prevT = 0;
    for (let k = 0; k < pieces.length; k++) {
      const cur = pieces[k];
      if (k === pieces.length - 1) { for (const q of cur) if (!chain.length || Math.hypot(q.x - cur[0].x, q.y - cur[0].y) > prevT + 0.05) chain.push(q); break; }
      const nxt = pieces[k + 1], C = cur[cur.length - 1];
      const pin = far(cur, C, true), pout = far(nxt, C, false);
      const lu = Math.hypot(C.x - pin.x, C.y - pin.y) || 1, lv = Math.hypot(pout.x - C.x, pout.y - C.y) || 1;
      const ux = (C.x - pin.x) / lu, uy = (C.y - pin.y) / lu, vx = (pout.x - C.x) / lv, vy = (pout.y - C.y) / lv;
      const half = (Math.PI - Math.acos(Math.max(-1, Math.min(1, ux * vx + uy * vy)))) / 2;
      if (half * 2 < M.rad(70)) acute = true;
      const tmax = 0.45 * Math.min(plen(cur), plen(nxt));
      let r = 4, t = r / Math.tan(half);
      if (t > tmax) { t = tmax; r = t * Math.tan(half); }
      for (const q of cur) {
        if (k > 0 && Math.hypot(q.x - cur[0].x, q.y - cur[0].y) <= prevT + 0.05) continue;
        if (Math.hypot(q.x - C.x, q.y - C.y) <= t + 0.05) continue;
        chain.push(q);
      }
      const T1 = { x: C.x - ux * t, y: C.y - uy * t }, T2 = { x: C.x + vx * t, y: C.y + vy * t };
      let nx = -uy, ny = ux;
      if (nx * (vx - ux) + ny * (vy - uy) < 0) { nx = -nx; ny = -ny; }
      const ox = T1.x + nx * r, oy = T1.y + ny * r;
      const a0 = Math.atan2(T1.y - oy, T1.x - ox), a1 = Math.atan2(T2.y - oy, T2.x - ox);
      let da = a1 - a0; while (da > Math.PI) da -= M.TAU; while (da < -Math.PI) da += M.TAU;
      const n = Math.max(3, Math.ceil(Math.abs(da) * r / 0.7)), arcPts = [];
      for (let q = 0; q <= n; q++) arcPts.push({ x: ox + Math.cos(a0 + da * q / n) * r, y: oy + Math.sin(a0 + da * q / n) * r, h: C.h });
      fills.push({ c: [r3(C.x), r3(C.y), r3(C.h)], pts: arcPts.map((q) => [r3(q.x), r3(q.y), r3(q.h)]) });
      for (const q of arcPts) chain.push(q);
      prevT = t;
    }
    if (chain.length < 3 || plen(chain) > 140) continue;
    // Bordür bir yolun asfaltına girmesin
    if (chain.some((q) => { const o = nearestRoad(q.x, q.y); return o && o.e < -0.3; })) continue;
    let pts;
    const poly = chain.map((q) => [q.x, q.y]);
    if (acute) {
      const mx = (A.ox + B.ox) / 2, my = (A.oy + B.oy) / 2;
      pts = chain.map((q, i) => i === 0 ? [A.ix, A.iy, A.ox, A.oy, A.h] : i === chain.length - 1 ? [B.ix, B.iy, B.ox, B.oy, B.h] : [q.x, q.y, mx, my, q.h]);
      poly.push([B.ox, B.oy], [A.ox, A.oy]);
    } else {
      // Kaldırım şeridi: bordürden yolun öbür yanına SW
      pts = chain.map((q, i) => {
        if (i === 0) return [A.ix, A.iy, A.ox, A.oy, A.h];
        if (i === chain.length - 1) return [B.ix, B.iy, B.ox, B.oy, B.h];
        const a = chain[i - 1], b = chain[i + 1], L = Math.hypot(b.x - a.x, b.y - a.y) || 1;
        let nx = -(b.y - a.y) / L, ny = (b.x - a.x) / L;
        const o1 = nearestRoad(q.x + nx * 1.5, q.y + ny * 1.5), o2 = nearestRoad(q.x - nx * 1.5, q.y - ny * 1.5);
        if (o1 && o2 && o1.e < o2.e) { nx = -nx; ny = -ny; }
        return [q.x, q.y, q.x + nx * SW, q.y + ny * SW, q.h];
      });
      for (let i = chain.length - 1; i >= 0; i--) poly.push([pts[i][2], pts[i][3]]);
    }
    sidewalkRuns.push({ road: acute ? "ada" : "kose", side: 0, pts: pts.map((v) => v.map(r3)) });
    if (acute) islands.push({ h: chain.reduce((u, q) => u + q.h, 0) / chain.length, poly });
    for (const f of fills) cornerFills.push(f);
    A.used = B.used = true;
    built.push(A.road + "/" + B.road);
  }
  if (built.length) console.log("ADA: artakalan köşeler:", built.join(", "));
}

// ---------------------------------------------------------------------------
// Köşe dönüşleri: kavşakta aynı yaya adasına (köşeye) bakan iki kaldırım ucu, yuvarlak bir
// bordürle birleşir; bordür ile kavşak merkezi arası asfaltla dolar. Araya yol giren uçlar
// (karşı kaldırım) birleşmez: orası yaya geçididir.
// ---------------------------------------------------------------------------
const cornerFills = [], islands = [];
{
  // Meydan göbeğinin dış kaldırımı caddeler arasında çok kısa kalıyor (parçalar üretilmiyor,
  // aralar toprak görünüyordu): atılır, yerine caddeler arası yaya adaları (aşağıda)
  const PZ = S.plaza, pr = ROADS.find((r) => r.id === "plaza");
  const PR = pr ? Math.hypot(pr.pts[0].x - PZ.x, pr.pts[0].y - PZ.y) : 0;
  for (let i = sidewalkRuns.length - 1; i >= 0; i--) {
    const r = sidewalkRuns[i], m = r.pts[r.pts.length >> 1];
    if (r.road === "plaza" && Math.hypot((m[0] + m[2]) / 2 - PZ.x, (m[1] + m[3]) / 2 - PZ.y) > PR) sidewalkRuns.splice(i, 1);
  }
  // Üç yolun birbirine yakın kavşaklarla çevirdiği küçük üçgen: kaldırım parçaları sığmıyor
  // (toprak kalıyordu). Yol kenarları arası tek bir yaya adası olur, köşeleri yuvarlak.
  triangleIslands();
  const ends = [];
  sidewalkRuns.forEach((run) => {
    if (run.road === "ada") return;          // ada kendi içinde kapalı
    const p = run.pts;
    for (const [k, kn] of [[0, 1], [p.length - 1, p.length - 2]]) {
      const a = p[k], b = p[kn], L = Math.hypot(a[0] - b[0], a[1] - b[1]) || 1;
      ends.push({ ix: a[0], iy: a[1], ox: a[2], oy: a[3], h: a[4], dx: (a[0] - b[0]) / L, dy: (a[1] - b[1]) / L, road: run.road, side: run.side, used: false });
    }
  });
  // İki ışının (p + t·d) kesişimi; ileri yönde değilse null
  const meet = (px, py, dx, dy, qx, qy, ex, ey) => {
    const den = dx * ey - dy * ex;
    if (Math.abs(den) < 0.15) return null;                       // neredeyse paralel
    const t = ((qx - px) * ey - (qy - py) * ex) / den, s = ((qx - px) * dy - (qy - py) * dx) / den;
    if (t < -0.5 || s < -0.5 || t > 30 || s > 30) return null;
    return { x: px + dx * t, y: py + dy * t };
  };
  // Meydan göbeği: komşu iki caddenin birbirine bakan kaldırım uçları arası tek bir yaya adası.
  // Bordür caddenin kenarından iner, yuvarlak köşeyle göbeğin dış kenarına döner, onu izler,
  // öbür caddeye aynı şekilde çıkar; ada içi (bordür ile iki kaldırımın dış ucu arası) doludur.
  if (pr) {
    const Ro = PR + pr.width / 2, RF = 4;
    const best = new Map();
    for (const e of ends) {
      const dd = Math.hypot(e.ix - PZ.x, e.iy - PZ.y);
      if (e.road === "plaza" || dd > Ro + 45 || (PZ.x - e.ix) * e.dx + (PZ.y - e.iy) * e.dy < 0.6 * dd) continue;
      const key = e.road + "|" + e.side;
      if (!best.has(key) || best.get(key).dd > dd) best.set(key, { e, dd, ang: Math.atan2(e.iy - PZ.y, e.ix - PZ.x) });
    }
    const list = [...best.values()].sort((a, b) => a.ang - b.ang);
    const wrap = (a) => { while (a > Math.PI) a -= M.TAU; while (a < -Math.PI) a += M.TAU; return a; };
    // Kenar çizgisinden (a + t·d) adaya doğru r kadar içeride, göbekten Ro + r uzaktaki köşe yuvarlağı merkezi
    const fillet = (e, nx, ny, r) => {
      const qx = e.ix + nx * r - PZ.x, qy = e.iy + ny * r - PZ.y, b = qx * e.dx + qy * e.dy, c = qx * qx + qy * qy - (Ro + r) ** 2;
      if (b * b - c < 0) return null;
      const t = -b - Math.sqrt(b * b - c);
      const cx = e.ix + nx * r + e.dx * t, cy = e.iy + ny * r + e.dy * t, L = Math.hypot(cx - PZ.x, cy - PZ.y);
      return { t, cx, cy, ex: e.ix + e.dx * t, ey: e.iy + e.dy * t, rx: PZ.x + (cx - PZ.x) * Ro / L, ry: PZ.y + (cy - PZ.y) * Ro / L };
    };
    const arc = (out, cx, cy, r, a0, a1, step) => {
      const da = wrap(a1 - a0), n = Math.max(2, Math.ceil(Math.abs(da) * r / step));
      for (let q = 1; q < n; q++) out.push({ x: cx + Math.cos(a0 + da * q / n) * r, y: cy + Math.sin(a0 + da * q / n) * r });
    };
    for (let k = 0; k < list.length; k++) {
      const A = list[k].e, B = list[(k + 1) % list.length].e;
      if (A === B || A.road === B.road || A.used || B.used) continue;
      // Adaya doğru normal: A'nın kenarından B'ye, B'ninkinden A'ya
      const nA = { x: -A.dy, y: A.dx }, nB = { x: -B.dy, y: B.dx };
      if (nA.x * (B.ix - A.ix) + nA.y * (B.iy - A.iy) < 0) { nA.x = -nA.x; nA.y = -nA.y; }
      if (nB.x * (A.ix - B.ix) + nB.y * (A.iy - B.iy) < 0) { nB.x = -nB.x; nB.y = -nB.y; }
      let fa = null, fb = null, rf = 0;
      for (let r = RF; r >= 1; r -= 0.5) {
        fa = fillet(A, nA.x, nA.y, r); fb = fillet(B, nB.x, nB.y, r);
        if (!fa || !fb) continue;
        // İki köşe yuvarlağı göbek kenarında üst üste binmesin (aradaki yay ileri yönde)
        const a0 = Math.atan2(fa.ry - PZ.y, fa.rx - PZ.x), a1 = Math.atan2(fb.ry - PZ.y, fb.rx - PZ.x);
        const s0 = Math.atan2(A.iy - PZ.y, A.ix - PZ.x), s1 = Math.atan2(B.iy - PZ.y, B.ix - PZ.x);
        if (Math.sign(wrap(a1 - a0)) === Math.sign(wrap(s1 - s0)) || Math.abs(wrap(a1 - a0)) < 1e-3) { rf = r; break; }
      }
      if (!rf || fa.t < -0.5 || fb.t < -0.5) continue;
      const chain = [{ x: A.ix, y: A.iy }];
      if (fa.t > 0.5) chain.push({ x: fa.cx - nA.x * rf, y: fa.cy - nA.y * rf });
      const filletA = chain.length;
      arc(chain, fa.cx, fa.cy, rf, Math.atan2(-nA.y, -nA.x), Math.atan2(fa.ry - fa.cy, fa.rx - fa.cx), 0.8);
      chain.push({ x: fa.rx, y: fa.ry });
      const segA = chain.slice(filletA - 1);
      arc(chain, PZ.x, PZ.y, Ro, Math.atan2(fa.ry - PZ.y, fa.rx - PZ.x), Math.atan2(fb.ry - PZ.y, fb.rx - PZ.x), 1.5);
      const filletB = chain.length;
      chain.push({ x: fb.rx, y: fb.ry });
      arc(chain, fb.cx, fb.cy, rf, Math.atan2(fb.ry - fb.cy, fb.rx - fb.cx), Math.atan2(-nB.y, -nB.x), 0.8);
      if (fb.t > 0.5) chain.push({ x: fb.cx - nB.x * rf, y: fb.cy - nB.y * rf });
      const segB = chain.slice(filletB);
      chain.push({ x: B.ix, y: B.iy });
      // Bordür başka bir yolun asfaltına girmesin (araya cadde giren uçlar)
      if (chain.some((q) => { const o = nearestRoad(q.x, q.y); return o && o.e < -0.3; })) continue;
      const hOf = (q) => { const o = nearestRoad(q.x, q.y); return o ? o.h : A.h; };
      const mx = (A.ox + B.ox) / 2, my = (A.oy + B.oy) / 2, hs = chain.map(hOf);
      const pts = [[A.ix, A.iy, A.ox, A.oy, A.h]];
      for (let q = 1; q < chain.length - 1; q++) pts.push([chain[q].x, chain[q].y, mx, my, hs[q]]);
      pts.push([B.ix, B.iy, B.ox, B.oy, B.h]);
      sidewalkRuns.push({ road: "ada", side: 0, pts: pts.map((v) => v.map(r3)) });
      islands.push({ h: hs.reduce((u, v) => u + v, 0) / hs.length, poly: chain.map((q) => [q.x, q.y]).concat([[B.ox, B.oy], [A.ox, A.oy]]) });
      // Köşe yuvarlağı ile keskin köşe (cadde kenarının göbek kenarına değdiği yer) arası asfalt
      for (const [f, seg] of [[fa, segA], [fb, segB]]) {
        if (seg.length >= 2) cornerFills.push({ c: [r3(f.ex), r3(f.ey), r3(hOf({ x: f.ex, y: f.ey }))], pts: seg.map((q) => [r3(q.x), r3(q.y), r3(hOf(q))]) });
      }
      A.used = B.used = true;
    }
  }
  const bez = (a, c, b, t) => { const u = 1 - t; return { x: u * u * a.x + 2 * u * t * c.x + t * t * b.x, y: u * u * a.y + 2 * u * t * c.y + t * t * b.y }; };
  for (const d of discs) {
    const near = ends.filter((e) => !e.used && Math.hypot(e.ix - d.x, e.iy - d.y) < d.r + SW + 12);
    if (near.length < 2) continue;
    near.sort((a, b) => Math.atan2(a.iy - d.y, a.ix - d.x) - Math.atan2(b.iy - d.y, b.ix - d.x));
    for (let k = 0; k < near.length; k++) {
      const A = near[k], B = near[(k + 1) % near.length];
      if (A === B || A.used || B.used || A.road === B.road) continue;
      const ci = meet(A.ix, A.iy, A.dx, A.dy, B.ix, B.iy, B.dx, B.dy);
      const co = meet(A.ox, A.oy, A.dx, A.dy, B.ox, B.oy, B.dx, B.dy);
      if (!ci || !co) continue;
      const ia = { x: A.ix, y: A.iy }, ib = { x: B.ix, y: B.iy }, oa = { x: A.ox, y: A.oy }, ob = { x: B.ox, y: B.oy };
      // Bordür eğrisi bir yolun asfaltından geçiyorsa bu iki uç karşı karşıya: birleşmez
      let crosses = false;
      for (const t of [0.15, 0.3, 0.5, 0.7, 0.85]) { const q = bez(ia, ci, ib, t), nr = nearestRoad(q.x, q.y); if (nr && nr.e < -0.15) crosses = true; }
      if (crosses) continue;
      const pts = [], curve = [];
      const M2 = 10;
      for (let q = 0; q <= M2; q++) {
        const t = q / M2, pi = bez(ia, ci, ib, t), po = bez(oa, co, ob, t), h = A.h + (B.h - A.h) * t;
        pts.push([r3(pi.x), r3(pi.y), r3(po.x), r3(po.y), r3(h)]);
        curve.push([r3(pi.x), r3(pi.y), r3(h)]);
      }
      sidewalkRuns.push({ road: "kose", side: 0, pts });
      cornerFills.push({ c: [r3(d.x), r3(d.y), r3(d.h)], pts: curve });
      A.used = B.used = true;
    }
  }
  leftoverCorners(ends);
}

// ---------------------------------------------------------------------------
// Çevre bariyeri (harita sınırı): çevre yolunun deniz tarafında; liman yolu ağzında açık
// ---------------------------------------------------------------------------
const ring = ROADS[0], port = ROADS.find((r) => r.id === "port");
const barrierRuns = [];
{
  let run = [];
  // Deniz tarafındaki kaldırımın dış kenarına oturur (taban 0,6 m, kenardan 0,05 m içeride):
  // yolun gerçek normali boyunca (merkezden dışa ölçek eğimli yerlerde kaldırıma gömülüyordu)
  const off = ring.width / 2 + SW - 0.35;
  for (let i = 0; i < ring.pts.length; i++) {
    const p = ring.pts[i], d = M.dirAt(ring.pts, i);
    let nx = -d.y, ny = d.x;
    if (M.inland(p.x + nx * 8, p.y + ny * 8) > M.inland(p.x - nx * 8, p.y - ny * 8)) { nx = -nx; ny = -ny; }
    const x = p.x + nx * off, y = p.y + ny * off;
    const gap = port && Math.hypot(x - port.pts[0].x, y - port.pts[0].y) < port.width / 2 + SW + 2;
    if (gap) { if (run.length >= 2) barrierRuns.push(run); run = []; continue; }
    run.push([r3(x), r3(y), r3(ring.prof.h[i] + CURB)]);
  }
  if (run.length >= 2) barrierRuns.push(run);
  // Kapalı halka: ilk ve son parça birleşsin
  if (barrierRuns.length > 1) {
    const f = barrierRuns[0], l = barrierRuns[barrierRuns.length - 1];
    if (Math.hypot(f[0][0] - l[l.length - 1][0], f[0][1] - l[l.length - 1][1]) < 8) { barrierRuns[0] = l.concat(f); barrierRuns.pop(); }
  }
}

// ---------------------------------------------------------------------------
// İskeleler ve liman rıhtımı
// ---------------------------------------------------------------------------
const ha = M.rad(S.harbor.angle), hr = M.coastR(ha), tx = -Math.sin(ha), ty = Math.cos(ha);
const piers = [];
for (let i = 0; i < S.harbor.piers; i++) {
  const off = (i - (S.harbor.piers - 1) / 2) * 34, L = S.harbor.pierLen + 12;
  const cx = Math.cos(ha) * (hr - 8 + L / 2) + tx * off, cy = Math.sin(ha) * (hr - 8 + L / 2) + ty * off;
  piers.push({ x: r3(cx), y: r3(cy), angle: r3(ha), length: r3(L), width: 8, h: 1.7 });
}

// ---------------------------------------------------------------------------
// Yükseklik ızgaraları (2 m): çarpışma (yollar tam yükseklikte) ve görüntü (yol altında
// 0,3 m aşağıda, şevler yumuşak); zemin türü
// ---------------------------------------------------------------------------
const STEP = 2, EXT = Math.ceil(S.size * 0.64 / STEP) * STEP, N = Math.round(2 * EXT / STEP) + 1;
const hCol = new Float32Array(N * N), hVis = new Float32Array(N * N), mat = new Uint8Array(N * N);
const P = S.plaza;
const smooth = (a, b, x) => { const t = Math.max(0, Math.min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
const MAT = { SEA: 0, SAND: 1, GRASS: 2, ROCK: 3, SOIL: 4, ROAD: 5 };
// Yaya adası: içindeyse uzaklık 0; dışındaysa kenarına uzaklık (yalnız 20 m'ye kadar)
function islandAt(x, y) {
  let best = null;
  for (const is of islands) {
    const P2 = is.poly;
    let inside = false, d = Infinity;
    for (let i = 0, j = P2.length - 1; i < P2.length; j = i++) {
      const [ax, ay] = P2[j], [bx, by] = P2[i];
      if ((ay > y) !== (by > y) && x < ax + (bx - ax) * (y - ay) / (by - ay)) inside = !inside;
      const dx = bx - ax, dy = by - ay, t = Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy || 1)));
      d = Math.min(d, Math.hypot(ax + dx * t - x, ay + dy * t - y));
    }
    if (inside) d = 0;
    if (d < 20 && (!best || d < best.d)) best = { d, h: is.h };
  }
  return best;
}
for (let j = 0; j < N; j++) {
  const y = -EXT + j * STEP;
  for (let i = 0; i < N; i++) {
    const x = -EXT + i * STEP, k = j * N + i;
    const t = M.height(x, y), land = M.inland(x, y);
    let hc = t, hv = t, m = land < 0 ? MAT.SEA : land < S.terrain.beach ? MAT.SAND : MAT.GRASS;
    const nr0 = nearestRoad(x, y);
    let nr = nr0 && { d: nr0.d, h: nr0.h, edge: nr0.half + SW + 0.6 };
    const isl = islandAt(x, y);
    if (isl && (!nr || isl.d - 0.6 < nr.d - nr.edge)) nr = { d: isl.d, h: isl.h, edge: 0.6 };
    if (nr) {
      const edge = nr.edge;
      // Şev: 1:1,2 eğimle, en fazla 14 m (kollar arasındaki yamaç teraslanmasın)
      const dh = Math.abs(nr.h - t), shoulder = Math.min(3 + dh * 1.2, 14);
      // Çarpışma zemini kaplamanın (yol, kavşak, köşe, kaldırım) altında kalsın, üstüne taşmasın
      if (nr.d <= edge) { hc = Math.min(nr.h, surfH(x, y)) - 0.03; hv = nr.h - 0.3; m = MAT.ROAD; }
      else if (nr.d < edge + shoulder + 2) {
        const w = smooth(edge, edge + shoulder, nr.d);
        hc = nr.h + (t - nr.h) * w;
        // Görüntü: düz bant 2 m daha geniş (yakın arazi 4 m ızgarayla çizilir; kaldırım kenarındaki
        // üçgen yamaçtan bir köşe alıp kaldırımın altına / üstüne eğilmesin)
        const wv = smooth(edge + 2, edge + shoulder + 2, nr.d);
        hv = (nr.h - 0.3) + (t - nr.h + 0.3) * wv;
        if (dh > 2 && land >= 0 && w < 0.85) m = MAT.SOIL;
      }
    }
    const dp = Math.hypot(x - P.x, y - P.y);
    if (dp < P.r + 0.5) { hc = M.plazaH; hv = M.plazaH - 0.3; m = MAT.ROAD; }
    hCol[k] = hc; hVis[k] = hv; mat[k] = m;
  }
}
// Dik yamaçlar kaya
for (let j = 1; j < N - 1; j++) for (let i = 1; i < N - 1; i++) {
  const k = j * N + i;
  if (mat[k] !== MAT.GRASS && mat[k] !== MAT.SAND) continue;
  const gx = (hCol[k + 1] - hCol[k - 1]) / (2 * STEP), gy = (hCol[k + N] - hCol[k - N]) / (2 * STEP);
  if (Math.hypot(gx, gy) > 0.62) mat[k] = MAT.ROCK;
}

// ---------------------------------------------------------------------------
// Trafik (şeritler, ışıklar, yaya geçitleri, tabelalar): tools/ada/trafik.js
// ---------------------------------------------------------------------------
const TR = require("./trafik.js")({ M, S, ROADS, JUNC, nearestRoad, SW, CURB, r3, sidewalkRuns, islandAt, piers });

// ---------------------------------------------------------------------------
// Yaya ağı: kaldırım ortası boyunca ~8 m'de bir düğüm, kavşaklarda karşıya geçitler
// ---------------------------------------------------------------------------
const nodes = [], edges = [];
const addNode = (x, y, h, run) => { nodes.push([r3(x), r3(y), r3(h + CURB), run]); return nodes.length - 1; };
sidewalkRuns.forEach((run, ri) => {
  let last = -1, acc = 0;
  for (let i = 0; i < run.pts.length; i++) {
    const [ix, iy, ox, oy, h] = run.pts[i], mx = (ix + ox) / 2, my = (iy + oy) / 2;
    if (i > 0) { const q = run.pts[i - 1]; acc += Math.hypot(mx - (q[0] + q[2]) / 2, my - (q[1] + q[3]) / 2); }
    if (i === 0 || i === run.pts.length - 1 || acc >= 8) {
      const id = addNode(mx, my, h, ri);
      if (last >= 0) edges.push([last, id]);
      last = id; acc = 0;
    }
  }
});
// Karşıya geçiş yalnız yaya geçitlerinden: geçidin iki ucuna birer düğüm; her uç kendi
// kaldırımındaki en yakın iki düğüme bağlanır (arada asfalt olmamalı). walkCross: [uç A, uç B, kavşak, kol]
const walkCross = [];
{
  const overRoad = (ax, ay, bx, by) => {
    for (const t of [0.25, 0.5, 0.75]) { const o = nearestRoad(ax + (bx - ax) * t, ay + (by - ay) * t); if (o && o.e < -0.2) return true; }
    return false;
  };
  for (const cw of TR.crosswalks) {
    const ids = [];
    for (const P of [cw.A, cw.B]) {
      const id = addNode(P.x, P.y, P.h, -2);
      const cands = nodes.map((nd, k) => ({ k, nd, L: Math.hypot(nd[0] - P.x, nd[1] - P.y) }))
        .filter((o) => o.k !== id && o.nd[3] >= 0 && o.L < 10 && !overRoad(P.x, P.y, o.nd[0], o.nd[1]))
        .sort((a, b) => a.L - b.L).slice(0, 2);
      for (const c of cands) edges.push([id, c.k]);
      ids.push(id);
    }
    edges.push([ids[0], ids[1]]);
    walkCross.push([ids[0], ids[1], cw.ji, cw.arm]);
  }
}
// Meydan plazası: merkez ve bir halka; iç kaldırıma bağlı
{
  const c = addNode(P.x, P.y, M.plazaH - CURB, -1), ringIds = [];
  for (let k = 0; k < 8; k++) { const a = M.TAU * k / 8; ringIds.push(addNode(P.x + Math.cos(a) * P.r * 0.6, P.y + Math.sin(a) * P.r * 0.6, M.plazaH - CURB, -1)); }
  ringIds.forEach((id, k) => { edges.push([c, id]); edges.push([id, ringIds[(k + 1) % 8]]); });
  for (const id of ringIds) {
    let best = null;
    nodes.forEach((nd, j) => { if (nd[3] < 0) return; const L = Math.hypot(nd[0] - nodes[id][0], nd[1] - nodes[id][1]); if (L < 16 && (!best || L < best.L)) best = { j, L }; });
    if (best) edges.push([id, best.j]);
  }
}

// ---------------------------------------------------------------------------
// Başlangıç: meydanda, en uzun caddeye bakarak
// ---------------------------------------------------------------------------
const avs = ROADS.filter((r) => r.kind === "avenue").sort((a, b) => b.prof.len - a.prof.len);
const av = avs[0], a0 = av.pts[0], a1 = av.pts[Math.min(6, av.pts.length - 1)];
const hd = Math.atan2(a1.y - a0.y, a1.x - a0.x);
const spawn = { x: r3(P.x + Math.cos(hd) * P.r * 0.4), y: r3(P.y + Math.sin(hd) * P.r * 0.4), h: r3(M.plazaH + 0.1), heading: r3(hd) };

// ---------------------------------------------------------------------------
fs.mkdirSync(OUT_DIR, { recursive: true });
for (const f of cornerFills) {
  f.c[2] = r3(surfH(f.c[0], f.c[1]));
  for (const q of f.pts) q[2] = r3(surfH(q[0], q[1]));
}
// Kavşak kaplaması: diskler (kutupsal ızgara) ve köşe dolguları (bölünmüş yelpaze) sık
// köşelerle yol yüzeyine oturur; üst üste binen parçalar arasında basamak kalmaz.
const paved = { v: [], t: [] };
{
  const V = (x, y) => { paved.v.push([r3(x), r3(y), r3(surfH(x, y))]); return paved.v.length - 1; };
  const RINGS = 4, SEG = 24;
  for (const d of discs) {
    if (d.plaza) continue;
    const c = V(d.x, d.y), ring = [];
    for (let k = 1; k <= RINGS; k++) {
      const row = [];
      for (let q = 0; q < SEG; q++) { const a = M.TAU * q / SEG, r = d.r * k / RINGS; row.push(V(d.x + Math.cos(a) * r, d.y + Math.sin(a) * r)); }
      ring.push(row);
    }
    for (let q = 0; q < SEG; q++) paved.t.push(c, ring[0][q], ring[0][(q + 1) % SEG]);
    for (let k = 0; k < RINGS - 1; k++) for (let q = 0; q < SEG; q++) {
      const a = ring[k][q], b = ring[k][(q + 1) % SEG], e = ring[k + 1][q], f = ring[k + 1][(q + 1) % SEG];
      paved.t.push(a, e, f, a, f, b);
    }
  }
  for (const f of cornerFills) {
    const [cx, cy] = f.c, STEPS = 4;
    const rows = f.pts.map(([x, y]) => { const r = []; for (let k = 1; k <= STEPS; k++) r.push(V(cx + (x - cx) * k / STEPS, cy + (y - cy) * k / STEPS)); return r; });
    const c = V(cx, cy);
    for (let i = 0; i < rows.length - 1; i++) {
      paved.t.push(c, rows[i][0], rows[i + 1][0]);
      for (let k = 0; k < STEPS - 1; k++) paved.t.push(rows[i][k], rows[i][k + 1], rows[i + 1][k + 1], rows[i][k], rows[i + 1][k + 1], rows[i + 1][k]);
    }
  }
}
// Yol boyası (yaya geçidi zebraları, dur çizgileri): her köşe yol yüzeyinde. Düz çizilince
// eğimli kavşakta boyanın bir kısmı asfaltın altında kalıp ara sıra kayboluyordu.
{
  const paint = [];
  const quad = (cx, cy, ax, ay, hl, hw) => {
    const sx = -ay, sy = ax;
    for (const [u, v] of [[-1, -1], [1, -1], [1, 1], [-1, 1]]) {
      const x = cx + ax * hl * u + sx * hw * v, y = cy + ay * hl * u + sy * hw * v;
      paint.push([r3(x), r3(y), r3(surfH(x, y) + 0.045)]);
    }
  };
  for (const cw of TR.street.crosswalks) {
    const [cx, cy] = cw.c, sx = -cw.ay, sy = cw.ax, half = cw.w / 2 - 0.35;
    for (let t = -half + 0.25; t <= half - 0.2; t += 1.0) quad(cx + sx * t, cy + sy * t, cw.ax, cw.ay, 1.5, 0.25);
  }
  for (const sl of TR.street.stopLines) {
    const dx = sl[3] - sl[0], dy = sl[4] - sl[1], L = Math.hypot(dx, dy) || 1;
    quad((sl[0] + sl[3]) / 2, (sl[1] + sl[4]) / 2, dx / L, dy / L, L / 2, 0.18);
  }
  TR.street.paint = paint;
}
const data = {
  version: 1, plan: S,
  grid: { ext: EXT, step: STEP, n: N, mats: Object.keys(MAT) },
  plaza: { x: P.x, y: P.y, r: P.r, h: r3(M.plazaH) },
  etekH: r3(M.ETEK_H), sidewalk: SW, curb: CURB,
  spawn, roads: roadsOut, sidewalks: sidewalkRuns, centerLines: centerRuns,
  discs: discs.map((d) => ({ x: r3(d.x), y: r3(d.y), h: r3(surfH(d.x, d.y)), r: r3(d.r), plaza: d.plaza,
    rim: Array.from({ length: 20 }, (_, k) => r3(surfH(d.x + Math.cos(M.TAU * k / 20) * d.r, d.y + Math.sin(M.TAU * k / 20) * d.r))) })),
  barrier: barrierRuns, piers, cornerFills, paved,
  walk: { nodes: nodes.map((n) => [n[0], n[1], n[2]]), edges, cross: walkCross },
  street: TR.street,
};
fs.writeFileSync(path.join(OUT_DIR, "ada.json"), JSON.stringify(data));
fs.writeFileSync(path.join(OUT_DIR, "trafik.json"), JSON.stringify(TR.trafik));
const bin = Buffer.alloc(N * N * 9);
for (let k = 0; k < N * N; k++) { bin.writeFloatLE(hCol[k], k * 4); bin.writeFloatLE(hVis[k], N * N * 4 + k * 4); bin.writeUInt8(mat[k], N * N * 8 + k); }
fs.writeFileSync(path.join(OUT_DIR, "ada_h.bin"), bin);
console.log(`ADA: ${ROADS.length} yol, ${sidewalkRuns.length} kaldırım parçası (${cornerFills.length} köşe dönüşü), ${centerRuns.length} orta çizgi, ${discs.length} kavşak diski,`,
  `${barrierRuns.length} bariyer parçası, ${piers.length} iskele, yaya ağı ${nodes.length} düğüm / ${edges.length} bağ, ızgara ${N}x${N}`);
