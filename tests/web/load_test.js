// Week 1 gate check: time from opening the link to the title screen, under emulated network/CPU.
// Then plays into a CPU fight and screenshots it. Usage: node tests/web/load_test.js http://127.0.0.1:8060 out_dir
// Note: emulation in desktop Chromium (software WebGL), not a real phone. Real-device testing is still required.
const { chromium } = require('playwright');
const fs = require('fs');
const url = process.argv[2] || 'http://127.0.0.1:8060';
const out = process.argv[3] || '.';

const PROFILES = [
  { name: 'desktop (no throttling)', net: null, cpu: 1 },
  { name: '4G typical (10 Mbps, 70 ms RTT) + mid-range CPU (4x slower)', net: { down: 10e6, up: 3e6, rtt: 70 }, cpu: 4 },
  { name: '4G weak (4 Mbps, 100 ms RTT) + mid-range CPU (4x slower)', net: { down: 4e6, up: 1e6, rtt: 100 }, cpu: 4 },
];

async function timeToTitle(browser, p) {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  const page = await ctx.newPage();
  const cdp = await ctx.newCDPSession(page);
  await cdp.send('Network.enable');
  await cdp.send('Network.setCacheDisabled', { cacheDisabled: true });
  if (p.net) {
    await cdp.send('Network.emulateNetworkConditions', {
      offline: false, latency: p.net.rtt,
      downloadThroughput: p.net.down / 8, uploadThroughput: p.net.up / 8,
    });
  }
  if (p.cpu > 1) await cdp.send('Emulation.setCPUThrottlingRate', { rate: p.cpu });
  let bytes = 0;
  cdp.on('Network.dataReceived', (e) => { bytes += e.encodedDataLength; });
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await page.goto(url, { waitUntil: 'commit' });
  await page.waitForFunction(() => window.qfTitleShownAt !== undefined, null, { timeout: 120000 });
  const ms = await page.evaluate(() => window.qfTitleShownAt);
  return { ctx, page, ms, bytes, errors };
}

(async () => {
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const results = [];
  for (const p of PROFILES) {
    const r = await timeToTitle(browser, p);
    results.push({ profile: p.name, ms: Math.round(r.ms), mb: +(r.bytes / 1e6).toFixed(2), errors: r.errors });
    console.log(`${p.name}: title screen after ${(r.ms / 1000).toFixed(2)} s, ${(r.bytes / 1e6).toFixed(2)} MB transferred`);
    if (p.cpu === 1) {
      const page = r.page;
      await page.waitForTimeout(800);
      await page.screenshot({ path: `${out}/1-title.png` });
      await page.mouse.click(640, 360);       // focus the canvas
      const press = async (k, wait = 250) => { await page.keyboard.press(k); await page.waitForTimeout(wait); };
      await page.waitForTimeout(300);
      await press('KeyJ');                     // title -> mode
      await page.screenshot({ path: `${out}/2-mode.png` });
      await press('KeyJ');                     // Versus CPU -> level
      await press('KeyJ');                     // Senior Designer -> select
      await page.screenshot({ path: `${out}/3-select.png` });
      await press('KeyJ');                     // P1 Arghya
      await press('KeyJ');                     // opponent Jitu
      await page.waitForTimeout(2200);
      await page.screenshot({ path: `${out}/4-fight-start.png` });
      // Walk in and attack for a few seconds.
      await page.keyboard.down('KeyD');
      await page.waitForTimeout(700);
      for (let i = 0; i < 6; i++) {
        await press('KeyJ', 90); await press('KeyK', 260);
      }
      await page.keyboard.up('KeyD');
      await page.screenshot({ path: `${out}/5-fight.png` });
      await press('F1', 400);                  // hitbox view
      await page.screenshot({ path: `${out}/6-hitboxes.png` });
      await page.waitForTimeout(3000);
      const stats = await page.evaluate(() => window.qfStats);
      results[0].fight_stats = stats;
      console.log('fight stats (software WebGL, unthrottled):', JSON.stringify(stats));
      await press('Escape', 400);
      await page.screenshot({ path: `${out}/7-pause.png` });
    }
    if (r.errors.length) console.log('  page errors:', r.errors.slice(0, 5));
    await r.ctx.close();
  }
  fs.writeFileSync(`${out}/load_results.json`, JSON.stringify(results, null, 2));
  await browser.close();
})();
