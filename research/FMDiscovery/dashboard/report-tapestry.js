// Small-multiples "tapestry" for the final report: every experiment's process
// diagram rendered in miniature, in chronological order, tinted by lever type.
// Reuses the dashboard's own SVG builder so the thumbnails match the live diagrams.
import { fetchRuns, fetchTypes, fetchProvenance } from './js/api.js';
import { buildExportSVG } from './js/export.js';
import { provenanceSteps } from './js/util.js';

const TY = {
  'Inference-Time': 'ty-infer',
  'Supervised Fine-Tuning': 'ty-sft',
  'Preference (ORPO)': 'ty-orpo',
};

const pipeCache = {};
async function pipe(label) {
  if (pipeCache[label] !== undefined) return pipeCache[label];
  try {
    const r = await fetch(`../results/pipelines/${label}.json?t=` + Date.now());
    pipeCache[label] = r.ok ? await r.json() : null;
  } catch (e) { pipeCache[label] = null; }
  return pipeCache[label];
}

async function render() {
  const el = document.getElementById('tapestry');
  if (!el) return;
  const [runs, types, prov] = await Promise.all([fetchRuns(), fetchTypes(), fetchProvenance()]);
  if (!runs.length) { el.innerHTML = '<p class="muted" style="font-size:14px">Run the dashboard server to load the diagrams.</p>'; return; }

  const cells = await Promise.all(runs.map(async r => {
    const spec = await pipe(r.label);
    let svg = '';
    if (spec) {
      const adapterStage = (spec.stages || []).find(s => s.knobs && s.knobs.model);
      if (adapterStage) spec.adapterTraining = provenanceSteps(prov, adapterStage.knobs.model);
      // strip the fixed width/height so viewBox + preserveAspectRatio contains it in the cell
      try { svg = buildExportSVG(spec).svg.replace(/ width="[0-9]+" height="[0-9]+"/, ''); } catch (e) { svg = ''; }
    }
    const cls = TY[types[r.label]] || '';
    return `<figure class="tw-cell ${cls}" title="${r.label} — quality ${(r.quality).toFixed(3)}, coverage ${r.coverage}">
      <div class="tw-dia">${svg || '<span class="tw-none">—</span>'}</div>
      <figcaption><span class="tw-lab">${r.label}</span><span class="tw-q">${Math.round(r.quality * 100)}%</span></figcaption>
    </figure>`;
  }));
  el.innerHTML = cells.join('');
}

render();
