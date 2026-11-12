// Linux-runnable check that reader.js translates the renderer's image notes by identifier.
// Run: node --test Tests/ReaderScriptChecks/resource-messages.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const repo = new URL('../../', import.meta.url);
const script = readFileSync(new URL('ReaderApp/Resources/reader.js', repo), 'utf8');
const renderer = readFileSync(new URL('ReaderCore/Sources/ReaderCore/MarkdownRenderer.swift', repo), 'utf8');

const expected = {
  'zh-Hans': ['图片需要所在文件夹的访问权限', '暂不支持此图片地址'],
  'zh-Hant': ['圖片需要所在資料夾的存取權限', '暫不支援此圖片位址'],
  en: ['Images require access to their containing folder', 'This image address is not supported yet'],
  ja: ['画像を含むフォルダへのアクセスが必要です', 'この画像のアドレスにはまだ対応していません'],
  ko: ['이미지가 있는 폴더에 대한 접근 권한이 필요합니다', '아직 지원하지 않는 이미지 주소입니다']
};

// The identifiers and Chinese fallbacks the renderer emits for each image case.
const note = id => {
  const match = renderer.match(new RegExp(`guard ([^\\n]*) else \\{ return "<span class=\\\\"resource-note\\\\" data-reader-message=\\\\"${id}\\\\">([^<]+)</span>"`));
  assert.ok(match, `renderer emits data-reader-message="${id}"`);
  return { guard: match[1], fallback: match[2] };
};

function load(language, ids) {
  const notes = ids.map(id => ({ dataset: { readerMessage: id }, textContent: 'untranslated' }));
  let changed;
  const context = {
    window: { webkit: { messageHandlers: { reader: { postMessage() {} } } } },
    document: {
      documentElement: { dataset: { uiLanguage: language } },
      querySelectorAll: selector => (selector === '.resource-note[data-reader-message]' ? notes : [])
    },
    MutationObserver: class { constructor(callback) { changed = callback; } observe() {} },
    addEventListener() {},
    setTimeout, clearTimeout
  };
  vm.runInNewContext(script, context);
  return {
    texts: () => notes.map(n => n.textContent),
    switchTo: next => { context.document.documentElement.dataset.uiLanguage = next; changed(); }
  };
}

test('renderer marks folder-access and unsupported-image notes with stable identifiers', () => {
  const folder = note('folder-access');      // ![local](image.png) with allowRelativeImages: false
  const unsupported = note('unsupported-image'); // ![remote](https://example.com/image.png)
  assert.equal(folder.guard, 'allowRelativeImages');
  assert.match(unsupported.guard, /safeDestination\(image\.source, image: true\)/);
  assert.equal(folder.fallback, expected['zh-Hans'][0]);
  assert.equal(unsupported.fallback, expected['zh-Hans'][1]);
});

test('each of the five languages translates both notes on load', () => {
  for (const [language, texts] of Object.entries(expected)) {
    assert.deepEqual(load(language, ['folder-access', 'unsupported-image']).texts(), texts, language);
  }
});

test('unknown language falls back to Simplified Chinese; unknown identifiers stay untouched', () => {
  assert.deepEqual(load('fr', ['folder-access', 'unsupported-image']).texts(), expected['zh-Hans']);
  assert.deepEqual(load('en', ['something-else']).texts(), ['untranslated']);
});

test('switching language back and forth retranslates existing notes', () => {
  const page = load('en', ['folder-access', 'unsupported-image']);
  for (const language of ['zh-Hans', 'en', 'zh-Hant', 'ja', 'ko', 'unknown', 'en', 'zh-Hans']) {
    page.switchTo(language);
    assert.deepEqual(page.texts(), expected[language] ?? expected['zh-Hans'], `after switching to ${language}`);
  }
});
