// §2 "The answer": the winning experiment's (exp056) detail card, reused verbatim
// from the dashboard — same markup, same renderer, same background — just without
// the per-case evaluation list (that's covered separately in §4's worked example).
import { fetchPipe, fetchProvenance, programLine } from './api.js';
import { renderPipeD3, pipeSummary } from './pipeline.js';
import { provenanceSteps, esc } from './util.js';
import { downloadPipePNG, downloadWriteupMD } from './export.js';

const CHAMPION = 'exp056';

async function render() {
  const cell = document.getElementById('answer-card');
  if (!cell) return;
  const spec = await fetchPipe(CHAMPION);
  if (!spec) { cell.innerHTML = '<p class="muted" style="font-size:14px">Run the dashboard server to load the diagram.</p>'; return; }

  const adapterStage = (spec.stages || []).find(s => s.knobs && s.knobs.model);
  if (adapterStage) {
    const prov = await fetchProvenance();
    spec.adapterTraining = provenanceSteps(prov, adapterStage.knobs.model);
  }
  const tried = await programLine(CHAMPION);

  const explain = (spec.hypothesis || spec.technique || spec.result) ? `<div class="explain">`
    + (spec.hypothesis ? `<div class="explain-block eb-hyp"><div class="explain-h">Hypothesis — the bet</div><p>${esc(spec.hypothesis)}</p></div>` : '')
    + (spec.technique ? `<div class="explain-block eb-tech"><div class="explain-h">Method — how we test it</div><p>${esc(spec.technique)}</p></div>` : '')
    + (spec.result ? `<div class="explain-block eb-res"><div class="explain-h">Result — what happened</div><p>${esc(spec.result)}</p></div>` : '')
    + `</div>` : '';
  const actions = `<div class="pipe-actions"><button class="png-btn">⬇ Summary (.png)</button>${tried ? '<button class="wu-btn">⬇ Full Write-Up (.md)</button>' : ''}</div>`;

  cell.innerHTML = `<div class="pipe-head">${pipeSummary(spec)}${actions}</div>`
    + `<div class="pipe-grid"><div class="pipe-diagram"><div class="pipe-d3"></div></div>${explain}</div>`
    + `<div class="legend-kinds"><b>Node colour = who runs it:</b> <b style="color:#111111">FM</b> on-device model call · <b style="color:#6b6a60">Swift</b> deterministic code · <b style="color:#9b998c">User</b> input/output · ochre <b style="color:#8a6a1e">LoRA</b> node = adapter feeding a call · ochre dashed column above it = how the adapter was <b style="color:#6f5618">trained</b> (dev-time, top-down: Sonnet corpus → format → fine-tune). Vertical = parallel, horizontal = sequential · hover for details</div>`;

  cell.querySelector('.wu-btn')?.addEventListener('click', () => downloadWriteupMD(spec, tried, CHAMPION));
  const d3el = cell.querySelector('.pipe-d3');
  const W = renderPipeD3(spec, d3el);
  if (W > d3el.clientWidth) cell.querySelector('.pipe-grid')?.classList.add('pipe-grid--wide');
  cell.querySelector('.png-btn')?.addEventListener('click', () => downloadPipePNG(spec, CHAMPION));
}

render();
