// Online gate test: two browsers play each other through the real signaling server and real WebRTC.
// Each side adds LAG ms to its outgoing input packets (?lag=), so the round trip is ~2*LAG plus the
// real local latency, and LOSS of them are dropped. Both sides mash random inputs for SECONDS.
// Pass = no desync, every checked frame matches, and the game didn't stall.
//
// Usage: node tests/web/online_test.js http://127.0.0.1:8070 out_dir [lag_ms=75] [loss=0.01] [seconds=60]
// Needs the web build served at the URL and the server (uvicorn app:app --port 8000) running.
const { chromium } = require('playwright');
const fs = require('fs');

const url = process.argv[2] || 'http://127.0.0.1:8070';
const out = process.argv[3] || '.';
const LAG = +(process.argv[4] || 75);
const LOSS = +(process.argv[5] || 0.01);
const SECONDS = +(process.argv[6] || 60);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function openPlayer(name) {
  // Separate browsers so neither page is a throttled background tab.
  const browser = await chromium.launch({
    args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
      // Let WebRTC use plain local IPs (mDNS .local names don't resolve in this container).
      '--disable-features=WebRtcHideLocalIpsWithMdns'],
  });
  // Small viewport: software WebGL renders faster, so the game keeps up with real time.
  const vw = +(process.env.VIEW_W || 640);
  const page = await browser.newPage({ viewport: { width: vw, height: Math.round(vw * 9 / 16) } });
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => {
    const t = m.text();
    if (m.type() === 'error' && !/still waiting|dependency:|end of list|dummy PhysicsServer/.test(t)) errors.push(t);
    if (/DESYNC/.test(t)) errors.push(t);
  });
  await page.goto(`${url}/?lag=${LAG}&loss=${LOSS}`);
  await page.waitForFunction(() => window.qfEngineReadyAt !== undefined, null, { timeout: 120000 });
  return { name, browser, page, errors };
}

async function press(page, key, wait = 200) {
  await page.keyboard.press(key);
  await sleep(wait);
}

// Title -> Mode menu -> "Online" (3rd item) -> pick Arghya -> Online menu.
async function toOnlineMenu(page) {
  await press(page, 'KeyJ', 700);
  await press(page, 'KeyS');
  await press(page, 'KeyS');
  await press(page, 'KeyJ', 400);
  await press(page, 'KeyJ', 400);
}

// Random "button masher": hold a direction and sometimes a button, change every 50-250 ms.
async function mash(page, untilMs) {
  const dirs = ['', 'KeyA', 'KeyD', 'KeyS', 'KeyW'];
  const buttons = ['', '', 'KeyJ', 'KeyK', 'KeyU', 'KeyI'];
  const held = new Set();
  while (Date.now() < untilMs) {
    const want = new Set([dirs[Math.floor(Math.random() * dirs.length)], buttons[Math.floor(Math.random() * buttons.length)]]);
    want.delete('');
    for (const k of held) if (!want.has(k)) { await page.keyboard.up(k); held.delete(k); }
    for (const k of want) if (!held.has(k)) { await page.keyboard.down(k); held.add(k); }
    await sleep(50 + Math.random() * 200);
  }
  for (const k of held) await page.keyboard.up(k);
}

(async () => {
  const host = await openPlayer('host');
  const guest = await openPlayer('guest');
  await toOnlineMenu(host.page);
  await toOnlineMenu(guest.page);

  // Host: "Create room" (2nd item). Guest: "Join room" (3rd item) answers the browser prompt.
  await press(host.page, 'KeyS');
  await press(host.page, 'KeyJ', 500);
  await host.page.waitForFunction(() => window.qfRoomCode, null, { timeout: 15000 });
  const code = await host.page.evaluate(() => window.qfRoomCode);
  console.log('room code', code);
  await host.page.screenshot({ path: `${out}/online-1-room-code.png` });
  guest.page.on('dialog', (d) => d.accept(code));
  await press(guest.page, 'KeyS');
  await press(guest.page, 'KeyS');
  await press(guest.page, 'KeyJ', 500);

  // Wait for the fight on both sides (qfStats appears once a fight screen runs).
  for (const p of [host, guest]) {
    await p.page.waitForFunction(() => window.qfStats && window.qfStats.ticks > 0, null, { timeout: 40000 });
  }
  console.log('fight started; playing for', SECONDS, 's at +', LAG, 'ms each way,', LOSS * 100, '% loss');
  const started = Date.now();
  const until = started + SECONDS * 1000;
  const samples = [];
  const sampler = (async () => {
    while (Date.now() < until) {
      await sleep(5000);
      const s = await Promise.all([host.page.evaluate(() => window.qfStats), guest.page.evaluate(() => window.qfStats)]);
      samples.push({ t: Math.round((Date.now() - started) / 1000), host: s[0], guest: s[1] });
      console.log(`${samples.at(-1).t}s  host: frame ${s[0].frame} fps ${s[0].fps} rtt ${s[0].rtt} rb ${s[0].rollbacks} (max ${s[0].max_rollback}) stalls ${s[0].stalls} | guest: frame ${s[1].frame} fps ${s[1].fps} rtt ${s[1].rtt} rb ${s[1].rollbacks} (max ${s[1].max_rollback}) stalls ${s[1].stalls}`);
    }
  })();
  await Promise.all([mash(host.page, until), mash(guest.page, until), sampler]);
  await host.page.screenshot({ path: `${out}/online-2-host.png` });
  await guest.page.screenshot({ path: `${out}/online-3-guest.png` });

  const final = await Promise.all([host.page.evaluate(() => window.qfStats), guest.page.evaluate(() => window.qfStats)]);
  const result = { lag_each_way_ms: LAG, loss: LOSS, seconds: SECONDS, code, host: final[0], guest: final[1],
    errors: { host: [...new Set(host.errors)].slice(0, 20), guest: [...new Set(guest.errors)].slice(0, 20) }, samples };
  fs.writeFileSync(`${out}/online_results.json`, JSON.stringify(result, null, 2));

  const checks = [
    ['no desync detected', final[0].desync === -1 && final[1].desync === -1],
    ['frames were cross-checked', final[0].checked > 10 && final[1].checked > 10],
    ['both sides in step', Math.abs(final[0].frame - final[1].frame) < 30],
    ['no page errors', host.errors.length === 0 && guest.errors.length === 0],
  ];
  for (const [name, ok] of checks) console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}`);
  await host.browser.close();
  await guest.browser.close();
  process.exit(checks.every((c) => c[1]) ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
