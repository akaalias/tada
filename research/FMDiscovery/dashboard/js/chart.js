// The Karpathy-style progress chart (canvas): a running-best staircase with
// kept (green) and discarded (grey) points, plus a hover tooltip.
//
// Two metrics live on one timeline: the dev-10 proxy (early exploration) and the
// full-30 gate (the metric we decide on). They are not comparable point-for-point
// (dev over-reported — adapter_e1 read 0.405 on dev but 0.362 on full-30 greedy),
// so the running-best is computed PER subset (two independent staircases) rather
// than one cross-denominator line. Both render in solid green; which metric a point
// belongs to is shown in the table (Set column) and the hover tooltip.

const GREEN = '#16a34a', GREY = '#94a3b8', MUTED = '#94a3b8', LINE = '#e2e8f0';
let chartPoints = [];   // {x, y, r} in CSS px, for hit-testing on hover

export function drawChart(runs) {
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
  const nn = runs.length;
  const X = i => pad.l + (nn === 1 ? (W - pad.l - pad.r) / 2 : i * (W - pad.l - pad.r) / (nn - 1));
  const Y = q => pad.t + (1 - (q - lo) / (hi - lo)) * (H - pad.t - pad.b);

  ctx.strokeStyle = LINE; ctx.fillStyle = MUTED; ctx.font = '12px system-ui'; ctx.lineWidth = 1;
  for (let k = 0; k <= 5; k++) {
    const q = lo + (hi - lo) * k / 5, y = Y(q);
    ctx.beginPath(); ctx.moveTo(pad.l, y); ctx.lineTo(W - pad.r, y); ctx.stroke();
    ctx.fillText(q.toFixed(3), 16, y + 4);
  }
  ctx.fillText('Experiment #', W / 2 - 30, H - 12);
  ctx.save(); ctx.translate(16, H / 2); ctx.rotate(-Math.PI / 2); ctx.fillText('Quality (higher is better)', -70, -44); ctx.restore();

  // running-best step line, computed independently PER subset (no cross-denominator line)
  const drawBest = (subset, color, width, dash) => {
    let best = -1; const pts = [];
    runs.forEach((r, i) => { if ((r.subset || 'full') !== subset) return; if (r.quality > best) best = r.quality; pts.push([i, best]); });
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

  // points (discarded = grey, kept = green; labelled when kept)
  runs.forEach((r, i) => {
    const x = X(i), y = Y(r.quality);
    chartPoints.push({ x, y, r });
    ctx.beginPath(); ctx.arc(x, y, r.kept ? 6 : 5, 0, 7);
    ctx.fillStyle = r.kept ? GREEN : GREY; ctx.fill();
    ctx.lineWidth = 2; ctx.strokeStyle = '#fff'; ctx.stroke();
    if (r.kept) { ctx.fillStyle = GREEN; ctx.font = '12px system-ui'; ctx.fillText(r.label, x + 9, y - 9); }
  });
}

// Wire the hover tooltip once (any point, kept or discarded).
export function initChartHover() {
  const cv = document.getElementById('chart'), tip = document.getElementById('tip');
  cv.addEventListener('mousemove', e => {
    const rect = e.currentTarget.getBoundingClientRect();
    const mx = e.clientX - rect.left, my = e.clientY - rect.top;
    let hit = null, bd = 144;
    for (const p of chartPoints) { const d = (p.x - mx) ** 2 + (p.y - my) ** 2; if (d < bd) { bd = d; hit = p; } }
    if (hit) {
      const r = hit.r;
      tip.innerHTML = `<b>${r.label}</b> · ${r.quality.toFixed(3)} · ${r.kept ? 'kept' : 'discarded'}`
        + (r.note ? `<span class="t-note">${r.note}</span>` : '');
      tip.style.left = (e.clientX + 12) + 'px'; tip.style.top = (e.clientY + 12) + 'px'; tip.style.opacity = 1;
    } else tip.style.opacity = 0;
  });
  cv.addEventListener('mouseleave', () => tip.style.opacity = 0);
}
