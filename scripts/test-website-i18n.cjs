// Run the shipped browser scripts against DOM/storage fixtures; no dependencies or network.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'website/index.html'), 'utf8');
const i18n = fs.readFileSync(path.join(root, 'website/i18n.js'), 'utf8');
const site = fs.readFileSync(path.join(root, 'website/site.js'), 'utf8');
const storageKey = 'blinkclip.website.language';
const VOID = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr']);
let checks = 0;
function check(name, operation) { operation(); checks++; }

class Element {
  constructor(tag, attrs = {}) {
    this.tag = tag;
    this.attrs = attrs;
    this.children = [];
    this.parent = null;
    this.ownerDocument = null;
    this.events = new Map();
    this.hidden = false;
    this.open = false;
    this.text = '';
    this.classList = {
      contains: (name) => (this.attrs.class || '').split(/\s+/).includes(name),
      add: (name) => { if (!this.classList.contains(name)) this.attrs.class = `${this.attrs.class || ''} ${name}`.trim(); },
      remove: (name) => { this.attrs.class = (this.attrs.class || '').split(/\s+/).filter((item) => item && item !== name).join(' '); },
      toggle: (name, force) => {
        const next = force === undefined ? !this.classList.contains(name) : force;
        if (next) this.classList.add(name); else this.classList.remove(name);
        return next;
      }
    };
  }
  get dataset() {
    if (!this.datasetCache) {
      const attrs = this.attrs;
      const attributeName = (key) => `data-${String(key).replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`)}`;
      this.datasetCache = new Proxy({}, {
        get: (_, key) => attrs[attributeName(key)],
        set: (_, key, value) => { attrs[attributeName(key)] = String(value); return true; },
        has: (_, key) => Object.hasOwn(attrs, attributeName(key)),
        ownKeys: () => Object.keys(attrs).filter((name) => name.startsWith('data-'))
          .map((name) => name.slice(5).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())),
        getOwnPropertyDescriptor: () => ({ enumerable: true, configurable: true })
      });
    }
    return this.datasetCache;
  }
  get textContent() {
    return this.text + this.children.map((child) => child.textContent).join('');
  }
  set textContent(value) {
    this.text = String(value);
    this.children = [];
  }
  getAttribute(name) { return this.attrs[name] ?? null; }
  setAttribute(name, value) { this.attrs[name] = String(value); }
  removeAttribute(name) { delete this.attrs[name]; }
  append(child) { child.parent = this; child.ownerDocument = this.ownerDocument; this.children.push(child); }
  contains(node) {
    if (node === this) return true;
    return this.children.some((child) => child.contains(node));
  }
  querySelectorAll(selector) {
    const groups = selector.trim().split(/\s+/);
    const last = groups[groups.length - 1];
    const found = [];
    const visit = (element) => {
      for (const child of element.children) {
        if (matchesSimple(child, last) && matchesAncestors(child, groups.slice(0, -1))) found.push(child);
        visit(child);
      }
    };
    visit(this);
    return found;
  }
  querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
  addEventListener(name, callback) { this.events.set(name, callback); }
  emit(name, event = {}) { this.events.get(name)?.({ target: this, ...event }); }
  focus() { if (this.ownerDocument) this.ownerDocument.activeElement = this; }
}

function matchesSimple(element, selector) {
  const parsed = selector.match(/^([a-z][\w-]*)?((?:[#.][\w-]+|\[[\w:-]+(?:=(?:"[^"]*"|'[^']*'|[^\]]*))?\])*)$/i);
  if (!parsed) return false;
  if (parsed[1] && element.tag !== parsed[1].toLowerCase()) return false;
  for (const token of parsed[2].matchAll(/([#.])([\w-]+)|\[([\w:-]+)(?:=(?:"([^"]*)"|'([^']*)'|([^\]]*)))?\]/g)) {
    if (token[1] === '#') {
      if (element.attrs.id !== token[2]) return false;
    } else if (token[1] === '.') {
      if (!element.classList.contains(token[2])) return false;
    } else {
      const name = token[3];
      const expected = token[4] ?? token[5] ?? token[6];
      if (!Object.hasOwn(element.attrs, name)) return false;
      if (expected !== undefined && element.attrs[name] !== expected) return false;
    }
  }
  return true;
}

function matchesAncestors(element, groups) {
  let current = element.parent;
  for (let index = groups.length - 1; index >= 0; index -= 1) {
    while (current && !matchesSimple(current, groups[index])) current = current.parent;
    if (!current) return false;
    current = current.parent;
  }
  return true;
}

function parseAttributes(raw) {
  const attrs = {};
  for (const match of raw.matchAll(/([\w:-]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>`=]+)))?/g)) {
    attrs[match[1]] = match[2] ?? match[3] ?? match[4] ?? '';
  }
  return attrs;
}

