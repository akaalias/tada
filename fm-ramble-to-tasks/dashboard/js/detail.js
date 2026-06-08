// The expanded per-experiment detail: pipeline diagram + write-up + per-case
// gold-vs-on-device comparison with the judge's verdict and notes.

import { fetchResults, fetchPipe, fetchGold, programLine, fetchProvenance } from './api.js';
import { pipeSummary, renderPipeD3 } from './pipeline.js';
import { downloadPipePNG, downloadWriteupMD } from './export.js';
import { esc, pw, rmean, rubricChips, relabelSets, provenanceSteps } from './util.js';

// Split the judge's prose into individual sentences so each can be shown as its own
// item — flowing text is hard to scan. Break on .?! + space + a capital/number/quote,
// which leaves abbreviations (vs. / e.g. — followed by lowercase) intact.
const splitSentences = text => String(text)
  .split(/(?<=[.!?])\s+(?=[A-Z0-9("])/).map(t => t.trim()).filter(Boolean);

// Find references to candidate output questions in the judge's prose ("Q6",
// "questions 6 and 7", "question 7") and wrap each as a .qref chip carrying its
// number(s); also return the referenced numbers so the matching candidate
// questions can be flagged. Operates on (and returns) escaped HTML.
function markQRefs(text, maxN) {
  const refd = new Set();
  const tag = (full, nums) => {
    const valid = nums.filter(n => n >= 1 && n <= maxN);
    if (!valid.length) return full;
    valid.forEach(n => refd.add(n));
    return `<span class="qref" data-qn="${valid.join(' ')}">${full}</span>`;
  };
  let out = esc(text)
    .replace(/\bquestions?\s+\d+(?:\s*(?:,|and|&amp;|to|–|-)\s*\d+)*/gi,
      m => tag(m, (m.match(/\d+/g) || []).map(Number)))
    .replace(/\bQ(\d+)\b/gi, (m, n) => tag(m, [Number(n)]));
  return { html: out, refd };
}

export async function renderDetail(label, cell) {
  cell.innerHTML = '<div class="detail-inner">loading…</div>';
  const scores = await fetchResults(label);
  if (!scores) { cell.innerHTML = '<div class="detail-inner disc">no per-case results file for this experiment</div>'; return; }

  const tried = await programLine(label);
  const spec = await fetchPipe(label);
  const golds = await Promise.all(scores.map(s => fetchGold(s.id)));

  // Model used for each column. Gold + Judge are fixed Sonnet; the on-device
  // candidate model is derived from the pipeline spec (adapter knob, else base 3B).
  const GOLD_MODEL = 'claude-sonnet-4-6', JUDGE_MODEL = 'claude-sonnet-4-6';
  const adapterStage = (spec && spec.stages || []).find(s => s.knobs && s.knobs.model);
  const candModel = adapterStage ? 'Apple FM 3B + LoRA: ' + adapterStage.knobs.model : 'Apple FM (on-device 3B)';

  // Attach the adapter's training provenance (Sonnet corpus -> format -> fine-tune)
  // so the diagram can show what produced the LoRA node.
  if (spec && adapterStage) {
    const prov = await fetchProvenance();
    spec.adapterTraining = provenanceSteps(prov, adapterStage.knobs.model);
  }

  const blocks = scores.map((s, i) => {
    const gold = golds[i];
    const goldQs = gold ? (gold.tasks.length ? `<ol class="qs">${gold.tasks.map(t => `<li>${esc(t)}</li>`).join('')}</ol>` : '<div class="disc">(none)</div>') : '<div class="disc">gold unavailable</div>';
    const cand = s.candidate;
    const refused = !!s.error;
    const maxN = cand ? cand.tasks.length : 0;
    // Judge verdict: split into sentences, mark "Qn" references, and collect which
    // candidate questions the judge flags so the candidate column can highlight them.
    const refd = new Set();
    const judgeBody = s.verdict
      ? `<ul class="judge-pts">${splitSentences(relabelSets(s.verdict.notes)).map(t => {
          const m = markQRefs(t, maxN); m.refd.forEach(n => refd.add(n));
          return `<li>${m.html}</li>`;
        }).join('')}</ul>`
      : refused ? `<div class="judge-note">${esc(s.error)}</div>`
      : `<div class="judge-note disc">not judged</div>`;
    const fmQs = cand ? (cand.tasks.length ? `<ol class="qs">${cand.tasks.map((q, qi) =>
        `<li data-qn="${qi + 1}"${refd.has(qi + 1) ? ' class="q-flag"' : ''}>${esc(q)}</li>`).join('')}</ol>` : '<div class="disc">(none)</div>')
      : refused ? `<div class="disc">${esc(s.error)} — no output; excluded from quality</div>`
      : `<div class="disc">spec failed: ${(s.spec.violations || []).join('; ')}</div>`;
    // Status header. A zero-task case (empty gold) is NOT judged — there is nothing to
    // compare — so it is scored deterministically; show that, not a bogus "spec failed".
    const m = s.match;
    const f1 = m ? (m.goldEmpty ? (m.zeroTaskCorrect ? 1 : 0) : m.f1) : null;
    const f1s = f1 != null ? f1.toFixed(2) : '—';
    let head;
    if (refused) {
      head = '<span class="badge b-tie">REFUSED</span> <span class="disc">FM content moderation — excluded from quality</span>';
    } else if (s.spec && !s.spec.passed) {
      head = `<span class="badge b-loss">SPEC FAIL</span> <span class="disc">${esc((s.spec.violations || []).join('; '))}</span>`;
    } else if (s.verdict) {
      const [cls, txt] = pw(s.verdict.pairwise);
      head = `<span class="badge ${cls}">${txt}</span> <span class="rubric">F1 ${f1s} · rubric ${rmean(s.verdict.rubric)}</span> ${rubricChips(s.verdict.rubric)}`;
    } else if (m && m.goldEmpty) {
      const ok = m.zeroTaskCorrect;
      head = `<span class="badge ${ok ? 'b-win' : 'b-loss'}">${ok ? 'CORRECT · EMPTY' : 'INVENTED TASKS'}</span> <span class="rubric">F1 ${f1s}</span> <span class="disc">no actionable task expected — not judged</span>`;
    } else {
      head = `<span class="badge b-loss">EMPTY OUTPUT</span> <span class="rubric">F1 ${f1s}</span> <span class="disc">no tasks extracted — not judged</span>`;
    }
    return `<div class="case">
      <div class="case-head"><span class="case-meta">${head}</span></div>
      <div class="cmp">
        <div class="col col-input"><div class="col-head">Input</div><div class="col-model">user ramble</div><div class="case-task">“${esc(s.input)}”</div></div>
        <div class="col col-gold"><div class="col-head">Gold — Sonnet (Set A)</div><div class="col-model">${esc(GOLD_MODEL)}</div>${goldQs}</div>
        <div class="col col-fm"><div class="col-head">On-device — candidate (Set B)</div><div class="col-model">${esc(candModel)}</div>${fmQs}</div>
        <div class="col col-judge"><div class="col-head">Judge</div><div class="col-model">${esc(JUDGE_MODEL)}</div>${judgeBody}</div>
      </div></div>`;
  }).join('');

  // Right-hand explanation: human-readable hypothesis (bet) → method (how) → result (what happened).
  const explain = spec && (spec.hypothesis || spec.technique || spec.result) ? `<div class="explain">`
    + (spec.hypothesis ? `<div class="explain-block eb-hyp"><div class="explain-h">Hypothesis — the bet</div><p>${esc(spec.hypothesis)}</p></div>` : '')
    + (spec.technique ? `<div class="explain-block eb-tech"><div class="explain-h">Method — how we test it</div><p>${esc(spec.technique)}</p></div>` : '')
    + (spec.result ? `<div class="explain-block eb-res"><div class="explain-h">Result — what happened</div><p>${esc(spec.result)}</p></div>` : '')
    + `</div>` : '';
  const actions = `<div class="pipe-actions">${spec ? '<button class="png-btn">⬇ Summary (.png)</button>' : ''}${tried ? '<button class="wu-btn">⬇ Full Write-Up (.md)</button>' : ''}</div>`;
  cell.innerHTML = `<div class="detail-inner"><div class="pipe-head">${pipeSummary(spec)}${actions}</div>`
    + `<div class="pipe-grid"><div class="pipe-diagram"><div class="pipe-d3"></div></div>${explain}</div>`
    + `<div class="legend-kinds"><b>Node colour = who runs it:</b> <b style="color:#111111">FM</b> on-device model call · <b style="color:#6b6a60">Swift</b> deterministic code · <b style="color:#9b998c">User</b> input/output · ochre <b style="color:#8a6a1e">LoRA</b> node = adapter feeding a call · ochre dashed column above it = how the adapter was <b style="color:#6f5618">trained</b> (dev-time, top-down: Sonnet corpus → format → fine-tune). Vertical = parallel, horizontal = sequential · hover for details</div>`
    + `<div class="eval-head">Per-case evaluation<span class="eval-sub">gold (Sonnet) vs. on-device candidate, with the judge's verdict — across the held-out tasks</span></div>`
    + `${blocks}</div>`;
  cell.querySelector('.wu-btn')?.addEventListener('click', () => downloadWriteupMD(spec, tried, label));
  // cross-highlight: hovering a judge "Qn" reference lifts the matching candidate
  // question, and vice versa — scoped to each case so numbers don't collide.
  cell.querySelectorAll('.case').forEach(caseEl => {
    const hi = (nums, on) => nums.forEach(n => {
      caseEl.querySelector(`.col-fm li[data-qn="${n}"]`)?.classList.toggle('q-hi', on);
      caseEl.querySelectorAll('.qref').forEach(r => {
        if (r.dataset.qn.split(' ').includes(String(n))) r.classList.toggle('q-hi', on);
      });
    });
    caseEl.querySelectorAll('.qref').forEach(r => {
      const nums = r.dataset.qn.split(' ');
      r.addEventListener('mouseenter', () => hi(nums, true));
      r.addEventListener('mouseleave', () => hi(nums, false));
    });
    caseEl.querySelectorAll('.col-fm li.q-flag').forEach(li => {   // only judged-on questions react
      li.addEventListener('mouseenter', () => hi([li.dataset.qn], true));
      li.addEventListener('mouseleave', () => hi([li.dataset.qn], false));
    });
  });
  if (spec) {
    const d3el = cell.querySelector('.pipe-d3');
    const W = renderPipeD3(spec, d3el);
    // A wide diagram (big parallel fan) squeezed into the 2-column grid gets clipped
    // behind the explanation column — give it the full row and drop the explanation below.
    if (W > d3el.clientWidth) cell.querySelector('.pipe-grid')?.classList.add('pipe-grid--wide');
    cell.querySelector('.png-btn')?.addEventListener('click', () => downloadPipePNG(spec, label));
  }
}
