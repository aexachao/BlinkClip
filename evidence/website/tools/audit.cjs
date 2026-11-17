// Measure a served copy of the landing page through the Chrome DevTools Protocol:
// first-screen geometry, horizontal overflow, screenshot density, target sizes,
// reduced-motion visibility and on-page character counts.
// Usage: node evidence/website/tools/audit.cjs <baseUrl> <prefix> <outDir> [--shots]
const fs = require('node:fs');
const path = require('node:path');

const [baseUrl, prefix, outDir, ...flags] = process.argv.slice(2);
if (!baseUrl || !prefix || !outDir) {
  console.error('Usage: node audit.cjs <baseUrl> <prefix> <outDir> [--shots]');
  process.exit(2);
}
const takeShots = flags.includes('--shots');
const endpoint = process.env.CHROME_DEBUG_URL || 'http://127.0.0.1:9222';
const SIZES = [[1440, 900], [1024, 768], [768, 1024], [390, 844], [320, 568]];
const SHOT_SIZES = new Set(['1440x900', '1024x768', '390x844']);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function connect() {
  const { webSocketDebuggerUrl } = await (await fetch(`${endpoint}/json/version`)).json();
  const socket = new WebSocket(webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.addEventListener('open', resolve, { once: true });
    socket.addEventListener('error', reject, { once: true });
  });
  let nextId = 0;
  const pending = new Map();
  const listeners = new Map();
  socket.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const { resolve, reject } = pending.get(message.id);
      pending.delete(message.id);
      message.error ? reject(new Error(message.error.message)) : resolve(message.result);
      return;
    }
    if (message.method && listeners.has(message.method)) {
      for (const listener of listeners.get(message.method)) listener(message.params);
      listeners.delete(message.method);
    }
  });
  const send = (method, params = {}, sessionId) => new Promise((resolve, reject) => {
    const id = ++nextId;
    const timer = setTimeout(() => {
      if (pending.has(id)) { pending.delete(id); reject(new Error(`CDP timeout: ${method}`)); }
    }, 45000);
    pending.set(id, {
      resolve: (value) => { clearTimeout(timer); resolve(value); },
      reject: (error) => { clearTimeout(timer); reject(error); }
    });
    socket.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
  });
  const once = (method) => new Promise((resolve) => {
    if (!listeners.has(method)) listeners.set(method, []);
    listeners.get(method).push(resolve);
  });
  return { socket, send, once };
}

const METRICS = `(() => {
  const doc = document.documentElement;
  const text = document.body.innerText;
  const cjk = (text.match(/[\\u3000-\\u303f\\u4e00-\\u9fff\\uff00-\\uffef]/g) || []).length;
  const hero = document.querySelector('.hero');
  const heroRect = hero.getBoundingClientRect();
  const title = document.querySelector('#hero-title');
  const titleStyle = title ? getComputedStyle(title) : null;
  const lineHeight = titleStyle ? parseFloat(titleStyle.lineHeight) : 0;
  const shots = [...document.querySelectorAll('.hero-shot img, .shot img')].map((img) => {
    const rect = img.getBoundingClientRect();
    return {
      src: img.getAttribute('src'),
      css: Math.round(rect.width),
      natural: img.naturalWidth,
      density: Math.round((img.naturalWidth / Math.max(rect.width, 1)) * 100) / 100
    };
  });
  const targets = [...document.querySelectorAll('a.button, .hero-secondary, .pill-link, .pill-cta, .language-trigger, .faq-trigger')]
    .map((el) => {
      const rect = el.getBoundingClientRect();
      return { label: (el.textContent || el.getAttribute('aria-label') || '').trim().slice(0, 18), w: Math.round(rect.width), h: Math.round(rect.height) };
    })
    .filter((target) => target.w > 0 && target.h > 0);
  const overflow = [...document.querySelectorAll('body *')]
    .filter((el) => {
      const rect = el.getBoundingClientRect();
      const style = getComputedStyle(el);
      if (style.position === 'fixed' || style.display === 'none' || style.visibility === 'hidden') return false;
      return rect.width > 0 && (rect.right > innerWidth + 1 || rect.left < -1);
    })
    .slice(0, 6)
    .map((el) => el.className || el.tagName);
  const lineWraps = [...document.querySelectorAll('.line-wrap')].map((wrap) => {
    const inner = wrap.firstElementChild;
    return {
      text: (inner ? inner.textContent : '').trim().slice(0, 24),
      wrapped: inner ? inner.getBoundingClientRect().height > wrap.getBoundingClientRect().height + 1 : false
    };
  });
  return {
    lang: doc.lang,
    viewport: { width: innerWidth, height: innerHeight },
    heroBottom: Math.round(heroRect.bottom),
    heroFillsScreen: Math.round(heroRect.bottom) === innerHeight,
    heroHeight: Math.round(heroRect.height),
    contentHeight: Math.round(Math.max(doc.scrollHeight, document.body.scrollHeight)),
    scrollWidth: doc.scrollWidth,
    clientWidth: doc.clientWidth,
    horizontalOverflow: overflow,
    characters: { cjk, total: text.replace(/\\s+/g, '').length },
    heroTitle: {
      height: Math.round(title.getBoundingClientRect().height),
      lines: lineHeight ? Math.round(title.getBoundingClientRect().height / lineHeight) : null
    },
    titleLines: lineWraps,
    shots,
    targets,
    smallTargets: targets.filter((target) => target.w < 44 || target.h < 44),
    sections: [...document.querySelectorAll('main section')].map((section) => ({
      id: section.id, height: Math.round(section.getBoundingClientRect().height)
    }))
  };
})()`;

