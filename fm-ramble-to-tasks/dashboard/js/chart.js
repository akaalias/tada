// The Karpathy-style progress chart (canvas): a running-best staircase with
// kept (green) and discarded (grey) points, plus a hover tooltip.
//
// Two metrics live on one timeline: the dev-10 proxy (early exploration) and the
// full-30 gate (the metric we decide on). They are not comparable point-for-point
// (dev over-reported — adapter_e1 read 0.405 on dev but 0.362 on full-30 greedy),
// so the running-best is computed PER subset (two independent staircases) rather
// than one cross-denominator line. Both render in solid green; which metric a point
// belongs to is shown in the table (Set column) and the hover tooltip.

// Tufte palette: near-black data ink for kept points + best line, receding warm
// gray for discarded, rust for invalid, warm hairline gridlines, cream "halo".
const GREEN = '#111111', GREY = '#b9b6a6', MUTED = '#6b6a60', LINE = '#ece9da';
const INVALID = '#8c2f1f', PAPER = '#fffff8', DIAG = '#6b4fa0';   // violet = reference analyses
const PIVOT = '#c8861a';   // amber ring = a patience-driven pivot (fresh direction after a no-improvement streak)
const FONT = '12px "Palatino","Palatino Linotype",Georgia,serif';
const SMALL = '10.5px "Palatino","Palatino Linotype",Georgia,serif';
let chartPoints = [];   // {x, y, r} (run) or {x, y, a} (analysis) in CSS px, for hover hit-testing

export function drawChart(runs, analyses = []) {
  const cv = document.getElementById('chart');
  const dpr = window.devicePixelRatio || 1;
  const W = cv.clientWidth, H = cv.clientHeight;
  cv.width = W * dpr; cv.height = H * dpr;
  const ctx = cv.getContext('2d'); ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, W, H);
  chartPoints = [];
  if (!runs.length) { ctx.fillStyle = MUTED; ctx.fillText('No runs yet — run: ./autoresearch/run.sh', 20, 40); return; }

  const pad = { l: 64, r: 40, t: 24, b: 48 };
  const qs = runs.map(r => r.quality);
  let lo = Math.min(...qs), hi = Math.max(...qs);
  const span = Math.max(0.05, hi - lo); lo = Math.max(0, lo - span * 0.25); hi = Math.min(1, hi + span * 0.35);
  hi = 1;   // always keep the 1.00 target (Sonnet parity) line in view
  const nn = runs.length;
  const X = i => pad.l + (nn === 1 ? (W - pad.l - pad.r) / 2 : i * (W - pad.l - pad.r) / (nn - 1));
  const Y = q => pad.t + (1 - (q - lo) / (hi - lo)) * (H - pad.t - pad.b);

  ctx.strokeStyle = LINE; ctx.fillStyle = MUTED; ctx.font = FONT; ctx.lineWidth = 1;
  for (let k = 0; k <= 5; k++) {
    const q = lo + (hi - lo) * k / 5, y = Y(q);
    ctx.beginPath(); ctx.moveTo(pad.l, y); ctx.lineTo(W - pad.r, y); ctx.stroke();
    ctx.fillText(q.toFixed(3), 16, y + 4);
  }
  // target reference: 1.00 = perfectly matches Sonnet's gold set on every case (the goal)
  { const yp = Y(1.0);
    ctx.save(); ctx.strokeStyle = INVALID; ctx.lineWidth = 1.5; ctx.setLineDash([5, 4]);
    ctx.beginPath(); ctx.moveTo(pad.l, yp); ctx.lineTo(W - pad.r, yp); ctx.stroke();
    ctx.setLineDash([]); ctx.fillStyle = INVALID; ctx.font = FONT;
    ctx.fillText('1.00 · Sonnet (target) — matches the gold set', pad.l + 6, yp + 14); ctx.restore(); }

  ctx.fillText('Experiment #', W / 2 - 30, H - 12);
  ctx.save(); ctx.translate(16, H / 2); ctx.rotate(-Math.PI / 2); ctx.fillText('Quality (higher is better)', -70, -44); ctx.restore();

  // running-best step line, computed independently PER subset (no cross-denominator line)
  const drawBest = (subset, color, width, dash) => {
    let best = -1; const pts = [];
    runs.forEach((r, i) => { if ((r.subset || 'full') !== subset) return; if (r.invalid) return; if (r.quality > best) best = r.quality; pts.push([i, best]); });
    if (!pts.length) return;
    ctx.strokeStyle = color; ctx.lineWidth = width; ctx.setLineDash(dash); ctx.beginPath();
    pts.forEach(([i, b], k) => {
      const x = X(i), y = Y(b);
      if (k === 0) ctx.moveTo(x, y);
      else { ctx.lineTo(x, Y(pts[k - 1][1])); ctx.lineTo(x, y); }   // step: horizontal then vertical
    });
    ctx.stroke(); ctx.setLineDash([]);
  };
  drawBest('dev', GREEN, 2.5, []);
  drawBest('full', GREEN, 2.5, []);

  // points (discarded = grey, kept = green, invalid = red ✕; labelled when kept/invalid)
  runs.forEach((r, i) => {
    const x = X(i), y = Y(r.quality);
    chartPoints.push({ x, y, r });
    if (r.invalid) {                          // invalid (e.g. gold leak): rust ✕, excluded from best-line
      ctx.strokeStyle = INVALID; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.moveTo(x - 5, y - 5); ctx.lineTo(x + 5, y + 5); ctx.moveTo(x + 5, y - 5); ctx.lineTo(x - 5, y + 5); ctx.stroke();
      ctx.fillStyle = INVALID; ctx.font = FONT; ctx.fillText(r.label + ' (invalid)', x + 9, y - 9);
      return;
    }
    const rad = r.kept ? 6 : 5;
    ctx.beginPath(); ctx.arc(x, y, rad, 0, 7);
    ctx.fillStyle = r.kept ? GREEN : GREY; ctx.fill();
    ctx.lineWidth = 2; ctx.strokeStyle = PAPER; ctx.stroke();
    if (r.pivot) {                            // pivot: an amber ring outside the paper stroke
      ctx.beginPath(); ctx.arc(x, y, rad + 3, 0, 7);
      ctx.lineWidth = 2; ctx.strokeStyle = PIVOT; ctx.stroke();
    }
    if (r.kept) { ctx.fillStyle = GREEN; ctx.font = FONT; ctx.fillText(r.label, x + 9, y - 9); }
  });

  // Reference analyses (probes/gates): no ruler score, so they sit on the BASELINE
  // (quality-0 floor) as violet diamonds at roughly the experiment index they followed.
  if (analyses.length) {
    const yBase = H - pad.b;                                  // the chart floor
    const groups = {};                                        // jitter dots that share an x
    analyses.forEach(a => { (groups[a.afterIndex] ??= []).push(a); });
    const LBL = '9px "Palatino","Palatino Linotype",Georgia,serif';
    Object.values(groups).forEach(g => g.forEach((a, k) => {
      const x = X(Math.max(0, Math.min(nn - 1, a.afterIndex))) + (k - (g.length - 1) / 2) * 13;
      const d = 3.2;
      ctx.save(); ctx.translate(x, yBase); ctx.rotate(Math.PI / 4);  // square rotated 45° = diamond
      ctx.fillStyle = DIAG; ctx.fillRect(-d, -d, 2 * d, 2 * d);
      ctx.lineWidth = 1; ctx.strokeStyle = PAPER; ctx.strokeRect(-d, -d, 2 * d, 2 * d);
      ctx.restore();
      ctx.fillStyle = DIAG; ctx.font = LBL; ctx.textAlign = 'center';
      ctx.fillText(a.id, x, yBase - 7); ctx.textAlign = 'left';
      chartPoints.push({ x, y: yBase, a });
    }));
    // legend sits just LEFT of the first diamond, right-aligned, leading into the cluster
    const firstX = X(Math.max(0, Math.min(nn - 1, Math.min(...analyses.map(a => a.afterIndex)))));
    ctx.fillStyle = DIAG; ctx.font = LBL; ctx.textAlign = 'right';
    ctx.fillText('reference analyses — no ruler score, at quality 0 by when they ran  ◆', firstX - 9, yBase - 3);
    ctx.textAlign = 'left';
  }
}