function parseHTML(source) {
  const wrapper = new Element('#document');
  const stack = [wrapper];
  const token = /<!--[\s\S]*?-->|<!doctype[^>]*>|<(\/?)([a-z][\w-]*)((?:[^>"']|"[^"]*"|'[^']*')*?)(\/?)>/gi;
  let cursor = 0;
  for (const match of source.matchAll(token)) {
    const text = source.slice(cursor, match.index);
    if (text.trim()) stack[stack.length - 1].text += text;
    cursor = match.index + match[0].length;
    if (match[0].startsWith('<!--') || /^<!doctype/i.test(match[0])) continue;
    const [, closing, tag, rawAttrs, selfClosing] = match;
    const name = tag.toLowerCase();
    if (closing) {
      for (let index = stack.length - 1; index > 0; index -= 1) {
        if (stack[index].tag === name) { stack.length = index; break; }
      }
      continue;
    }
    const element = new Element(name, parseAttributes(rawAttrs));
    stack[stack.length - 1].append(element);
    if (!selfClosing && !VOID.has(name)) stack.push(element);
  }
  return wrapper;
}

function runtime(languages, saved = null, blocked = false) {
  const tree = parseHTML(html);
  const documentElement = tree.querySelector('html');
  const events = new Map();
  const document = {
    documentElement,
    title: '',
    activeElement: null,
    querySelectorAll: (selector) => documentElement.querySelectorAll(selector),
    querySelector: (selector) => documentElement.querySelector(selector),
    addEventListener: (name, callback) => events.set(name, callback),
    dispatchEvent: (event) => events.get(event.type)?.(event)
  };
  documentElement.ownerDocument = document;
  const assignDocument = (element) => {
    element.ownerDocument = document;
    for (const child of element.children) assignDocument(child);
  };
  assignDocument(documentElement);
  const storage = new Map(saved === null ? [] : [[storageKey, saved]]);
  const storageAPI = {
    getItem(key) { if (blocked) throw new Error('storage blocked'); return storage.get(key) ?? null; },
    setItem(key, value) { if (blocked) throw new Error('storage blocked'); storage.set(key, value); },
    removeItem(key) { if (blocked) throw new Error('storage blocked'); storage.delete(key); }
  };
  const windowEvents = new Map();
  const window = { addEventListener: (name, callback) => windowEvents.set(name, callback) };
  const navigator = { languages, language: languages[0] };
  const context = vm.createContext({
    document, window, navigator, localStorage: storageAPI,
    CustomEvent: class { constructor(type, options) { this.type = type; this.detail = options?.detail; } }
  });
  vm.runInContext(i18n, context, { filename: 'website/i18n.js' });
  vm.runInContext(site, context, { filename: 'website/site.js' });
  return {
    document,
    storage,
    navigator,
    api: window.BlinkClipI18n,
    choose(value) { document.querySelector(`[data-language="${value}"]`).emit('click'); },
    systemChanges(next) { navigator.languages = next; navigator.language = next[0]; windowEvents.get('languagechange')(); }
  };
}

const messages = JSON.parse(i18n.match(/const messages = (\{[\s\S]*?\n  \});/)[1]);

check('catalogs have identical keys and placeholders', () => {
  assert.deepEqual(Object.keys(messages.en).sort(), Object.keys(messages['zh-Hans']).sort());
  for (const key of Object.keys(messages.en)) {
    assert.ok(messages.en[key] && messages['zh-Hans'][key], key);
    assert.deepEqual(messages.en[key].match(/\{\w+\}/g), messages['zh-Hans'][key].match(/\{\w+\}/g), key);
  }
});
check('all HTML translation bindings exist in both catalogs', () => {
  for (const [, key] of html.matchAll(/data-i18n(?:-(?:alt|aria-label|placeholder|content|title))?="([^"]+)"/g)) {
    assert.ok(Object.hasOwn(messages.en, key) && Object.hasOwn(messages['zh-Hans'], key), key);
  }
});
for (const [languages, expected] of [
  [['zh-CN', 'en'], 'zh-Hans'], [['zh-TW'], 'zh-Hans'], [['en-US'], 'en'],
  [['ja-JP', 'fr-FR'], 'en'], [['fr-FR', 'zh-CN'], 'zh-Hans'], [[], 'en']
]) check(`system negotiation ${languages.join(',') || 'missing'}`, () => {
  const app = runtime(languages);
  assert.equal(app.api.language, expected);
  assert.equal(app.document.documentElement.lang, expected);
  assert.equal(app.document.querySelector('[data-language="system"]').getAttribute('aria-pressed'), 'true');
  assert.equal(app.storage.size, 0);
});
check('manual preference wins over system and persists across visits', () => {
  const app = runtime(['zh-CN']); app.choose('en');
  assert.equal(app.storage.get(storageKey), 'en');
  assert.equal(runtime(['zh-CN'], app.storage.get(storageKey)).api.language, 'en');
});
check('legacy zh-CN preference is migrated to zh-Hans', () => {
  const app = runtime(['en-US'], 'zh-CN');
  assert.equal(app.api.language, 'zh-Hans');
  assert.equal(app.document.documentElement.lang, 'zh-Hans');
});
check('returning to system removes manual override', () => {
  const app = runtime(['zh-CN'], 'en'); app.choose('system');
  assert.equal(app.api.language, 'zh-Hans'); assert.equal(app.storage.has(storageKey), false);
});
check('invalid saved preference falls back to system', () => {
  assert.equal(runtime(['zh-CN'], 'not-a-supported-language').api.language, 'zh-Hans');
});
check('storage denial preserves usable language switching', () => {
  const app = runtime(['zh-CN'], null, true); app.choose('en');
  assert.equal(app.api.language, 'en'); assert.equal(app.document.documentElement.lang, 'en');
});
check('system language changes are observed in automatic mode', () => {
  const app = runtime(['zh-CN']); app.systemChanges(['en-GB']); assert.equal(app.api.language, 'en');
});
check('system changes do not override manual choice', () => {
  const app = runtime(['en-US'], 'zh-Hans'); app.systemChanges(['en-GB']); assert.equal(app.api.language, 'zh-Hans');
});
check('metadata, document title, accessible labels and image alt are localized', () => {
  const app = runtime(['en-US']);
  assert.equal(app.document.querySelector('meta[property="og:locale"]').content, 'en_US');
  assert.ok(app.document.querySelector('meta[name="description"]').getAttribute('content').includes('local-first'));
  assert.ok(app.document.querySelector('title').textContent.startsWith('BlinkClip'));
  assert.ok(app.document.title.startsWith('BlinkClip'));
  assert.ok(app.document.querySelector('.hero-shot img').getAttribute('alt').includes('clipboard panel'));
  assert.equal(app.document.querySelector('#language-trigger').getAttribute('title'), 'Change language: English');
  assert.equal(app.document.querySelector('#language-trigger').getAttribute('aria-label'), 'Change language: English');
});
check('Chinese copy and document language are applied by default', () => {
  const app = runtime(['zh-CN']);
  assert.equal(app.document.documentElement.lang, 'zh-Hans');
  assert.equal(app.document.querySelector('#hero-title').textContent.replace(/\s+/g, ''), '复制过的，都找得回来。');
  assert.equal(app.document.title, messages['zh-Hans']['meta.title']);
  assert.equal(app.document.querySelector('#language-trigger').getAttribute('aria-label'), '切换语言：简体中文');
});
check('language control reports current language and closes after selection', () => {
  const app = runtime(['zh-CN']); const doc = app.document;
  assert.equal(doc.querySelector('#language-trigger').getAttribute('title'), '切换语言：简体中文');
  doc.querySelector('.language-switch').open = true;
  app.choose('en');
  assert.equal(doc.querySelector('[data-language="en"]').getAttribute('aria-pressed'), 'true');
  assert.equal(doc.querySelector('[data-language="system"]').getAttribute('aria-pressed'), 'false');
  assert.equal(doc.querySelector('#language-trigger').getAttribute('aria-label'), 'Change language: English');
  assert.equal(doc.querySelector('.language-switch').open, false);
  assert.equal(doc.activeElement, doc.querySelector('#language-trigger'));
});
check('FAQ accordion opens, closes and stays exclusive', () => {
  const app = runtime(['zh-CN']); const doc = app.document;
  const items = doc.querySelectorAll('.faq-item');
  assert.equal(items.length, 6);
  const first = items[0].querySelector('.faq-trigger');
  const second = items[1].querySelector('.faq-trigger');
  first.emit('click');
  assert.equal(items[0].dataset.open, 'true');
  assert.equal(first.getAttribute('aria-expanded'), 'true');
  second.emit('click');
  assert.equal(items[0].dataset.open, 'false');
  assert.equal(items[1].dataset.open, 'true');
  assert.equal(first.getAttribute('aria-expanded'), 'false');
  second.emit('click');
  assert.equal(items[1].dataset.open, 'false');
});
check('switching language preserves FAQ state and copy updates in place', () => {
  const app = runtime(['zh-CN']); const doc = app.document;
  doc.querySelector('.faq-trigger').emit('click');
  app.choose('en');
  assert.equal(doc.querySelector('.faq-item').dataset.open, 'true');
  assert.equal(doc.querySelector('.faq-question').textContent, messages.en['faq.q1']);
  assert.equal(doc.querySelector('.faq-answer').textContent, messages.en['faq.a1']);
});
check('counts and measure words are expressed naturally in each language', () => {
  assert.equal(messages.en['stats.installer.title'], 'universal installer');
  assert.equal(messages.en['stats.types.title'], 'item types');
  assert.ok(messages['zh-Hans']['stats.installer.title'].includes('个'));
  assert.ok(messages['zh-Hans']['stats.types.title'].includes('类'));
  const app = runtime(['en-US']);
  assert.equal(app.api.t('language.trigger', { language: 'English' }), 'Change language: English');
  const zh = runtime(['zh-CN']);
  assert.equal(zh.api.t('language.trigger', { language: '简体中文' }), '切换语言：简体中文');
});
// scripts/sync-release-downloads.py rewrites the marker blocks with the latest stable DMG before
// this test runs in CI, so a pinned installer is expected there and only there.
const RELEASE_BASE = 'https://github.com/aexachao/BlinkClip';
const LATEST_RELEASE = `${RELEASE_BASE}/releases/latest`;
const DMG_LINK = /https:\/\/github\.com\/aexachao\/BlinkClip\/releases\/download\/v(\d+\.\d+\.\d+)\/BlinkClip-(\d+\.\d+\.\d+)-macos-universal\.dmg/g;
const syncedRegions = [...html.matchAll(/<!-- blinkclip-download:start -->([\s\S]*?)<!-- blinkclip-download:end -->/g)].map((match) => match[1]);
const htmlWithoutSynced = html.replace(/<!-- blinkclip-download:start -->[\s\S]*?<!-- blinkclip-download:end -->/g, '');
const releaseVersion = () => {
  const match = /data-release-version="([^"]*)"/.exec(html);
  assert.ok(match, 'the document must declare data-release-version');
  return match[1];
};
const regionLinks = () => syncedRegions.map((region) => [...region.matchAll(DMG_LINK)].map((match) => {
  assert.equal(match[1], match[2], `release tag and installer version disagree: ${match[0]}`);
  return match[0];
}));
const syncedLinks = () => regionLinks().flat();

