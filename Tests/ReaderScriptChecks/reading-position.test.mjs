// Linux-runnable check of reading-position save (reader.js anchor) and restore (ReaderWebView.positionScript)
// against a fake block layout, including width reflow (iPad Split View / Stage Manager) and late image loads.
// Both scripts are read from the production sources, so the tests cannot drift from the app.
// Run: node --test Tests/ReaderScriptChecks/reading-position.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const repo = new URL('../../', import.meta.url);
const reader = readFileSync(new URL('ReaderApp/Resources/reader.js', repo), 'utf8');
const swift = readFileSync(new URL('ReaderApp/ReaderWebView.swift', repo), 'utf8');

// Mirrors `static func positionScript(_ value: Double) -> String` by substituting the Swift interpolations.
const positionBody = swift.slice(swift.indexOf('static func positionScript'), swift.indexOf('private var appearanceScript'));
const legacy = positionBody.match(/return "(window\.scrollTo[^"]*)"/)[1];
const blockScript = positionBody.match(/return """\n([\s\S]*?)\n\s*"""/)[1];
function positionScript(value) {
  value = Number.isFinite(value) ? value : 0;
  if (value < 2) return legacy.replace('\\(min(1, max(0, value)))', String(Math.min(1, Math.max(0, value))));
  return blockScript.replaceAll('\\(value)', String(value));
}

class HTMLImageElement {}

// Top-level article blocks stacked vertically after an optional dates box; only geometry matters.
function page({ heights, innerHeight = 800, datesHeight = 0 }) {
  const state = { heights: [...heights], scrollY: 0, timers: [], windowListeners: {}, documentListeners: [], messages: [] };
  const tops = () => { let y = datesHeight; return state.heights.map(h => { const top = y; y += h; return top; }); };
  const scrollHeight = () => datesHeight + state.heights.reduce((a, b) => a + b, 0);
  const blocks = state.heights.map((_, index) => ({
    getBoundingClientRect() {
      const top = tops()[index] - state.scrollY, height = state.heights[index];
      return { top, height, bottom: top + height };
    }
  }));
  const clamp = () => { state.scrollY = Math.max(0, Math.min(state.scrollY, Math.max(0, scrollHeight() - innerHeight))); };
  const context = {
    HTMLImageElement,
    MutationObserver: class { observe() {} },
    document: {
      documentElement: { dataset: { uiLanguage: 'en' }, get scrollHeight() { return Math.max(scrollHeight(), innerHeight); } },
      querySelectorAll: selector => (selector === 'article > :not(#reader-file-dates)' ? blocks : []),
      addEventListener: (type, listener, capture) => state.documentListeners.push({ type, listener, capture })
    },
    addEventListener(type, listener, options) { (state.windowListeners[type] ??= []).push({ listener, once: options?.once }); },
    scrollTo(_, y) { state.scrollY = y; clamp(); },
    setTimeout(callback, delay) { state.timers.push({ callback, delay }); return state.timers.length; },
    clearTimeout() {},
    get scrollY() { return state.scrollY; },
    get innerHeight() { return innerHeight; }
  };
  context.window = context;
  context.window.webkit = { messageHandlers: { reader: { postMessage: message => state.messages.push(message) } } };
  vm.createContext(context);
  vm.runInContext(reader, context);
  const fire = type => {
    const listeners = state.windowListeners[type] ?? [];
    state.windowListeners[type] = listeners.filter(entry => !entry.once);
    listeners.forEach(entry => entry.listener({ type }));
  };
  return {
    state,
    run: source => vm.runInContext(source, context),
    scrollTo: y => { state.scrollY = y; clamp(); },
    // Saved value the app would persist: the anchor reader.js reports on pagehide.
    anchor() { fire('pagehide'); return state.messages.at(-1).anchor; },
    // Where the viewport top sits as block index + fraction, independent of reader.js.
    position() {
      const t = tops();
      const index = state.heights.findIndex((h, i) => t[i] + h > state.scrollY);
      return index + (state.scrollY - t[index]) / state.heights[index];
    },
    reflow(next) { state.heights = [...next]; clamp(); },
    resize: () => fire('resize'),
    interact: type => fire(type),
    imageLoaded: (target = new HTMLImageElement()) => state.documentListeners
      .filter(entry => entry.type === 'load' && entry.capture === true).forEach(entry => entry.listener({ target })),
    expire: () => state.timers.filter(timer => timer.delay === 10000).forEach(timer => timer.callback())
  };
}

const close = (actual, expected, message) => assert.ok(Math.abs(actual - expected) < 1e-9, `${message}: ${actual} != ${expected}`);
const heights = [100, 400, 200, 600, 300, 500, 900];

test('anchor encodes the block at the viewport top as 2 + index + fraction', () => {
  const view = page({ heights, datesHeight: 40 });
  view.scrollTo(0);
  close(view.anchor(), 2, 'before the first block (dates box visible)');
  view.scrollTo(40 + 100 + 100); // a quarter into block 1
  close(view.anchor(), 3.25, 'inside block 1');
  view.scrollTo(40 + 100 + 400); // exactly at block 2's top
  close(view.anchor(), 4, 'block boundary');
  // Without room to scroll past the end, the last block is reported with its in-block fraction.
  view.scrollTo(1e9);
  const end = view.state.scrollY - (40 + 100 + 400 + 200 + 600 + 300 + 500);
  close(view.anchor(), 2 + 6 + end / 900, 'end of document');
});

