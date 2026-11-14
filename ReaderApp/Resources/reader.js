(() => {
  const bridge = window.webkit.messageHandlers.reader;
  let timer;
  // [copy, copied, table, task status, folder-access note, unsupported-image note, image-failed note]
  const messages = {
    "zh-Hans": ["复制", "已复制", "表格", "任务状态", "图片需要所在文件夹的访问权限", "暂不支持此图片地址", "图片无法加载"],
    "zh-Hant": ["複製", "已複製", "表格", "任務狀態", "圖片需要所在資料夾的存取權限", "暫不支援此圖片位址", "圖片無法載入"],
    "en": ["Copy", "Copied", "Table", "Task status", "Images require access to their containing folder", "This image address is not supported yet", "The image couldn't be loaded"],
    "ja": ["コピー", "コピーしました", "表", "タスクの状態", "画像を含むフォルダへのアクセスが必要です", "この画像のアドレスにはまだ対応していません", "画像を読み込めませんでした"],
    "ko": ["복사", "복사됨", "표", "작업 상태", "이미지가 있는 폴더에 대한 접근 권한이 필요합니다", "아직 지원하지 않는 이미지 주소입니다", "이미지를 불러올 수 없습니다"]
  };
  const words = () => messages[document.documentElement.dataset.uiLanguage] || messages["zh-Hans"];
  const updateInterface = () => {
    const text = words();
    document.querySelectorAll('.copy').forEach(button => {
      button.textContent = button.dataset.copied === 'true'
        ? text[1] : text[0];
    });
    document.querySelectorAll('.table-scroll').forEach(table => table.setAttribute('aria-label', text[2]));
    document.querySelectorAll('input[type=checkbox][disabled]').forEach(box => box.setAttribute('aria-label', text[3]));
    document.querySelectorAll('.resource-note[data-reader-message]').forEach(note => {
      const index = { 'folder-access': 4, 'unsupported-image': 5, 'image-failed': 6 }[note.dataset.readerMessage];
      if (index !== undefined) note.textContent = text[index];
    });
  };
  // A remote image that fails (offline, removed, blocked) becomes a quiet note instead of a broken icon.
  addEventListener('error', event => {
    const image = event.target;
    if (!image || image.tagName !== 'IMG' || !/^https:/i.test(image.getAttribute('src') || '')) return;
    const note = document.createElement('span');
    note.className = 'resource-note';
    note.dataset.readerMessage = 'image-failed';
    if (image.alt) note.title = image.alt;
    (image.closest('picture') || image).replaceWith(note);
    updateInterface();
  }, true);
  updateInterface();
  new MutationObserver(updateInterface).observe(document.documentElement, { attributes: true, attributeFilter: ['data-ui-language'] });
  // Top-level article block at the top edge plus the fraction scrolled through it (encoded from 2),
  // so a position survives font, width and late image changes across devices.
  const anchor = () => {
    const blocks = document.querySelectorAll('article > :not(#reader-file-dates)');
    for (let index = 0; index < blocks.length; index++) {
      const box = blocks[index].getBoundingClientRect();
      if (box.bottom > 0) return 2 + index + (box.height > 0 ? Math.min(0.999, Math.max(0, -box.top / box.height)) : 0);
    }
    return blocks.length ? 2 + blocks.length - 1 : undefined;
  };
  const report = () => {
    const distance = document.documentElement.scrollHeight - innerHeight;
    bridge.postMessage({ type: 'progress', value: distance > 0 ? Math.min(1, Math.max(0, scrollY / distance)) : 0, anchor: anchor() });
  };
  addEventListener('scroll', () => { clearTimeout(timer); timer = setTimeout(report, 350); }, { passive: true });
  addEventListener('pagehide', report);
  // Color only explicitly supported languages near the viewport. Never guess a grammar for long blocks;
  // a whole source file gets a larger budget and otherwise stays plain, numbered text.
  const highlight = code => {
    const language = code.dataset.language;
    const limit = code.closest('.codefile') ? 200000 : 20000;
    if (!window.hljs || !language || !hljs.getLanguage(language) || code.textContent.length > limit) return;
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