check('versioned DMG links are pinned only inside the synchronized download markers', () => {
  assert.equal(html.split('<!-- blinkclip-download:start -->').length - 1, 2, 'hero and CTA markers');
  assert.equal(html.split('<!-- blinkclip-download:end -->').length - 1, 2, 'hero and CTA markers');
  assert.equal(syncedRegions.length, 2);
  assert.ok(!/BlinkClip-\d+\.\d+\.\d+-macos-universal\.dmg/.test(htmlWithoutSynced),
    'hand-written markup must not pin an installer version');
  assert.ok(!/releases\/download\//.test(htmlWithoutSynced), 'hand-written markup must not pin a download URL');
});

check('hero and CTA download links target the latest release or its synchronized DMG', () => {
  const links = [...html.matchAll(/class="button" href="([^"]+)"/g)].map((match) => match[1]);
  assert.equal(links.length, 2);
  const pinned = syncedLinks();
  if (pinned.length === 0) {
    assert.equal(releaseVersion(), '', 'a site without a published installer must not claim a release version');
    for (const link of links) assert.ok([LATEST_RELEASE, `${RELEASE_BASE}/releases`].includes(link), link);
    return;
  }
  for (const link of links) assert.ok(link === LATEST_RELEASE || link === pinned[0], link);
});

check('synchronized markers hold exactly one DMG link each, identical and matching the release version', () => {
  const links = syncedLinks();
  if (links.length === 0) {
    assert.equal(releaseVersion(), '', 'no installer is only allowed together with an empty release version');
    return;
  }
  for (const urls of regionLinks()) assert.equal(urls.length, 1, 'each synchronized region carries exactly one DMG link');
  assert.equal(new Set(links).size, 1, `both synchronized regions must share one DMG link: ${links.join(', ')}`);
  assert.equal(`v${releaseVersion()}`, /download\/(v\d+\.\d+\.\d+)\//.exec(links[0])[1],
    'data-release-version must match the synchronized DMG');
});
console.log(JSON.stringify({ passed: true, checks, translation_keys: Object.keys(messages.en).length }));
