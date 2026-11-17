// Capture deterministic viewport/full-page screenshots and layout facts through the Chrome DevTools Protocol.
// Usage: node evidence/website/tools/shots.cjs <baseUrl> <outDir> <width>x<height> [<width>x<height> ...]
const fs = require('node:fs');
const path = require('node:path');

const [baseUrl, outDir, ...sizes] = process.argv.slice(2);
if (!baseUrl || !outDir || sizes.length === 0) {
  console.error('Usage: node shots.cjs <baseUrl> <outDir> <width>x<height> ...');
  process.exit(2);
}

const endpoint = process.env.CHROME_DEBUG_URL || 'http://127.0.0.1:9222';

async function connect() {
  const response = await fetch(`${endpoint}/json/version`);
  if (!response.ok) throw new Error(`Chrome debug endpoint unavailable: ${response.status}`);
  const { webSocketDebuggerUrl } = await response.json();
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

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function main() {
  fs.mkdirSync(outDir, { recursive: true });
  const { socket, send, once } = await connect();
  const facts = [];
  for (const size of sizes) {
    const [width, height] = size.split('x').map(Number);
    if (!width || !height) throw new Error(`Bad size: ${size}`);
    const { targetId } = await send('Target.createTarget', { url: 'about:blank' });
    const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
    await send('Page.enable', {}, sessionId);
    await send('Emulation.setDeviceMetricsOverride', {
      width, height, deviceScaleFactor: 1, mobile: width < 700
    }, sessionId);
    const loaded = once('Page.loadEventFired');
    await send('Page.navigate', { url: baseUrl }, sessionId);
    await loaded;
    await sleep(1600);
    await send('Runtime.evaluate', { expression: 'document.fonts && document.fonts.ready', awaitPromise: true }, sessionId);
    await sleep(300);
    await send('Runtime.evaluate', {
      expression: `(async () => {
        const root = document.documentElement;
        const previous = root.style.scrollBehavior;
        root.style.scrollBehavior = 'auto';
        const step = Math.round(window.innerHeight * 0.75);
        for (let y = 0; y < root.scrollHeight; y += step) {
          window.scrollTo(0, y);
          await new Promise((resolve) => setTimeout(resolve, 120));
        }
        window.scrollTo(0, root.scrollHeight);
        await new Promise((resolve) => setTimeout(resolve, 500));
        window.scrollTo(0, 0);
        await new Promise((resolve) => setTimeout(resolve, 500));
        root.style.scrollBehavior = previous;
      })()`, awaitPromise: true
    }, sessionId);

    const metrics = await send('Runtime.evaluate', {
      expression: `(() => {
        const doc = document.documentElement;
        const images = [...document.images].map((img) => ({
          src: img.getAttribute('src'), width: img.naturalWidth, complete: img.complete
        }));
        const buttons = [...document.querySelectorAll('a.button, .pill-link, .pill-cta, .language-trigger, .hero-secondary, .v-a-trigger')].map((el) => {
          const r = el.getBoundingClientRect();
          return { label: (el.textContent || el.getAttribute('aria-label') || '').trim().slice(0, 24), w: Math.round(r.width), h: Math.round(r.height) };
        });
        const hero = document.querySelector('.hero');
        const heroRect = hero ? hero.getBoundingClientRect() : null;
        return {
          scrollWidth: doc.scrollWidth, clientWidth: doc.clientWidth,
          scrollHeight: doc.scrollHeight,
          heroBottom: heroRect ? Math.round(heroRect.bottom) : null,
          heroTop: heroRect ? Math.round(heroRect.top) : null,
          images, buttons,
          title: document.title,
          lang: doc.lang
        };
      })()`, returnByValue: true
    }, sessionId);
    const value = metrics.result.value;

    const viewport = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false }, sessionId);
    fs.writeFileSync(path.join(outDir, `${size}.png`), Buffer.from(viewport.data, 'base64'));

    const layout = await send('Page.getLayoutMetrics', {}, sessionId);
    const content = layout.cssContentSize;
    const full = await send('Page.captureScreenshot', {
      format: 'png', captureBeyondViewport: true,
      clip: { x: 0, y: 0, width: content.width, height: content.height, scale: 1 }
    }, sessionId);
    fs.writeFileSync(path.join(outDir, `${size}-full.png`), Buffer.from(full.data, 'base64'));

    facts.push({ size, ...value, contentHeight: Math.round(content.height) });
    await send('Target.closeTarget', { targetId });
  }
  fs.writeFileSync(path.join(outDir, 'facts.json'), JSON.stringify(facts, null, 2));
  socket.close();
  console.log(JSON.stringify(facts.map((f) => ({
    size: f.size, scrollWidth: f.scrollWidth, clientWidth: f.clientWidth,
    heroBottom: f.heroBottom, contentHeight: f.contentHeight,
    brokenImages: f.images.filter((img) => !img.complete || img.width === 0).map((img) => img.src),
    smallTargets: f.buttons.filter((b) => b.w < 44 || b.h < 44)
  })), null, 2));
}

main().catch((error) => { console.error(error); process.exit(1); });
