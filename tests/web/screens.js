// Screenshots of the art in the real web build: select screen and Training poses.
// Usage: node tests/web/screens.js http://127.0.0.1:8060 out_dir
const { chromium } = require('playwright');
const url = process.argv[2] || 'http://127.0.0.1:8060';
const out = process.argv[3] || '.';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
(async () => {
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  page.on('console', (m) => { if (m.type() === 'error' && !/still waiting|dependency|end of list/.test(m.text())) console.log('page error:', m.text()); });
  await page.goto(url);
  await page.waitForFunction(() => window.qfEngineReadyAt !== undefined, null, { timeout: 120000 });
  const press = async (k, wait = 250) => { await page.keyboard.press(k); await sleep(wait); };
  const shot = async (name) => { await page.screenshot({ path: `${out}/${name}.png` }); console.log('shot', name); };
  await press('KeyJ', 700);                                   // title -> mode
  for (let i = 0; i < 3; i++) await press('KeyS');            // Training
  await press('KeyJ', 600);
  await shot('select');
  await press('KeyJ', 400);                                   // P1 Arghya
  await press('KeyJ', 1500);                                  // dummy Jitu
  await shot('idle');
  await press('F5', 200);                                     // Training slow-motion (1/4 speed)
  // Hold a key combination for a moment, screenshot partway through the move.
  const move = async (name, keys, at) => {
    for (const k of keys) await page.keyboard.down(k);
    await sleep(40);
    for (const k of keys.slice().reverse()) await page.keyboard.up(k);
    await sleep(at);
    await shot(name);
    await sleep(2600);
  };
  await move('heavy-punch', ['KeyK'], 480);
  await move('heavy-kick', ['KeyI'], 640);
  await move('squeegee-swing', ['KeyD', 'KeyK'], 1150);
  await move('heat-press-palm', ['KeyS', 'KeyK'], 420);
  await move('sweep', ['KeyS', 'KeyI'], 600);
  await page.keyboard.down('KeyS'); await sleep(400); await shot('crouch'); await page.keyboard.up('KeyS');
  await sleep(400);
  await page.keyboard.down('KeyW'); await sleep(350); await shot('jump'); await page.keyboard.up('KeyW');
  await sleep(1000);
  await browser.close();
})();
