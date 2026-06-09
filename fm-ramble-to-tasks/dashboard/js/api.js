// All data fetching. Caches successful results; never caches a miss, so a fetch
// that lands mid-write self-heals on the next refresh.

const bust = () => '?t=' + Date.now();

export async function fetchRuns() {
  try {
    const t = await (await fetch('../results/programs.jsonl' + bust())).text();
    return t.trim().split('\n').filter(Boolean).map(JSON.parse);
  } catch (e) { return []; }
}

export async function fetchCosts() {
  try { return await (await fetch('../results/costs.json' + bust())).json(); }
  catch (e) { return {}; }
}

export async function fetchOperators() {
  try { return await (await fetch('../results/operators.json' + bust())).json(); }
  catch (e) { return {}; }
}

export async function fetchTypes() {
  try { return await (await fetch('../results/types.json' + bust())).json(); }
  catch (e) { return {}; }
}

// Two-parent lineage per program: { label: { parents: [...], pivot } }.
// Written by record_lineage.py each loop sample.
export async function fetchLineageMeta() {
  try { return await (await fetch('../results/lineage_meta.json' + bust())).json(); }
  catch (e) { return {}; }
}

// Wall-clock per program (the coder sample: code + build + eval), in ms,
// keyed by label. Written by run.sh from the coder's duration_ms.
export async function fetchDurations() {
  try { return await (await fetch('../results/durations.json' + bust())).json(); }
  catch (e) { return {}; }
}

export async function fetchAnalyses() {
  try { return (await (await fetch('../results/analyses.json' + bust())).json()).analyses || []; }
  catch (e) { return []; }
}

let provCache = null;
export async function fetchProvenance() {
  if (provCache) return provCache;
  try { provCache = await (await fetch('../results/adapter_provenance.json' + bust())).json(); return provCache; }
  catch (e) { return {}; }
}

const pipeCache = {};
export async function fetchPipe(label) {
  if (pipeCache[label] !== undefined) return pipeCache[label];
  try {
    const r = await fetch(`../results/pipelines/${label}.json` + bust());
    if (!r.ok) return null;                 // don't cache a miss
    const j = await r.json();
    // Defensive: the generator can occasionally store `stages` as a JSON string; normalize.
    if (j && typeof j.stages === 'string') { try { j.stages = JSON.parse(j.stages); } catch (e) { j.stages = []; } }
    if (j && !Array.isArray(j.stages)) j.stages = [];
    pipeCache[label] = j;
    return j;
  } catch (e) { return null; }
}

const goldCache = {};
export async function fetchGold(id) {
  if (goldCache[id] !== undefined) return goldCache[id];
  try {
    const r = await fetch(`../gold/${id}.json` + bust());
    if (!r.ok) return null;
    goldCache[id] = (await r.json()).gold;
    return goldCache[id];
  } catch (e) { return null; }
}

const resultsCache = {};
export async function fetchResults(label) {
  if (resultsCache[label]) return resultsCache[label];
  try {
    const j = await (await fetch(`../results/${label}.json` + bust())).json();
    resultsCache[label] = j;
    return j;
  } catch (e) { return null; }
}

let programText = null;
export async function programLine(label) {
  if (programText === null) {
    try { programText = await (await fetch('../program.md' + bust())).text(); }
    catch (e) { programText = ''; }
  }
  const e = label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const m = programText.match(new RegExp('^\\s*-\\s.*\\b' + e + '\\b.*$', 'mi'));
  return m ? m[0].replace(/^\s*-\s*/, '').replace(/\*\*/g, '') : '';
}
