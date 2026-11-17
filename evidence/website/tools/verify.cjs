// Verify language switching, accordion state, overflow and target sizes in a real Chrome page.
// Usage: node evidence/website/tools/verify.cjs <baseUrl> <outDir>
const fs = require('node:fs');
const path = require('node:path');

const [baseUrl, outDir] = process.argv.slice(2);
const endpoint = process.env.CHROME_DEBUG_URL || 'http://127.0.0.1:9222';
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
      if (message.error) reject(new Error(message.error.message));
      else resolve(message.result);
      return;
    }
    if (message.method && listeners.has(message.method)) {
      for (const listener of listeners.get(message.method)) listener(message.params);
      listeners.delete(message.method);
    }
  });
  const send = (method, params = {}, sessionId) => new Promise((resolve, reject) => {
    const id = ++nextId;
    pending.set(id, { resolve, reject });
    socket.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
  });
  const once = (method) => new Promise((resolve) => {
    if (!listeners.has(method)) listeners.set(method, []);
    listeners.get(method).push(resolve);
  });
  return { socket, send, once };
}

async function main() {
  fs.mkdirSync(outDir, { recursive: true });
  const { socket, send, once } = await connect();
  const { targetId } = await send('Target.createTarget', { url: 'about:blank' });
  const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
  await send('Page.enable', {}, sessionId);
  await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false }, sessionId);
  await send('Page.addScriptToEvaluateOnNewDocument', {
    source: `window.__errors = []; window.addEventListener('error', (event) => window.__errors.push(String(event.message))); window.addEventListener('unhandledrejection', (event) => window.__errors.push(String(event.reason)));`
  }, sessionId);
  const loaded = once('Page.loadEventFired');
  await send('Page.navigate', { url: baseUrl }, sessionId);
  await loaded;
  await sleep(1400);

  const evaluate = async (expression) => (await send('Runtime.evaluate', {
    expression, awaitPromise: true, returnByValue: true
  }, sessionId)).result.value;

  const scrollThrough = () => evaluate(`(async () => {
    const root = document.documentElement;
    const previous = root.style.scrollBehavior;
    root.style.scrollBehavior = 'auto';
    const step = Math.round(window.innerHeight * 0.75);
    for (let y = 0; y < root.scrollHeight; y += step) {
      window.scrollTo(0, y);
      await new Promise((resolve) => setTimeout(resolve, 110));
    }
    window.scrollTo(0, root.scrollHeight);
    await new Promise((resolve) => setTimeout(resolve, 400));
    window.scrollTo(0, 0);
    await new Promise((resolve) => setTimeout(resolve, 300));
    root.style.scrollBehavior = previous;
  })()`);

  const snapshot = () => evaluate(`(() => {
    const doc = document.documentElement;
    const active = document.querySelector('[data-language][aria-pressed="true"]');
    const h1 = document.querySelector('#hero-title');
    return {
      htmlLang: doc.lang,
      title: document.title,
      ogLocale: document.querySelector('meta[property="og:locale"]').content,
      stored: localStorage.getItem('blinkclip.website.language'),
      pressed: active ? active.dataset.language : null,
      h1: h1 ? h1.textContent.replace(/\\s+/g, ' ').trim() : null,
      download: document.querySelector('.button')?.textContent.replace(/\\s+/g, ' ').trim(),
      imageAlt: document.querySelector('.hero-shot img')?.getAttribute('alt'),
      trigger: document.querySelector('#language-trigger')?.getAttribute('aria-label'),
      overflow: doc.scrollWidth > doc.clientWidth,
      faqOpen: document.querySelector('.faq-item')?.dataset.open,
      faqExpanded: document.querySelector('.faq-trigger')?.getAttribute('aria-expanded')
    };
  })()`);

  const zh = await snapshot();
  const errors = await evaluate('window.__errors');
  const motion = await evaluate(`(() => ({
    gsap: Boolean(window.gsap),
    scrollTrigger: Boolean(window.ScrollTrigger),
    heroInlineStyle: document.querySelector('.hero-copy')?.children[0]?.getAttribute('style'),
    shotInlineStyle: document.querySelector('.hero-shot')?.getAttribute('style'),
    reduced: matchMedia('(prefers-reduced-motion: reduce)').matches
  }))()`);
  await evaluate(`document.querySelector('[data-language="en"]').click()`);
  await sleep(500);
  await scrollThrough();
  const en = await snapshot();
  const stats = await evaluate(`[...document.querySelectorAll('.stat-value')].map((el) => el.textContent)`);
  const enViewport = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false }, sessionId);
  fs.writeFileSync(path.join(outDir, 'en-1440x900.png'), Buffer.from(enViewport.data, 'base64'));
  const layout = await send('Page.getLayoutMetrics', {}, sessionId);
  const enFull = await send('Page.captureScreenshot', {
    format: 'png', captureBeyondViewport: true,
    clip: { x: 0, y: 0, width: layout.cssContentSize.width, height: layout.cssContentSize.height, scale: 1 }
  }, sessionId);
  fs.writeFileSync(path.join(outDir, 'en-1440-full.png'), Buffer.from(enFull.data, 'base64'));

  await send('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: true }, sessionId);
  await sleep(500);
  await scrollThrough();
  const mobileEn = await evaluate(`(() => {
    const doc = document.documentElement;
    const wide = [...document.querySelectorAll('body *')].filter((el) => {
      const r = el.getBoundingClientRect();
      return r.width > 0 && (r.right > doc.clientWidth + 1 || r.left < -1);
    }).slice(0, 8).map((el) => typeof el.className === 'string' ? el.className : el.tagName);
    const cta = document.querySelector('.cta-actions .button').getBoundingClientRect();
    const targets = [...document.querySelectorAll('a.button, .pill-link, .pill-cta, .language-trigger, .faq-trigger, .cta-github')].map((el) => {
      const r = el.getBoundingClientRect();
      return { label: (el.textContent || '').trim().slice(0, 20), w: Math.round(r.width), h: Math.round(r.height) };
    }).filter((t) => t.w < 44 || t.h < 44);
    return {
      overflow: doc.scrollWidth > doc.clientWidth,
      scrollWidth: doc.scrollWidth,
      clientWidth: doc.clientWidth,
      heroBottom: Math.round(document.querySelector('.hero').getBoundingClientRect().bottom),
      wide,
      cta: { w: Math.round(cta.width), h: Math.round(cta.height) },
      smallTargets: targets
    };
  })()`);
  const mobileShot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false }, sessionId);
  fs.writeFileSync(path.join(outDir, 'en-390x844.png'), Buffer.from(mobileShot.data, 'base64'));

  await evaluate(`document.querySelector('[data-language="system"]').click()`);
  await sleep(400);
  const system = await snapshot();

  await evaluate(`document.querySelector('[data-language="zh-Hans"]').click()`);
  await sleep(300);
  await evaluate(`document.querySelector('.faq-trigger').click()`);
  await sleep(700);
  const faq = await snapshot();
  const faqHeight = await evaluate(`document.querySelector('.faq-inner').getBoundingClientRect().height`);
  await evaluate(`(() => {
    document.documentElement.style.scrollBehavior = 'auto';
    document.querySelector('#faq').scrollIntoView({ block: 'start' });
  })()`);
  await sleep(700);
  const faqShot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false }, sessionId);
  fs.writeFileSync(path.join(outDir, 'faq-open-390x844.png'), Buffer.from(faqShot.data, 'base64'));

  await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-reduced-motion', value: 'reduce' }] }, sessionId);
  const reducedLoaded = once('Page.loadEventFired');
  await send('Page.reload', {}, sessionId);
  await reducedLoaded;
  await sleep(900);
  const reduced = await evaluate(`({
    media: matchMedia('(prefers-reduced-motion: reduce)').matches,
    shotInlineStyle: document.querySelector('.hero-shot').getAttribute('style'),
    gsap: Boolean(window.gsap)
  })`);
  await send('Emulation.setEmulatedMedia', { features: [] }, sessionId);

  const report = { zh, en, errors, motion, stats, reduced, mobileEn, system, faq, faqHeight };
  fs.writeFileSync(path.join(outDir, 'verify.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
  await send('Target.closeTarget', { targetId });
  socket.close();
}

main().catch((error) => { console.error(error); process.exit(1); });
