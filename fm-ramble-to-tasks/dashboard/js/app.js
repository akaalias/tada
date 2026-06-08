// Entry point: poll the run log every 3s, update the header + chart, and rebuild
// the table only when the data changed (so open detail panels survive refreshes).

import { fetchRuns, fetchCosts, fetchOperators, fetchTypes, fetchAnalyses } from './api.js';
import { drawChart, initChartHover } from './chart.js';
import { fillTable } from './table.js';

const state = { lastSig: '', expanded: new Set(), costs: {}, operators: {}, types: {}, analysesSig: '' };

// When opened from the report tapestry (index.html#<label>), open that row and jump to it.
const hashTarget = decodeURIComponent((location.hash || '').replace(/^#/, ''));
let hashDone = false;
function focusHashRow() {
  if (hashDone || !hashTarget) return;
  const row = document.getElementById('exp-' + hashTarget);
  if (!row) return;
  hashDone = true;
  row.classList.add('row-flash');
  setTimeout(() => row.classList.remove('row-flash'), 1800);
  // The detail panel loads async and grows the page, so a single scroll lands too
  // high. Align the row to the top, then re-correct after the detail settles.
  const jump = behavior => row.scrollIntoView({ behavior, block: 'start' });
  jump('auto');
  setTimeout(() => jump('smooth'), 450);
}

const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

function fillAnalyses(rows) {
  const tb = document.querySelector('#analyses-tbl tbody');
  if (!tb) return;
  tb.innerHTML = rows.map(a =>
    `<tr><td>${esc(a.id)}</td>`
    + `<td title="${esc(a.detail)}"><b>${esc(a.title)}</b><div class="an-scripts">${(a.scripts || []).map(esc).join(' · ')}</div></td>`
    + `<td class="an-q">${esc(a.question)}</td>`
    + `<td class="an-r">${esc(a.result)}</td>`
    + `<td><span class="ty-badge an-verdict">${esc(a.verdict)}</span></td></tr>`).join('');
}

async function load() {
  const runs = await fetchRuns();
  document.getElementById('updated').textContent = 'updated ' + new Date().toLocaleTimeString();

  // Pre-expand the row a deep link points at, so it renders open on first paint.
  if (hashTarget && !hashDone && runs.some(r => r.label === hashTarget)) state.expanded.add(hashTarget);

  // The chart shows ALL runs; dev-10 (proxy) and full-30 (gate) get separate
  // best-lines inside drawChart so we never compare across denominators.
  const kept = runs.filter(r => r.kept).length;
  const hasDev = runs.some(r => (r.subset || 'full') === 'dev');
  const hasFull = runs.some(r => (r.subset || 'full') === 'full');
  const denom = hasDev && hasFull ? 'dev + full' : hasDev ? 'dev gate' : 'full set';
  document.getElementById('title').textContent =
    `Autoresearch Progress: ${runs.length} Experiment${runs.length === 1 ? '' : 's'}, ${kept} Kept (${denom})`;

  const analyses = await fetchAnalyses();
  drawChart(runs, analyses);

  state.costs = await fetchCosts();
  state.operators = await fetchOperators();
  state.types = await fetchTypes();
  const sig = runs.map(r => r.label + ':' + r.quality + ':' + r.kept + ':' + (state.costs[r.label] ?? '') + ':' + (state.operators[r.label] ?? '') + ':' + (state.types[r.label] ?? '')).join('|');
  if (sig !== state.lastSig) { state.lastSig = sig; fillTable(runs, state.expanded, state.costs, state.operators, state.types); }
  focusHashRow();

  const asig = analyses.map(a => a.id + ':' + a.result).join('|');
  if (asig !== state.analysesSig) { state.analysesSig = asig; fillAnalyses(analyses); }
}

initChartHover();
load();
setInterval(load, 3000);
window.addEventListener('resize', load);
