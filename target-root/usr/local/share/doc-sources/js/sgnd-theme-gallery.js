/* SolidGroundUX documentation theme gallery. Read-only; consumes the generated catalog. */
(function () {
  'use strict';
  const root = document.getElementById('sgnd-theme-gallery');
  if (!root) return;
  const result = document.getElementById('sgnd-themes-results');
  const allButton = document.getElementById('sgnd-themes-all');
  const compareButton = document.getElementById('sgnd-themes-compare');
  const choices = document.getElementById('sgnd-themes-choices');
  const left = document.getElementById('sgnd-themes-left');
  const right = document.getElementById('sgnd-themes-right');
  const count = document.getElementById('sgnd-themes-count');
  let themes = [];
  let mode = 'all';

  function escapeHtml(value) {
    return String(value == null ? '' : value).replace(/[&<>"']/g, function (char) {
      return {'&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;'}[char];
    });
  }
  function safeColor(value, fallback) {
    return typeof value === 'string' && /^#[0-9a-f]{6}$/i.test(value) ? value : (fallback || '#bec9d7');
  }
  function themeColor(theme, key, fallback) {
    return safeColor(theme.colors && theme.colors[key], fallback);
  }
  function colorSpan(theme, key, text) {
    return '<span style="color:' + themeColor(theme, key) + '">' + escapeHtml(text) + '</span>';
  }
  const messageText = {
    STRT: 'Starting operation', INFO: 'Preparing configuration', OK: 'Operation completed',
    WARN: 'Review configuration', FAIL: 'Connection unavailable', END: 'Execution finished'
  };
  function specimen(theme) {
    const messages = ['STRT', 'INFO', 'OK', 'WARN', 'FAIL', 'END'].map(function (key) {
      const message = (theme.messages && theme.messages[key]) || {};
      const shade = safeColor(message.color);
      return '<div class="sgnd-theme-msg">' +
        '<span class="sgnd-theme-icon" style="color:' + shade + '">' + escapeHtml(message.icon || message.symbol || '') + '</span>' +
        '<span class="sgnd-theme-label" style="color:' + shade + '">' + escapeHtml(message.label || key) + '</span>' +
        '<span style="color:' + themeColor(theme, 'SGND_UI_TEXT') + '">' + escapeHtml(messageText[key]) + '</span></div>';
    }).join('');
    const swatches = [
      'SGND_UI_BORDER','SGND_UI_LABEL','SGND_UI_VALUE','SGND_UI_TEXT',
      'SGND_UI_PROMPT','SGND_UI_INPUT','SGND_UI_SUCCESS','SGND_UI_ERROR'
    ].map(function (key) {
      return '<span title="' + key + '" style="background:' + themeColor(theme, key) + '"></span>';
    }).join('');
    const border = themeColor(theme, 'SGND_UI_BORDER');
    const section = themeColor(theme, 'SGND_SECTION_TEXTCLR');
    const separator = themeColor(theme, 'SGND_DT_HEADERLINE_CLR');
    return '<article class="sgnd-theme-card"><div class="sgnd-theme-cardhead"><b>' + escapeHtml(theme.name) +
      '</b><small>' + escapeHtml(theme.file) + '</small></div>' +
      '<div class="sgnd-theme-screen">' +
      '<div class="sgnd-theme-title" style="color:' + themeColor(theme, 'SGND_TITLE_TEXTCLR') + '">SolidGroundUX Management Console</div>' +
      '<div class="sgnd-theme-rule" style="background:' + border + '"></div>' +
      '<div class="sgnd-theme-subtitle" style="color:' + section + '">Message output</div>' + messages +
      '<div class="sgnd-theme-subtitle" style="color:' + section + '">Settings &amp; input</div>' +
      '<div>' + colorSpan(theme, 'SGND_UI_LABEL', 'Active setting: ') + colorSpan(theme, 'SGND_UI_VALUE', 'configuration = enabled') + '</div>' +
      '<div class="sgnd-theme-prompt">' + colorSpan(theme, 'SGND_UI_PROMPT', 'Select option: ') + colorSpan(theme, 'SGND_UI_INPUT', '1') + '</div>' +
      '<div class="sgnd-theme-subtitle" style="color:' + section + '">DataTable</div>' +
      '<div class="sgnd-theme-rule" style="background:' + separator + '"></div>' +
      '<table class="sgnd-theme-sample-table"><thead><tr style="color:' + themeColor(theme, 'SGND_DT_COLUMNNAME_CLR') + '"><th>Module</th><th>State</th><th>Count</th></tr></thead>' +
      '<tbody style="color:' + themeColor(theme, 'SGND_DT_DATACOLOR_CLR') + '"><tr><td>Framework</td><td>Ready</td><td>128</td></tr>' +
      '<tr><td>Console</td><td>Enabled</td><td>36</td></tr><tr><td>Storage</td><td>Online</td><td>12</td></tr></tbody></table>' +
      '<div class="sgnd-theme-rule" style="background:' + separator + '"></div>' +
      '<div class="sgnd-theme-subtitle" style="color:' + section + '">Progress</div>' +
      '<div style="color:' + themeColor(theme, 'SGND_UI_TEXT') + '">Synchronizing... 65%</div>' +
      '<div class="sgnd-theme-progress"><span style="background:' + themeColor(theme, 'PROG_BAR_CLR') + ';width:65%"></span><span style="background:#293341;width:35%"></span></div>' +
      '<div class="sgnd-theme-swatches">' + swatches + '</div></div>' +
      '<div class="sgnd-theme-foot">Theme file: ' + escapeHtml(theme.file) + '</div></article>';
  }
  function render() {
    choices.hidden = mode !== 'compare';
    allButton.classList.toggle('active', mode === 'all');
    compareButton.classList.toggle('active', mode === 'compare');
    allButton.setAttribute('aria-pressed', String(mode === 'all'));
    compareButton.setAttribute('aria-pressed', String(mode === 'compare'));
    if (mode === 'all') {
      result.className = 'sgnd-theme-grid';
      result.innerHTML = themes.map(specimen).join('');
      count.textContent = themes.length + ' available themes';
    } else {
      result.className = 'sgnd-theme-grid sgnd-theme-grid-compare';
      result.innerHTML = [left.value, right.value].map(function (key) {
        return specimen(themes.find(function (theme) { return theme.key === key; }));
      }).join('');
      count.textContent = 'Side-by-side comparison';
    }
  }
  allButton.addEventListener('click', function () { mode = 'all'; render(); });
  compareButton.addEventListener('click', function () { mode = 'compare'; render(); });
  left.addEventListener('change', render);
  right.addEventListener('change', render);
  fetch('/assets/sgnd-theme-gallery.json').then(function (response) {
    if (!response.ok) throw new Error('Theme definitions are unavailable (' + response.status + ')');
    return response.json();
  }).then(function (loaded) {
    if (!Array.isArray(loaded) || !loaded.length) throw new Error('No themes found');
    themes = loaded;
    for (const select of [left, right]) {
      for (const theme of themes) {
        const option = document.createElement('option');
        option.value = theme.key;
        option.textContent = theme.name;
        select.appendChild(option);
      }
    }
    left.value = themes[0].key;
    right.value = (themes[1] || themes[0]).key;
    render();
  }).catch(function (error) {
    result.textContent = 'Unable to load the theme gallery: ' + error.message;
    count.textContent = '';
  });
}());
