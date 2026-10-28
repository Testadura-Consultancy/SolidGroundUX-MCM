(() => {
  'use strict';
  const query = document.getElementById('doc-api-query');
  const table = document.getElementById('doc-api-results');
  const count = document.getElementById('doc-api-count');
  if (!query || !table || !count) return;
  let entries = [];
  const appendText = (element, value) => { element.textContent = value; return element; };
  const render = () => {
    const terms = query.value.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean);
    const matches = entries.filter(entry => terms.every(term =>
      [entry.name, entry.description, entry.product, entry.source].some(field => String(field || '').toLocaleLowerCase().includes(term))));
    const visible = matches.slice(0, 250);
    const fragment = document.createDocumentFragment();
    for (const item of visible) {
      const tr = document.createElement('tr');
      const name = document.createElement('td');
      const anchor = document.createElement('a');
      anchor.href = item.url;
      appendText(anchor, item.name);
      name.appendChild(anchor);
      tr.appendChild(name);
      for (const field of ['description', 'product', 'source']) tr.appendChild(appendText(document.createElement('td'), item[field]));
      fragment.appendChild(tr);
    }
    table.replaceChildren(fragment);
    count.textContent = `${matches.length} of ${entries.length} functions${matches.length > 250 ? ' (showing first 250; refine your search)' : ''}`;
    if (!visible.length) {
      const tr = document.createElement('tr');
      const td = appendText(document.createElement('td'), 'No matching functions.');
      td.colSpan = 4;
      tr.appendChild(td);
      table.appendChild(tr);
    }
  };
  query.addEventListener('input', render);
  fetch('/assets/sgnd-api-index.json').then(response => {
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return response.json();
  }).then(data => { entries = data; render(); }).catch(() => {
    table.replaceChildren();
    const tr = document.createElement('tr');
    const td = appendText(document.createElement('td'), 'Unable to load API index.');
    td.colSpan = 4;
    tr.appendChild(td);
    table.appendChild(tr);
  });
})();