// Wire the hover tooltip once (any point, kept or discarded).
export function initChartHover() {
  const cv = document.getElementById('chart'), tip = document.getElementById('tip');
  cv.addEventListener('mousemove', e => {
    const rect = e.currentTarget.getBoundingClientRect();
    const mx = e.clientX - rect.left, my = e.clientY - rect.top;
    let hit = null, bd = 144;
    for (const p of chartPoints) { const d = (p.x - mx) ** 2 + (p.y - my) ** 2; if (d < bd) { bd = d; hit = p; } }
    if (hit && hit.a) {
      const a = hit.a;
      tip.innerHTML = `<b>${a.id} · ${a.title}</b> <span class="t-note">reference analysis · no ruler score</span>`
        + `<span class="t-note">${a.result}</span>`;
      tip.style.left = (e.clientX + 12) + 'px'; tip.style.top = (e.clientY + 12) + 'px'; tip.style.opacity = 1;
    } else if (hit) {
      const r = hit.r;
      tip.innerHTML = `<b>${r.label}</b> · ${r.quality.toFixed(3)} · ${r.invalid ? 'INVALID' : r.kept ? 'kept' : 'discarded'}${r.pivot ? ' · pivot' : ''}`
        + (r.invalid && r.invalidReason ? `<span class="t-note">⚠ ${r.invalidReason}</span>` : '')
        + (r.note ? `<span class="t-note">${r.note}</span>` : '');
      tip.style.left = (e.clientX + 12) + 'px'; tip.style.top = (e.clientY + 12) + 'px'; tip.style.opacity = 1;
    } else tip.style.opacity = 0;
  });
  cv.addEventListener('mouseleave', () => tip.style.opacity = 0);
}
