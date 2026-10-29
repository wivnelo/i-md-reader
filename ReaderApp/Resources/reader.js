(() => {
  const bridge = window.webkit.messageHandlers.reader;
  let timer;
  const english = () => document.documentElement.dataset.uiLanguage === 'en';
  const resourceMessages = {
    'folder-access': ['图片需要所在文件夹的访问权限', 'Images require access to their containing folder'],
    'unsupported-image': ['暂不支持此图片地址', 'This image address is not supported yet']
  };
  const updateInterface = () => {
    document.querySelectorAll('.copy').forEach(button => {
      button.textContent = button.dataset.copied === 'true'
        ? (english() ? 'Copied' : '已复制') : (english() ? 'Copy' : '复制');
    });
    document.querySelectorAll('.table-scroll').forEach(table => table.setAttribute('aria-label', english() ? 'Table' : '表格'));
    document.querySelectorAll('input[type=checkbox][disabled]').forEach(box => box.setAttribute('aria-label', english() ? 'Task status' : '任务状态'));
    document.querySelectorAll('.resource-note[data-reader-message]').forEach(note => {
      const message = resourceMessages[note.dataset.readerMessage];
      if (message) note.textContent = message[english() ? 1 : 0];
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
