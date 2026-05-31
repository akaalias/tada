// Static, non-interactive snapshot of the experiment record for the onboarding page:
// a simplified SVG progress chart + a compact table. Reuses the dashboard's data
// fetch so it always reflects the latest runs. No hover/expand — read-only.
import { fetchRuns, fetchCosts, fetchTypes } from './api.js';

// Tufte palette: near-black data ink, receding gray for discarded, rust for invalid.
const GREEN = '#111111', GREY = '#b9b6a6', RED = '#8c2f1f', MUTED = '#6b6a60', LINE = '#ece9da';
// method type -> [short label, css class]; matches the live dashboard's Type column
const TYPE = {
  'Inference-Time': ['Inference', 't-inf'],
  'Supervised Fine-Tuning': ['SFT', 't-sft'],
  'Preference (ORPO)': ['ORPO', 't-orpo'],
};

function chartSVG(runs) {
  const W = 900, H = 300, pad = { l: 48, r: 16, t: 16, b: 38 };
  const valid = runs.filter(r => !r.invalid);
  if (!valid.length) return '';
  const qs = valid.map(r => r.quality);
  let lo = Math.max(0, Math.min(...qs) - 0.03), hi = Math.min(1, Math.max(...qs) + 0.03);
  const n = runs.length;
  const X = i => pad.l + (n <= 1 ? (W - pad.l - pad.r) / 2 : i * (W - pad.l - pad.r) / (n - 1));
  const Y = q => pad.t + (1 - (q - lo) / (hi - lo)) * (H - pad.t - pad.b);
  let s = '';
  // gridlines + y-axis labels
  for (let k = 0; k <= 4; k++) {
    const q = lo + (hi - lo) * k / 4, y = Y(q);
    s += `<line x1="${pad.l}" y1="${y}" x2="${W - pad.r}" y2="${y}" stroke="${LINE}" stroke-width="1"/>`;
    s += `<text x="${pad.l - 8}" y="${y + 4}" text-anchor="end" font-size="11" fill="${MUTED}">${q.toFixed(2)}</text>`;
  }
  s += `<text x="${W / 2}" y="${H - 6}" text-anchor="middle" font-size="11" fill="${MUTED}">experiments, in order &rarr;</text>`;
  // per-subset running-best staircase (invalid excluded), like the live chart
  const bestLine = (subset, color, dash) => {
    let best = -1; const pts = [];
    runs.forEach((r, i) => { if ((r.subset || 'full') !== subset || r.invalid) return; if (r.quality > best) best = r.quality; pts.push([i, best]); });
    if (!pts.length) return '';
    let d = '';
    pts.forEach(([i, b], k) => {
      const x = X(i), y = Y(b);
      d += k === 0 ? `M${x},${y}` : ` L${X(pts[k - 1][0])},${y} L${x},${y}`;
    });
    return `<path d="${d}" fill="none" stroke="${color}" stroke-width="${dash ? 1.5 : 2.5}"${dash ? ' stroke-dasharray="5 4"' : ''}/>`;
  };
  s += bestLine('dev', GREEN, false);
  s += bestLine('full', GREEN, false);
  // points
  runs.forEach((r, i) => {
    const x = X(i), y = Y(r.quality);
    if (r.invalid) {
      s += `<path d="M${x - 4},${y - 4} L${x + 4},${y + 4} M${x + 4},${y - 4} L${x - 4},${y + 4}" stroke="${RED}" stroke-width="2"/>`;
      return;
    }
    const col = r.kept ? GREEN : GREY;
    s += `<circle cx="${x}" cy="${y}" r="${r.kept ? 5 : 3.5}" fill="${col}" stroke="#fff" stroke-width="1.5"/>`;
  });
  return `<svg viewBox="0 0 ${W} ${H}" width="100%" style="font-family:-apple-system,system-ui,sans-serif">${s}</svg>`;
}

const esc = s => (s || '').replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));

function tableHTML(runs, costs, types) {
  const ordered = [...runs].reverse();                 // most recent at the top
  const rows = ordered.map(r => {
    const t = TYPE[types[r.label]];
    const ty = t ? `<span class="snap-ty ${t[1]}">${t[0]}</span>` : '<span class="snap-dash">—</span>';
    const c = costs[r.label];
    const cost = c != null ? `$${c.toFixed(2)}` : '<span class="snap-dash">—</span>';
    const status = r.invalid ? '<span class="snap-st st-inv">Invalid</span>'
      : r.kept ? '<span class="snap-st st-kept">Kept</span>'
      : '<span class="snap-st st-disc">Discarded</span>';
    const cls = r.kept && !r.invalid ? ' class="snap-keptrow"' : '';
    return `<tr${cls}>`
      + `<td>${r.index}</td><td>${r.label}</td><td>${ty}</td>`
      + `<td class="snap-q">${Math.round(r.quality * 100)}%</td><td>${status}</td>`
      + `<td class="snap-move"><span>${esc(r.note)}</span></td>`
      + `<td class="snap-cost">${cost}</td></tr>`;
  }).join('');
  const total = runs.reduce((a, r) => a + (costs[r.label] || 0), 0);
  const foot = `<tr class="snap-total"><td colspan="6">Total agent cost</td><td class="snap-cost">$${total.toFixed(2)}</td></tr>`;
  return `<table class="snap-tbl"><thead><tr><th>#</th><th>Label</th><th>Type</th><th>Quality</th><th>Status</th><th>Move (what was tried)</th><th>Cost</th></tr></thead><tbody>${rows}</tbody><tfoot>${foot}</tfoot></table>`;
}

async function render() {
  const chartEl = document.getElementById('snap-chart');
  const tableEl = document.getElementById('snap-table');
  if (!chartEl || !tableEl) return;
  const [runs, costs, types] = await Promise.all([fetchRuns(), fetchCosts(), fetchTypes()]);
  if (!runs.length) {
    chartEl.innerHTML = '<p class="muted" style="font-size:14px">Run the dashboard server to load the live record, or see the <a href="index.html">interactive dashboard</a>.</p>';
    return;
  }
  const kept = runs.filter(r => r.kept && !r.invalid).length;
  const best = Math.max(...runs.filter(r => !r.invalid).map(r => r.quality));
  chartEl.innerHTML = chartSVG(runs);
  document.getElementById('snap-count').textContent =
    `${runs.length} experiments logged · ${kept} set a new best · current best ${Math.round(best * 100)}%`;
  tableEl.innerHTML = tableHTML(runs, costs, types);
}

render();
