// Measure WCAG contrast of every `--accent-bright` text use on its real backdrop,
// and capture the dark sections (stats / cta / footer) for evidence.
// Usage: node evidence/website/tools/contrast-check.cjs <baseUrl> <outDir>
const fs = require('node:fs');
const path = require('node:path');

const [baseUrl, outDir] = process.argv.slice(2);
if (!baseUrl || !outDir) {
  console.error('Usage: node contrast-check.cjs <baseUrl> <outDir>');
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

const CONTRAST_JS = `(() => {
  const parse = (value) => {
    const m = String(value).match(/rgba?\\(([^)]+)\\)/);
    if (!m) return null;
    const parts = m[1].split(',').map((n) => parseFloat(n.trim()));
    return { r: parts[0], g: parts[1], b: parts[2], a: parts.length > 3 ? parts[3] : 1 };
  };
  const luminance = ({ r, g, b }) => {
    const channel = (v) => {
      const c = v / 255;
      return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    };
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
  };
  const contrast = (fgRaw, bg) => {
    const fg = fgRaw.a >= 0.999 ? fgRaw : {
      r: fgRaw.r * fgRaw.a + bg.r * (1 - fgRaw.a),
      g: fgRaw.g * fgRaw.a + bg.g * (1 - fgRaw.a),
      b: fgRaw.b * fgRaw.a + bg.b * (1 - fgRaw.a),
      a: 1
    };
    const a = luminance(fg), b = luminance(bg);
    return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
  };
  const backdrop = (el) => {
    let node = el;
    while (node && node !== document.documentElement) {
      const style = getComputedStyle(node);
      const parsed = parse(style.backgroundColor);
      if (parsed && parsed.a >= 0.98) return parsed;
      node = node.parentElement;
    }
    const body = parse(getComputedStyle(document.body).backgroundColor);
    return body && body.a >= 0.98 ? body : { r: 255, g: 255, b: 255, a: 1 };
  };
  const probes = [
    ['.stats .eyebrow', 'stats eyebrow'],
    ['.stat-row.is-focal .stat-value', 'focal stat value'],
    ['.cta .eyebrow', 'cta eyebrow'],
    ['.cta-title .accent', 'cta title accent'],
    ['.footer-link', 'footer link'],
    ['.cta-github', 'cta github link']
  ];
  return probes.map(([selector, label]) => {
    const el = document.querySelector(selector);
    if (!el) return { label, selector, missing: true };
    const style = getComputedStyle(el);
    const fg = parse(style.color);
    const bg = backdrop(el);
    return {
      label, selector,
      color: style.color,
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      backdrop: \`rgb(\${bg.r}, \${bg.g}, \${bg.b})\`,
      ratio: Math.round(contrast(fg, bg) * 100) / 100
    };
  });
})()`;

async function main() {
  fs.mkdirSync(outDir, { recursive: true });
  const { socket, send } = await connect();
  const { targetId } = await send('Target.createTarget', { url: 'about:blank' });
  const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
  await send('Page.enable', {}, sessionId);
  await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false }, sessionId);
  await send('Page.navigate', { url: baseUrl }, sessionId);
  await sleep(2400);
  await send('Runtime.evaluate', {
    expression: `(() => { const root = document.documentElement; root.style.scrollBehavior = 'auto';
      const step = Math.round(innerHeight * 0.75);
      for (let y = 0; y < root.scrollHeight; y += step) window.scrollTo(0, y);
      window.scrollTo(0, 0); })()`
  }, sessionId);
  await sleep(900);

  const probes = (await send('Runtime.evaluate', { expression: CONTRAST_JS, returnByValue: true }, sessionId)).result.value;

  const shots = {};
  for (const [selector, name] of [['#stats', 'stats-1440x900'], ['.cta', 'cta-1440x900']]) {
    await send('Runtime.evaluate', {
      expression: `(() => { document.documentElement.style.scrollBehavior = 'auto';
        document.querySelector(${JSON.stringify(selector)}).scrollIntoView({ block: 'start' }); })()`
    }, sessionId);
    await sleep(900);
    const shot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false }, sessionId);
    const file = path.join(outDir, `${name}.png`);
    fs.writeFileSync(file, Buffer.from(shot.data, 'base64'));
    shots[name] = file;
  }
  await send('Runtime.evaluate', { expression: 'window.scrollTo(0, 0)' }, sessionId);

  const report = { probes, shots };
  fs.writeFileSync(path.join(outDir, 'contrast.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
  await send('Target.closeTarget', { targetId });
  socket.close();
}

main().catch((error) => { console.error(error); process.exit(1); });
