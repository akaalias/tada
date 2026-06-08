// Glossary tooltips. Scans the page prose, wraps the FIRST occurrence of each
// known term in a <span class="gloss">, and shows a popover (def + example) on
// hover / focus / tap. The source HTML is never edited — wrapping happens at
// runtime, so the authored copy stays exactly as written.

import { GLOSSARY, GROUP_STARTS } from './glossary-data.js';

// Roots to scan, and ancestors to never touch (headings, links, code, pills,
// nav, the data tables/chart). Keeps the markup we wrap to plain body prose.
const ROOT_SEL = document.body.dataset.glossaryRoot || '.wrap';
const SKIP_SEL = 'h1,h2,h3,h4,a,code,button,svg,canvas,table,.pill,.nav,.eyebrow,.num,.gloss,.dash-legend,.snap-legend,.tap-legend,script,style';

// Build one ordered alias list (longest first, so "over-generate-and-prune"
// wins over "prune", "LoRA adapter" over "adapter", etc.).
const aliases = [];
for (const e of GLOSSARY) for (const m of e.match) aliases.push({ m, id: e.id });
aliases.sort((a, b) => b.m.length - a.m.length);

const byId = new Map(GLOSSARY.map(e => [e.id, e]));
const aliasToId = new Map();          // lowercased alias -> id (first listed wins)
for (const { m, id } of aliases) { const k = m.toLowerCase(); if (!aliasToId.has(k)) aliasToId.set(k, id); }

// Prose triggers (.gloss) get a dotted underline; pill chips (.gloss-pill)
// keep their own colored chip styling. Both fire the same popover.
const TRIGGER = '.gloss, .gloss-pill';

const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
// Token-aware boundaries: treat letters/digits/hyphen/curly-or-straight
// apostrophe as "word" chars, so we match whole terms and not fragments.
const B = "[A-Za-z0-9\\-’']";
// Capture the headword in group 1, then allow an optional plural suffix so
// "Foundation Models" / "adapters" / "pipelines" match their singular alias.
const RE = new RegExp(`(?<!${B})(${aliases.map(a => esc(a.m)).join('|')})(?:es|s)?(?!${B})`, 'gi');

const used = new Set();

function skip(node) {
  return node.parentElement && node.parentElement.closest(SKIP_SEL);
}

function wrapTextNode(node) {
  const text = node.nodeValue;
  RE.lastIndex = 0;
  let m, frag = null, last = 0;
  while ((m = RE.exec(text))) {
    const id = aliasToId.get(m[1].toLowerCase());  // m[1] = headword without plural
    if (!id || used.has(id)) continue;        // unknown, or already linked once
    used.add(id);
    frag = frag || document.createDocumentFragment();
    if (m.index > last) frag.appendChild(document.createTextNode(text.slice(last, m.index)));
    const span = document.createElement('span');
    span.className = 'gloss';
    span.tabIndex = 0;
    span.dataset.id = id;
    span.setAttribute('role', 'button');
    span.setAttribute('aria-label', `${byId.get(id).title} — glossary term`);
    span.textContent = m[0];
    frag.appendChild(span);
    last = m.index + m[0].length;
  }
  if (frag) {
    if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
    node.parentNode.replaceChild(frag, node);
  }
}

// Pill chips (INFERENCE, SFT, ORPO, GRPO, GAD, LoRA…) are reference labels, so
// EVERY matching pill becomes a trigger — not just the first — unlike prose.
function wirePills(root) {
  root.querySelectorAll('.pill').forEach(p => {
    if (p.classList.contains('gloss-pill')) return;
    const id = aliasToId.get(p.textContent.trim().toLowerCase());
    if (!id) return;                       // e.g. operator pills ("Interactive")
    p.classList.add('gloss-pill');
    p.tabIndex = 0;
    p.dataset.id = id;
    p.setAttribute('role', 'button');
    p.setAttribute('aria-label', `${byId.get(id).title} — glossary term`);
  });
}

function scan(root) {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode: n => (n.nodeValue.trim() && !skip(n)) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT,
  });
  const nodes = [];
  for (let n = walker.nextNode(); n; n = walker.nextNode()) nodes.push(n);
  nodes.forEach(wrapTextNode);   // collected first; mutating during walk is unsafe
}

// ---- popover ----------------------------------------------------------------
let pop, current = null;

function buildPop() {
  pop = document.createElement('div');
  pop.className = 'gloss-pop';
  pop.id = 'gloss-pop';
  pop.setAttribute('role', 'tooltip');
  pop.hidden = true;
  document.body.appendChild(pop);
  // Keep open while the pointer is over the popover itself.
  pop.addEventListener('mouseenter', () => clearTimeout(pop._t));
  pop.addEventListener('mouseleave', hide);
}

function show(span) {
  const e = byId.get(span.dataset.id);
  if (!e) return;
  current = span;
  pop.innerHTML =
    `<div class="gloss-title">${e.title}</div>` +
    `<div class="gloss-def">${e.def}</div>` +
    `<div class="gloss-ex"><span class="gloss-ex-tag">Example</span>${e.ex}</div>`;
  pop.hidden = false;
  position(span);
}

function position(span) {
  const r = span.getBoundingClientRect();
  const pr = pop.getBoundingClientRect();
  const margin = 10, gap = 8;
  // Horizontal: align to the term, clamp into the viewport.
  let left = r.left + window.scrollX;
  left = Math.min(left, window.scrollX + document.documentElement.clientWidth - pr.width - margin);
  left = Math.max(left, window.scrollX + margin);
  // Vertical: below by default, flip above if it would overflow the bottom.
  let top = r.bottom + window.scrollY + gap;
  const below = r.bottom + gap + pr.height;
  if (below > document.documentElement.clientHeight && r.top - gap - pr.height > 0) {
    top = r.top + window.scrollY - pr.height - gap;
    pop.dataset.placement = 'above';
  } else {
    pop.dataset.placement = 'below';
  }
  pop.style.left = `${left}px`;
  pop.style.top = `${top}px`;
}

