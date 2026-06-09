// Single source of truth for site navigation (the static-site equivalent of a
// server-rendered nav helper). Every page drops a `<div data-nav="KEY"></div>`
// placeholder; this module replaces it with the shared bar and marks KEY as the
// active item (rendered as a non-link so it stays visible). Change a label, href,
// or the page set HERE and every page updates — do not hand-write nav anywhere.
const NAV = [
  { key: 'dashboard', href: 'index.html',   label: 'Run log' },
  { key: 'problem',   href: 'samples.html', label: 'The problem' },
  { key: 'lineage',   href: 'lineage.html', label: 'Program lineage', sub: true },
];

export function renderNav(current) {
  let prevSub = false;
  const items = NAV.map(it => {
    const div = (it.sub && !prevSub) ? '<span class="nav-div" aria-hidden="true"></span>' : '';
    prevSub = !!it.sub;
    const cls = [it.sub && 'nav-sub', it.key === current && 'nav-here'].filter(Boolean).join(' ');
    const attr = cls ? ` class="${cls}"` : '';
    const node = it.key === current
      ? `<span${attr}>${it.label}</span>`
      : `<a${attr} href="${it.href}">${it.label}</a>`;
    return div + node;
  });
  return `<nav class="sitenav">${items.join('')}</nav>`;
}

const slot = document.querySelector('[data-nav]');
if (slot) slot.outerHTML = renderNav(slot.getAttribute('data-nav'));

// Shared site footer — one definition, appended to every page that loads this module.
export function renderFooter() {
  return `<footer class="site-footer">Ramble &rarr; Tasks &middot; an on-device Apple Foundation Models research log by `
    + `<a href="https://github.com/akaalias">Alexis Rondeau</a>, built with Claude Code.</footer>`;
}
if (document.body && !document.body.querySelector('.site-footer'))
  document.body.insertAdjacentHTML('beforeend', renderFooter());
