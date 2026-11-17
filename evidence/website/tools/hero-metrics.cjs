// Record first-screen hero geometry (heroBottom vs viewport height) and the
// rendered-vs-natural aspect of the product shot, in zh-Hans and English.
// Usage: node evidence/website/tools/hero-metrics.cjs <baseUrl> <outDir>
const fs = require('node:fs');
const path = require('node:path');

const [baseUrl, outDir] = process.argv.slice(2);
if (!baseUrl || !outDir) {
  console.error('Usage: hero-metrics.cjs <baseUrl> <outDir>');
  process.exit(2);
}
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
  socket.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const { resolve, reject } = pending.get(message.id);
      pending.delete(message.id);
      message.error ? reject(new Error(message.error.message)) : resolve(message.result);
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
  return { socket, send };
}

const METRICS_JS = `(() => {
  const rect = (selector) => {
    const el = document.querySelector(selector);
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { top: Math.round(r.top), bottom: Math.round(r.bottom), width: Math.round(r.width), height: Math.round(r.height) };
  };
  const hero = document.querySelector('.hero');
  const img = document.querySelector('.hero-shot img');
  const clip = getComputedStyle(hero).clipPath;
  const clipBottom = clip.includes('88%') ? Math.round(hero.getBoundingClientRect().height * 0.88) : null;
  return {
    lang: document.documentElement.lang,
    viewport: { width: innerWidth, height: innerHeight },
    heroBottom: Math.round(hero.getBoundingClientRect().bottom),
    heroFillsFirstScreen: Math.round(hero.getBoundingClientRect().bottom) === innerHeight,
    heroClipPath: clip,
    clipBottomAtRightEdge: clipBottom,
    shot: rect('.hero-shot'),
    image: rect('.hero-shot img'),
    imageNatural: { width: img.naturalWidth, height: img.naturalHeight },
    // offsetWidth/offsetHeight are the untransformed layout box (the card is rotated -1.2deg).
    imageLayout: { width: img.offsetWidth, height: img.offsetHeight },
    imageRenderedAspect: Math.round((img.offsetWidth / img.offsetHeight) * 100) / 100,
    imageNaturalAspect: Math.round((img.naturalWidth / img.naturalHeight) * 100) / 100,
    imageCropped: Math.abs(img.offsetWidth / img.offsetHeight - img.naturalWidth / img.naturalHeight) > 0.02,
    shotInsideDiagonalClip: clipBottom === null || Math.round(document.querySelector('.hero-shot').getBoundingClientRect().bottom) < clipBottom
  };
})()`;

async function main() {
  fs.mkdirSync(outDir, { recursive: true });
  const { socket, send } = await connect();
  const { targetId } = await send('Target.createTarget', { url: 'about:blank' });
  const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
  await send('Page.enable', {}, sessionId);
  const results = [];
  for (const [width, height] of [[1440, 900], [1024, 768], [390, 844]]) {
    await send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: width < 700 }, sessionId);
    await send('Page.navigate', { url: baseUrl }, sessionId);
    await sleep(2200);
    const zh = (await send('Runtime.evaluate', { expression: METRICS_JS, returnByValue: true }, sessionId)).result.value;
    results.push({ size: `${width}x${height}`, ...zh });
    await send('Runtime.evaluate', { expression: `document.querySelector('[data-language="en"]').click()` }, sessionId);
    await sleep(700);
    const en = (await send('Runtime.evaluate', { expression: METRICS_JS, returnByValue: true }, sessionId)).result.value;
    results.push({ size: `${width}x${height}`, ...en });
    await send('Runtime.evaluate', { expression: `document.querySelector('[data-language="system"]').click()` }, sessionId);
    await sleep(400);
  }
  const file = path.join(outDir, 'hero-metrics.json');
  fs.writeFileSync(file, JSON.stringify(results, null, 2));
  console.log(JSON.stringify(results.map((r) => ({
    size: r.size, lang: r.lang, viewport: r.viewport.height, heroBottom: r.heroBottom,
    fills: r.heroFillsFirstScreen, shotBottom: r.shot.bottom, clipEdge: r.clipBottomAtRightEdge,
    insideClip: r.shotInsideDiagonalClip, imageCropped: r.imageCropped,
    aspect: `${r.imageRenderedAspect} vs ${r.imageNaturalAspect}`
  })), null, 2));
  await send('Target.closeTarget', { targetId });
  socket.close();
}

main().catch((error) => { console.error(error); process.exit(1); });
