// Entry point: poll the run log every 3s, update the header + chart, and rebuild
// the table only when the data changed (so open detail panels survive refreshes).

import { fetchRuns, fetchCosts, fetchOperators, fetchTypes } from './api.js';
import { drawChart, initChartHover } from './chart.js';
import { fillTable } from './table.js';

const state = { lastSig: '', expanded: new Set(), costs: {}, operators: {}, types: {} };

async function load() {
  const runs = await fetchRuns();
  document.getElementById('updated').textContent = 'updated ' + new Date().toLocaleTimeString();

  // The chart shows ALL runs; dev-10 (proxy) and full-30 (gate) get separate
  // best-lines inside drawChart so we never compare across denominators.
  const kept = runs.filter(r => r.kept).length;
  const hasDev = runs.some(r => (r.subset || 'full') === 'dev');
  const hasFull = runs.some(r => (r.subset || 'full') === 'full');
  const denom = hasDev && hasFull ? 'dev-10 proxy + full-30 gate' : hasDev ? 'dev-10 proxy' : 'full-30 gate';
  document.getElementById('title').textContent =
    `Autoresearch Progress: ${runs.length} Experiment${runs.length === 1 ? '' : 's'}, ${kept} Kept (${denom})`;

  drawChart(runs);

  state.costs = await fetchCosts();
  state.operators = await fetchOperators();
  state.types = await fetchTypes();
  const sig = runs.map(r => r.label + ':' + r.quality + ':' + r.kept + ':' + (state.costs[r.label] ?? '') + ':' + (state.operators[r.label] ?? '') + ':' + (state.types[r.label] ?? '')).join('|');
  if (sig !== state.lastSig) { state.lastSig = sig; fillTable(runs, state.expanded, state.costs, state.operators, state.types); }
}

initChartHover();
load();
setInterval(load, 3000);
window.addEventListener('resize', load);
