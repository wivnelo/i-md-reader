(() => {
  const root = document.documentElement;
  const validLanguages = ['zh', 'en'];
  const validThemes = ['system', 'light', 'dark'];
  const read = key => { try { return localStorage.getItem(key); } catch (_) { return null; } };
  const save = (key, value) => { try { localStorage.setItem(key, value); } catch (_) {} };
  let language = validLanguages.includes(read('imdreader-site-language')) ? read('imdreader-site-language') : 'zh';
  let theme = validThemes.includes(read('imdreader-site-theme')) ? read('imdreader-site-theme') : 'system';
  const translations = [...document.querySelectorAll('[data-en]')];
  translations.forEach(element => { element.dataset.zh = element.textContent; });
  const labels = [...document.querySelectorAll('[data-en-aria]')];
  labels.forEach(element => { element.dataset.zhAria = element.getAttribute('aria-label'); });
  const pictureSources = [...document.querySelectorAll('[data-en-src]')];
  pictureSources.forEach(element => { element.dataset.zhSrc = element.getAttribute('src'); });
  const images = [...document.querySelectorAll('[data-en-alt]')];
  images.forEach(element => { element.dataset.zhAlt = element.alt; });
  function render() {
    root.dataset.language = language;
    root.dataset.theme = theme;
    root.lang = language === 'zh' ? 'zh-Hans' : 'en';
    translations.forEach(element => { element.textContent = language === 'en' ? element.dataset.en : element.dataset.zh; });
    pictureSources.forEach(element => { element.setAttribute('src', language === 'en' ? element.dataset.enSrc : element.dataset.zhSrc); });
    images.forEach(element => { element.alt = language === 'en' ? element.dataset.enAlt : element.dataset.zhAlt; });
    labels.forEach(element => { element.setAttribute('aria-label', language === 'en' ? element.dataset.enAria : element.dataset.zhAria); });
    document.querySelectorAll('[data-setting="language"]').forEach(select => { select.value = language; });
    document.querySelectorAll('[data-setting="theme"]').forEach(select => { select.value = theme; });
    if (document.body.dataset.titleEn) document.title = language === 'en' ? document.body.dataset.titleEn : document.body.dataset.titleZh;
  }
  document.body.dataset.titleZh = document.title;
  document.querySelectorAll('[data-setting="language"]').forEach(select => select.addEventListener('change', () => {
    if (!validLanguages.includes(select.value)) return;
    language = select.value; save('imdreader-site-language', language); render();
  }));
  document.querySelectorAll('[data-setting="theme"]').forEach(select => select.addEventListener('change', () => {
    if (!validThemes.includes(select.value)) return;
    theme = select.value; save('imdreader-site-theme', theme); render();
  }));
  render();
})();
