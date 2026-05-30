// The expanded per-experiment detail: pipeline diagram + write-up + per-case
// gold-vs-on-device comparison with the judge's verdict and notes.

import { fetchResults, fetchPipe, fetchGold, programLine } from './api.js';
import { pipeSummary, renderPipeD3 } from './pipeline.js';
import { esc, pw, rmean, rubricChips, relabelSets } from './util.js';

export async function renderDetail(label, cell) {
  cell.innerHTML = '<div class="detail-inner">loading…</div>';
  const scores = await fetchResults(label);
  if (!scores) { cell.innerHTML = '<div class="detail-inner disc">no per-case results file for this experiment</div>'; return; }

  const tried = await programLine(label);
  const spec = await fetchPipe(label);
  const golds = await Promise.all(scores.map(s => fetchGold(s.id)));

  const blocks = scores.map((s, i) => {
    const gold = golds[i];
    const goldQs = gold ? `<ol class="qs">${gold.questions.map(q => `<li>${esc(q.title)}</li>`).join('')}</ol>` : '<div class="disc">gold unavailable</div>';
    const cand = s.candidate;
    const refused = !!s.error;
    const fmQs = cand ? `<ol class="qs">${cand.questions.map(q => `<li>${esc(q.title)}</li>`).join('')}</ol>`
      : refused ? `<div class="disc">${esc(s.error)} — no output; excluded from quality</div>`
      : `<div class="disc">spec failed: ${(s.spec.violations || []).join('; ')}</div>`;
    let head = refused
      ? '<span class="badge b-tie">REFUSED</span> <span class="disc">FM content moderation — excluded from quality</span>'
      : '<span class="disc">not judged (spec failed)</span>';
    if (s.verdict) {
      const [cls, txt] = pw(s.verdict.pairwise);
      head = `<span class="badge ${cls}">${txt}</span> <span class="rubric">rubric ${rmean(s.verdict.rubric)}</span> ${rubricChips(s.verdict.rubric)}`;
    }
    const judgeText = s.verdict ? esc(relabelSets(s.verdict.notes))
      : refused ? esc(s.error) : '<span class="disc">not judged</span>';
    return `<div class="case">
      <div class="case-head"><span class="case-task">${esc(s.input)}</span> ${head}</div>
      <div class="cmp">
        <div class="col col-gold"><div class="col-head">Gold — Sonnet (Set A)</div>${goldQs}</div>
        <div class="col col-fm"><div class="col-head">On-device — candidate (Set B)</div>${fmQs}</div>
        <div class="col col-judge"><div class="col-head">Judge</div><div class="judge-note">${judgeText}</div></div>
      </div></div>`;
  }).join('');

  const triedHtml = tried ? `<details class="trywrap"><summary>Full write-up</summary><div class="tried">${esc(tried)}</div></details>` : '';
  cell.innerHTML = `<div class="detail-inner">${pipeSummary(spec)}<div class="pipe-d3"></div>`
    + `<div class="legend-kinds"><b>Node colour = who runs it:</b> <b style="color:#db2777">FM</b> on-device model call · <b style="color:#ea580c">Swift</b> deterministic code · <b style="color:#64748b">User</b> input · gold <b style="color:#ca8a04">LoRA</b> node = adapter feeding a call. Vertical = parallel, horizontal = sequential · hover for details</div>`
    + `${triedHtml}${blocks}</div>`;
  if (spec) renderPipeD3(spec, cell.querySelector('.pipe-d3'));
}
