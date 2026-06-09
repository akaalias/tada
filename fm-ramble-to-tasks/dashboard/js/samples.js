// The sample index: every eval ramble + its frozen Sonnet gold task list,
// grouped by category. Data: results/samples.json (built by gen_samples.py).
import { esc } from './util.js';

const bust = () => '?t=' + Date.now();

async function load() {
  try { return await (await fetch('../results/samples.json' + bust())).json(); }
  catch (e) { return { total: 0, categories: [] }; }
}

function tasksBlock(tasks) {
  if (!tasks || !tasks.length)
    return '<div class="s-empty">No tasks — correctly empty.</div>';
  return `<ol>${tasks.map(t => `<li>${esc(t)}</li>`).join('')}</ol>`;
}

function renderItem(it) {
  return `
    <div class="s-flow">
      <div class="s-in"><div class="s-quote">“${esc(it.input)}”</div></div>
      <div class="s-arrow">&rarr;</div>
      <div class="s-out">${tasksBlock(it.tasks)}</div>
    </div>`;
}

function renderCategory(c) {
  return `
    <section class="s-cat" id="cat-${c.kind}">
      <h2 class="s-cat-h">${esc(c.label)} <span class="s-count">${c.items.length}</span></h2>
      ${c.desc ? `<p class="sub">${esc(c.desc)}</p>` : ''}
      <div class="s-flow s-flow-head">
        <div class="s-in s-tag">User input</div>
        <div class="s-arrow"></div>
        <div class="s-out s-tag">Gold tasks · Sonnet</div>
      </div>
      ${c.items.map(renderItem).join('')}
    </section>`;
}

(async () => {
  const data = await load();
  document.getElementById('title').textContent =
    `${data.total} samples across ${data.categories.length} categories`;
  const nav = data.categories.map(c =>
    `<a href="#cat-${c.kind}">${esc(c.label)} (${c.items.length})</a>`).join('');
  document.getElementById('catnav').innerHTML = nav;
  document.getElementById('samples').innerHTML =
    data.categories.map(renderCategory).join('') ||
    '<p class="sub">No samples found. Run <code>python3 autoresearch/gen_samples.py</code>.</p>';
})();
