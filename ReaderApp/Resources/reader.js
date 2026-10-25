(() => {
  const bridge = window.webkit.messageHandlers.reader;
  let timer;
  const english = () => document.documentElement.dataset.uiLanguage === 'en';
  document.querySelectorAll('.resource-note').forEach(note => {
    if (note.textContent === '[图片暂未加载]') note.dataset.readerMessage = 'pending';
    if (note.textContent === '[图片未加载：仅支持本地相对图片]') note.dataset.readerMessage = 'relative';
  });
  const updateInterface = () => {
    document.querySelectorAll('.copy').forEach(button => {
      button.textContent = button.dataset.copied === 'true'
        ? (english() ? 'Copied' : '已复制') : (english() ? 'Copy' : '复制');
    });
    document.querySelectorAll('.table-scroll').forEach(table => table.setAttribute('aria-label', english() ? 'Table' : '表格'));
    document.querySelectorAll('input[type=checkbox][disabled]').forEach(box => box.setAttribute('aria-label', english() ? 'Task status' : '任务状态'));
    document.querySelectorAll('.resource-note[data-reader-message]').forEach(note => {
      note.textContent = note.dataset.readerMessage === 'pending'
        ? (english() ? '[Image not loaded]' : '[图片暂未加载]')
        : (english() ? '[Image not loaded: only local relative images are supported]' : '[图片未加载：仅支持本地相对图片]');
    });
  };
  updateInterface();
  new MutationObserver(updateInterface).observe(document.documentElement, { attributes: true, attributeFilter: ['data-ui-language'] });
  const report = () => {
    const distance = document.documentElement.scrollHeight - innerHeight;
    bridge.postMessage({ type: 'progress', value: distance > 0 ? Math.min(1, Math.max(0, scrollY / distance)) : 0 });
  };
  addEventListener('scroll', () => { clearTimeout(timer); timer = setTimeout(report, 350); }, { passive: true });
  addEventListener('pagehide', report);
  // Color only explicitly supported languages near the viewport. Never guess a grammar for long blocks.
  const highlight = code => {
    const language = code.dataset.language;
    if (!window.hljs || !language || !hljs.getLanguage(language) || code.textContent.length > 20000) return;
    try { code.innerHTML = hljs.highlight(code.textContent, { language, ignoreIllegals: true }).value; } catch (_) { /* Keep escaped plain text. */ }
  };
  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver(entries => {
      entries.forEach(entry => { if (entry.isIntersecting) { observer.unobserve(entry.target); highlight(entry.target); } });
    }, { rootMargin: '240px' });
    document.querySelectorAll('pre code[data-language]').forEach(code => observer.observe(code));
  } else { document.querySelectorAll('pre code[data-language]').forEach(highlight); }
  document.querySelectorAll('.copy').forEach(button => {
    button.addEventListener('click', () => {
      const code = button.closest('.codeblock')?.querySelector('code')?.textContent;
      if (code == null) return;
      bridge.postMessage({ type: 'copy', text: code });
      button.dataset.copied = 'true';
      updateInterface();
      setTimeout(() => { button.dataset.copied = 'false'; updateInterface(); }, 1500);
    });
  });
})();
