// Entry point: poll the run log every 3s, update the header + chart, and rebuild
// the table only when the data changed (so open detail panels survive refreshes).

import { fetchRuns, fetchCosts } from './api.js';
import { drawChart, initChartHover } from './chart.js';
import { fillTable } from './table.js';

const state = { lastSig: '', expanded: new Set(), costs: {} };

async function load() {
  const runs = await fetchRuns();
  document.getElementById('updated').textContent = 'updated ' + new Date().toLocaleTimeString();

  // The chart tracks the dev-proxy series so all points share a denominator.
  const subset = runs.some(r => (r.subset || 'full') === 'dev') ? 'dev' : 'full';
  const chartRuns = runs.filter(r => (r.subset || 'full') === subset);
  const kept = chartRuns.filter(r => r.kept).length;
  const n = chartRuns[0] ? chartRuns[0].n : '';
  document.getElementById('title').textContent =
    `Autoresearch Progress: ${chartRuns.length} Experiment${chartRuns.length === 1 ? '' : 's'}, ${kept} Kept (${subset}-${n} proxy)`;

  drawChart(chartRuns);

  state.costs = await fetchCosts();
  const sig = runs.map(r => r.label + ':' + r.quality + ':' + r.kept + ':' + (state.costs[r.label] ?? '')).join('|');
  if (sig !== state.lastSig) { state.lastSig = sig; fillTable(runs, state.expanded, state.costs); }
}

initChartHover();
load();
setInterval(load, 3000);
window.addEventListener('resize', load);
