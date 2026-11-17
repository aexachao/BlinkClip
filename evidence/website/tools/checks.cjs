// Exercise the shipped page in a real Chrome: English hero fit at three widths,
// FAQ accordion state, language switching and console errors.
// Usage: node evidence/website/tools/checks.cjs <baseUrl> <outFile>
const fs = require('node:fs');

const [baseUrl, outFile] = process.argv.slice(2);
if (!baseUrl || !outFile) {
  console.error('Usage: checks.cjs <baseUrl> <outFile>');
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

const LAYOUT = `(() => {
  const doc = document.documentElement;
  const hero = document.querySelector('.hero').getBoundingClientRect();
  const title = document.querySelector('#hero-title');
  const lineHeight = parseFloat(getComputedStyle(title).lineHeight);
  return {
    lang: doc.lang,
    innerHeight,
    heroBottom: Math.round(hero.bottom),
    heroFillsScreen: Math.round(hero.bottom) === innerHeight,
    scrollWidth: doc.scrollWidth,
    clientWidth: doc.clientWidth,
    titleLines: Math.round(title.getBoundingClientRect().height / lineHeight),
    title: title.textContent.replace(/\\s+/g, ''),
    h1Height: Math.round(title.getBoundingClientRect().height),
    buttons: [...document.querySelectorAll('a.button, .hero-secondary')].map((el) => {
      const rect = el.getBoundingClientRect();
      return { label: el.textContent.trim().slice(0, 16), w: Math.round(rect.width), h: Math.round(rect.height) };
    }),
    downloadHref: document.querySelector('.hero-actions a.button').getAttribute('href')
  };
})()`;

async function evaluate(send, sessionId, expression) {
  const result = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true }, sessionId);
  return result.result.value;
}

async function main() {
  const { socket, send } = await connect();
  const { targetId } = await send('Target.createTarget', { url: 'about:blank' });
  const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
  await send('Page.enable', {}, sessionId);
  await send('Runtime.enable', {}, sessionId);
  const errors = [];
  socket.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (message.method === 'Runtime.exceptionThrown') errors.push(String(message.params?.exceptionDetails?.text));
  });

  const layout = [];
  for (const [width, height] of [[1440, 900], [1024, 768], [390, 844], [320, 568]]) {
    await send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: width < 700 }, sessionId);
    await send('Page.navigate', { url: baseUrl }, sessionId);
    await sleep(1500);
    await evaluate(send, sessionId, `document.querySelector('[data-language="en"]').click()`);
    await sleep(600);
    layout.push({ size: `${width}x${height}`, ...(await evaluate(send, sessionId, LAYOUT)) });
  }

  await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false }, sessionId);
  await send('Page.navigate', { url: baseUrl }, sessionId);
  await sleep(1500);

  const faq = await evaluate(send, sessionId, `(() => {
    const item = document.querySelector('.faq-item');
    const trigger = item.querySelector('.faq-trigger');
    trigger.click();
    const opened = { open: item.dataset.open, expanded: trigger.getAttribute('aria-expanded') };
    const second = document.querySelectorAll('.faq-trigger')[1];
    second.click();
    const exclusive = { first: item.dataset.open, second: second.getAttribute('aria-expanded') };
    second.click();
    return { opened, exclusive, closedAfterSecondToggle: second.getAttribute('aria-expanded') };
  })()`);

  const i18n = await evaluate(send, sessionId, `(() => {
    const read = () => ({
      lang: document.documentElement.lang,
      title: document.title,
      nav: document.querySelector('[href="#capture"] .pill-label').textContent,
      lede: document.querySelector('.hero-lede').textContent,
      alt: document.querySelector('.shot img').getAttribute('alt').slice(0, 40),
      pressed: document.querySelector('[data-language="en"]').getAttribute('aria-pressed')
    });
    const sign = document.querySelector('#language-trigger');
    const before = { lang: document.documentElement.lang, aria: sign.getAttribute('aria-label'), ...read() };
    document.querySelector('[data-language="en"]').click();
    const english = read();
    document.querySelector('[data-language="system"]').click();
    const back = { lang: document.documentElement.lang, pressed: document.querySelector('[data-language="system"]').getAttribute('aria-pressed') };
    return { before, english, back, stored: localStorage.getItem('blinkclip.website.language') };
  })()`);

  const report = { layout, faq, i18n, errors };
  fs.writeFileSync(outFile, JSON.stringify(report, null, 2));
  console.log(JSON.stringify({
    layout: layout.map((item) => ({
      size: item.size, lang: item.lang, fill: item.heroFillsScreen, overflow: item.scrollWidth > item.clientWidth,
      lines: item.titleLines, title: item.title, smallButtons: item.buttons.filter((b) => b.h < 44)
    })),
    faq, i18n: { englishTitle: i18n.english.title, nav: i18n.english.nav, alt: i18n.english.alt, backLang: i18n.back.lang },
    errors
  }, null, 2));
  await send('Target.closeTarget', { targetId });
  socket.close();
}

main().catch((error) => { console.error(error); process.exit(1); });