const SCROLL = `(async () => {
  const root = document.documentElement;
  const previous = root.style.scrollBehavior;
  root.style.scrollBehavior = 'auto';
  const step = Math.round(window.innerHeight * 0.6);
  for (let y = 0; y < root.scrollHeight; y += step) {
    window.scrollTo(0, y);
    await new Promise((resolve) => setTimeout(resolve, 90));
  }
  window.scrollTo(0, 0);
  await new Promise((resolve) => setTimeout(resolve, 400));
  root.style.scrollBehavior = previous;
})()`;

const REDUCED = `(() => {
  const hero = document.querySelector('.hero');
  const children = [...hero.querySelectorAll('h1, .hero-lede, .hero-meta, .hero-actions, .hero-shot')];
  return children.map((el) => {
    const style = getComputedStyle(el);
    const rect = el.getBoundingClientRect();
    return { tag: el.className, opacity: style.opacity, visibility: style.visibility, height: Math.round(rect.height) };
  });
})()`;

async function main() {
  fs.mkdirSync(outDir, { recursive: true });
  const { socket, send, once } = await connect();
  const results = [];
  for (const [width, height] of SIZES) {
    const size = `${width}x${height}`;
    const { targetId } = await send('Target.createTarget', { url: 'about:blank' });
    const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
    await send('Page.enable', {}, sessionId);
    await send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: width < 700 }, sessionId);
    const loaded = once('Page.loadEventFired');
    await send('Page.navigate', { url: baseUrl }, sessionId);
    await loaded.catch(() => {});
    await sleep(1800);
    await send('Runtime.evaluate', { expression: 'document.fonts && document.fonts.ready', awaitPromise: true }, sessionId);
    await send('Runtime.evaluate', { expression: SCROLL, awaitPromise: true }, sessionId);
    await sleep(400);
    const zh = (await send('Runtime.evaluate', { expression: METRICS, returnByValue: true }, sessionId)).result.value;
    results.push({ size, ...zh });

    const reduced = await (async () => {
      await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-reduced-motion', value: 'reduce' }] }, sessionId);
      await send('Page.navigate', { url: baseUrl }, sessionId);
      await sleep(1400);
      const value = (await send('Runtime.evaluate', { expression: REDUCED, returnByValue: true }, sessionId)).result.value;
      await send('Emulation.setEmulatedMedia', { features: [] }, sessionId);
      return value;
    })();
    results[results.length - 1].reducedMotion = reduced;
    results[results.length - 1].reducedVisible = reduced.every((item) => item.opacity === '1' && item.visibility === 'visible' && item.height > 0);

    if (takeShots && SHOT_SIZES.has(size)) {
      await send('Page.navigate', { url: baseUrl }, sessionId);
      await sleep(1700);
      await send('Runtime.evaluate', { expression: SCROLL, awaitPromise: true }, sessionId);
      await sleep(400);
      const shot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false }, sessionId);
      fs.writeFileSync(path.join(outDir, `${prefix}-${size}.png`), Buffer.from(shot.data, 'base64'));
      const layout = await send('Page.getLayoutMetrics', {}, sessionId);
      const content = layout.cssContentSize;
      const full = await send('Page.captureScreenshot', {
        format: 'png', captureBeyondViewport: true,
        clip: { x: 0, y: 0, width: content.width, height: content.height, scale: 1 }
      }, sessionId);
      fs.writeFileSync(path.join(outDir, `${prefix}-${size}-full.png`), Buffer.from(full.data, 'base64'));
    }
    await send('Target.closeTarget', { targetId });
  }
  fs.writeFileSync(path.join(outDir, `${prefix}-audit.json`), JSON.stringify(results, null, 2));
  socket.close();
  console.log(JSON.stringify(results.map((r) => ({
    size: r.size,
    viewportHeight: r.viewport.height,
    heroBottom: r.heroBottom,
    heroFillsScreen: r.heroFillsScreen,
    contentHeight: r.contentHeight,
    horizontalOverflow: r.scrollWidth > r.clientWidth || r.horizontalOverflow.length > 0,
    overflowNodes: r.horizontalOverflow,
    characters: r.characters,
    heroTitleLines: r.heroTitle.lines,
    smallTargets: r.smallTargets,
    reducedVisible: r.reducedVisible,
    shots: r.shots.map((s) => `${s.src.split('/').pop()} ${s.css}px@${s.density}x`)
  })), null, 2));
}

main().catch((error) => { console.error(error); process.exit(1); });