test('anchor edge cases: zero-height block, past the last block, no blocks', () => {
  const zero = page({ heights: [100, 0, 300], innerHeight: 100 });
  zero.scrollTo(100);
  close(zero.anchor(), 4, 'a zero-height block at the top edge is skipped (bottom is not below 0)');
  const empty = page({ heights: [] });
  assert.equal(empty.anchor(), undefined, 'no blocks reports no anchor');
  // Past the last block (only possible if the viewport top is below every block).
  const short = page({ heights: [100, 100], innerHeight: 50 });
  short.state.scrollY = 500;
  close(short.anchor(), 3, 'past the last block falls back to the last block start');
  // Fractions never reach the next block.
  const fraction = page({ heights: [1000, 1000], innerHeight: 10 });
  fraction.scrollTo(999.9999);
  assert.ok(fraction.anchor() < 3, 'fraction stays below the next index');
});

test('restore lands on the saved block and fraction, including after a font change', () => {
  const saved = page({ heights, datesHeight: 40 });
  saved.scrollTo(40 + 100 + 400 + 200 + 150); // a quarter into block 3
  const value = saved.anchor();
  close(value, 5.25, 'saved anchor');

  const bigger = page({ heights: heights.map(h => h * 1.5), datesHeight: 40 });
  bigger.run(positionScript(value));
  close(bigger.position(), 3.25, 'restored at block 3 + 0.25 with larger text');
  close(bigger.anchor(), value, 'round trip reports the same anchor');
});

test('restore past the last block goes to the end of the last block', () => {
  const view = page({ heights: [500, 500, 500], innerHeight: 200 });
  view.run(positionScript(2 + 9.5));
  assert.equal(view.state.scrollY, 1300, 'clamped to the end of the last block (document end)');
});

test('legacy 0...1 ratios scroll once to the whole-document ratio and do not re-align', () => {
  const view = page({ heights: [1000, 1000, 1000], innerHeight: 1000 });
  view.run(positionScript(0.5));
  assert.equal(view.state.scrollY, 1000);
  view.reflow([2000, 1000, 1000]);
  view.resize();
  view.imageLoaded();
  assert.equal(view.state.scrollY, 1000, 'no listeners for legacy ratios');
  assert.deepEqual(view.state.documentListeners, []);
  view.run(positionScript(Number.NaN));
  assert.equal(view.state.scrollY, 0, 'non-finite values restore to the top');
});

test('width change (Split View / Stage Manager) before interaction re-applies the saved block and fraction', () => {
  const view = page({ heights });
  const value = 2 + 4 + 0.4; // block 4, 40% in
  view.run(positionScript(value));
  close(view.position(), 4.4, 'initial restore at the wide width');
  const pixels = view.state.scrollY;

  // Narrower column: text and images wrap, so every block gets taller; the pixel scrollY is now stale.
  view.reflow(heights.map(h => h * 1.8));
  assert.ok(Math.abs(view.position() - 4.4) > 0.5, `stale pixel offset ${pixels} drifts to ${view.position()}`);
  view.resize();
  close(view.position(), 4.4, 'resize re-applies the saved block and fraction');

  // Back to the wide width (leaving Split View).
  view.reflow(heights);
  view.resize();
  close(view.position(), 4.4, 'second resize re-applies again');
});

test('late image load above the target re-aligns; images below change nothing', () => {
  const view = page({ heights: [100, 300, 200, 800, 400] });
  view.run(positionScript(2 + 3 + 0.5));
  close(view.position(), 3.5, 'initial restore');

  view.reflow([100, 300 + 640, 200, 800, 400]); // image in block 1 loads with its real height
  assert.ok(view.position() < 3, 'without re-apply the reader would see an earlier block');
  view.imageLoaded();
  close(view.position(), 3.5, 'image load re-applies');

  view.reflow([100, 940, 200, 800, 400 + 900]); // image below the target
  const before = view.state.scrollY;
  view.imageLoaded();
  assert.equal(view.state.scrollY, before, 'image below the target keeps the same offset');

  view.reflow([100, 940, 200, 800 + 300, 1300]); // image inside the target block grows it
  view.imageLoaded();
  close(view.position(), 3.5, 'same fraction of the grown target block');

  const other = view.state.scrollY;
  view.reflow([100, 1200, 200, 1100, 1300]);
  view.imageLoaded({}); // a non-image load (e.g. a script or frame) does not re-apply
  close(view.state.scrollY, other, 'offset unchanged by a non-image load');
});

for (const type of ['wheel', 'touchstart', 'keydown', 'mousedown']) {
  test(`${type} stops later image-load and resize re-alignment`, () => {
    const view = page({ heights });
    view.run(positionScript(5.5));
    view.interact(type);
    view.scrollTo(250); // the reader moves somewhere else
    view.reflow(heights.map(h => h * 2));
    view.resize();
    view.imageLoaded();
    assert.equal(view.state.scrollY, 250, 'the reader keeps their own position');
  });
}

test('the 10 second window ends re-alignment; programmatic scrolls and resizes do not settle it early', () => {
  const view = page({ heights });
  view.run(positionScript(5.5));
  view.interact('scroll'); // our own scrollTo fires scroll events; they must not count as interaction
  view.reflow(heights.map(h => h * 1.3));
  view.resize();
  view.resize();
  close(view.position(), 3.5, 'still aligned after repeated resizes');
  view.reflow(heights.map(h => h * 1.6));
  view.imageLoaded();
  close(view.position(), 3.5, 'image load after resizes still re-applies');

  view.expire();
  const settled = view.state.scrollY;
  view.reflow(heights);
  view.resize();
  view.imageLoaded();
  assert.equal(view.state.scrollY, settled, 'no re-alignment after the window ends');
});
