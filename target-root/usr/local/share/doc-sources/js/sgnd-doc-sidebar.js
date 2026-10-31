(() => {
  'use strict';
  const shell = document.querySelector('.doc-shell');
  const nav = document.querySelector('.doc-nav');
  const grip = document.querySelector('.doc-nav-resizer');

  // A section label opens its page (or first published descendant), while
  // the chevron retains the native details expand/collapse behavior.
  // Nested links inside <summary> alone are not a reliable click target for
  // the entire label row, so make the two actions explicit.
  if (nav) nav.addEventListener('click', event => {
    if (!(event.target instanceof Element)) return;
    const summary = event.target.closest('details.wc-nav-group > summary');
    if (!summary || !nav.contains(summary)) return;
    if (event.target.closest('.wc-nav-arrow')) return;
    // Preserve keyboard operation and browser new-tab/modifier behavior.
    if (event.detail === 0 || event.button !== 0 ||
        event.ctrlKey || event.metaKey || event.altKey || event.shiftKey) return;
    const destination = summary.querySelector('a[href]');
    if (!destination) return;
    event.preventDefault();
    window.location.assign(destination.href);
  });

  if (!shell || !nav || !grip) return;
  const key = 'solidgroundux-doc-sidebar-width';
  const defaultWidth = 350;
  const constrained = width => Math.min(650, Math.max(240, width));
  const setWidth = value => {
    const width = constrained(value);
    shell.style.setProperty('--doc-nav-width', `${width}px`);
    grip.setAttribute('aria-valuenow', String(Math.round(width)));
  };
  try {
    const saved = Number(localStorage.getItem(key));
    if (saved) setWidth(saved);
  } catch (_) { /* Storage may be unavailable. */ }
  const save = width => { try { localStorage.setItem(key, String(Math.round(width))); } catch (_) {} };
  let active = false;
  grip.addEventListener('pointerdown', event => {
    if (event.button !== 0 || window.matchMedia('(max-width: 850px)').matches) return;
    active = true;
    grip.setPointerCapture(event.pointerId);
    event.preventDefault();
  });
  grip.addEventListener('pointermove', event => {
    if (!active) return;
    setWidth(event.clientX - shell.getBoundingClientRect().left);
  });
  const finish = () => {
    if (!active) return;
    active = false;
    save(nav.getBoundingClientRect().width);
  };
  grip.addEventListener('pointerup', finish);
  grip.addEventListener('pointercancel', finish);
  grip.addEventListener('dblclick', () => { setWidth(defaultWidth); save(defaultWidth); });
  grip.addEventListener('keydown', event => {
    if (!['ArrowLeft', 'ArrowRight', 'Home'].includes(event.key)) return;
    event.preventDefault();
    const width = event.key === 'Home' ? defaultWidth : nav.getBoundingClientRect().width + (event.key === 'ArrowLeft' ? -20 : 20);
    setWidth(width);
    save(width);
  });
})();