function hide() {
  pop.hidden = true;
  current = null;
}

// ---- sidebar drawer ---------------------------------------------------------
// A persistent bottom-right "Glossary" button opens a right-hand drawer holding
// the whole glossary, grouped by section, with a live search box at the top.
function buildSidebar() {
  const fab = document.createElement('button');
  fab.type = 'button';
  fab.className = 'gloss-fab';
  fab.textContent = 'Glossary';
  fab.setAttribute('aria-haspopup', 'dialog');
  fab.setAttribute('aria-expanded', 'false');

  const backdrop = document.createElement('div');
  backdrop.className = 'gloss-backdrop';
  backdrop.hidden = true;

  const drawer = document.createElement('aside');
  drawer.className = 'gloss-drawer';
  drawer.hidden = true;
  drawer.setAttribute('role', 'dialog');
  drawer.setAttribute('aria-modal', 'false');
  drawer.setAttribute('aria-label', 'Glossary');
  drawer.innerHTML =
    `<div class="gloss-drawer-head">
       <div class="gloss-drawer-bar">
         <span class="gloss-drawer-title">Glossary</span>
         <button class="gloss-drawer-close" type="button" aria-label="Close glossary">&times;</button>
       </div>
       <input class="gloss-search" type="search" autocomplete="off"
              placeholder="Search ${GLOSSARY.length} terms…" aria-label="Search glossary">
       <div class="gloss-empty" hidden>No terms match.</div>
     </div>
     <div class="gloss-drawer-body"></div>`;

  const body = drawer.querySelector('.gloss-drawer-body');
  const items = [];
  let group = null;
  for (const e of GLOSSARY) {
    if (GROUP_STARTS[e.id]) {
      group = document.createElement('div');
      group.className = 'gloss-group';
      group.textContent = GROUP_STARTS[e.id];
      body.appendChild(group);
    }
    const it = document.createElement('div');
    it.className = 'gloss-item';
    it.innerHTML =
      `<div class="gloss-title">${e.title}</div>` +
      `<div class="gloss-def">${e.def}</div>` +
      `<div class="gloss-ex"><span class="gloss-ex-tag">Example</span>${e.ex}</div>`;
    it._hay = `${e.title} ${e.def} ${e.ex} ${e.match.join(' ')}`.toLowerCase();
    it._group = group;
    body.appendChild(it);
    items.push(it);
  }

  document.body.append(fab, backdrop, drawer);

  const search = drawer.querySelector('.gloss-search');
  const empty = drawer.querySelector('.gloss-empty');
  const groups = [...body.querySelectorAll('.gloss-group')];

  const open = () => {
    drawer.hidden = backdrop.hidden = false;
    fab.setAttribute('aria-expanded', 'true');
    requestAnimationFrame(() => { drawer.classList.add('open'); backdrop.classList.add('open'); });
    search.focus();
  };
  const close = () => {
    drawer.classList.remove('open');
    backdrop.classList.remove('open');
    fab.setAttribute('aria-expanded', 'false');
    setTimeout(() => { drawer.hidden = backdrop.hidden = true; }, 240);
    fab.focus();
  };

  fab.addEventListener('click', open);
  drawer.querySelector('.gloss-drawer-close').addEventListener('click', close);
  backdrop.addEventListener('click', close);
  document.addEventListener('keydown', e => { if (e.key === 'Escape' && !drawer.hidden) close(); });

  search.addEventListener('input', () => {
    const q = search.value.trim().toLowerCase();
    const seen = new Set();
    let any = false;
    for (const it of items) {
      const show = !q || it._hay.includes(q);
      it.hidden = !show;
      if (show) { any = true; if (it._group) seen.add(it._group); }
    }
    groups.forEach(g => { g.hidden = q ? !seen.has(g) : false; });
    empty.hidden = any;
    body.hidden = !any;
  });
}

function init() {
  if (!aliases.length) return;
  document.querySelectorAll(ROOT_SEL).forEach(root => { scan(root); wirePills(root); });
  buildSidebar();
  if (!document.querySelector(TRIGGER)) return;
  buildPop();

  document.addEventListener('mouseover', e => {
    const span = e.target.closest(TRIGGER);
    if (span) { clearTimeout(pop._t); show(span); }
  });
  document.addEventListener('mouseout', e => {
    const span = e.target.closest(TRIGGER);
    if (span && !e.relatedTarget?.closest('.gloss-pop')) pop._t = setTimeout(hide, 120);
  });
  document.addEventListener('focusin', e => {
    const span = e.target.closest(TRIGGER);
    if (span) show(span);
  });
  document.addEventListener('focusout', e => {
    if (e.target.closest(TRIGGER)) hide();
  });
  // Tap to toggle on touch / no-hover devices.
  document.addEventListener('click', e => {
    const span = e.target.closest(TRIGGER);
    if (span) { e.preventDefault(); current === span ? hide() : show(span); }
    else if (!e.target.closest('.gloss-pop')) hide();
  });
  document.addEventListener('keydown', e => { if (e.key === 'Escape') hide(); });
  window.addEventListener('scroll', () => { if (current) position(current); }, { passive: true });
  window.addEventListener('resize', () => { if (current) position(current); });
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
else init();
