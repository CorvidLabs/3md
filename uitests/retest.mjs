import { webkit } from 'playwright';
import fs from 'fs';

const URL = 'https://corvidlabs.github.io/3md/embed-example.html?theme=dark';
const examples = JSON.parse(fs.readFileSync('/tmp/all-examples.json', 'utf8'));

// Adversarial sampling: more than the original 44. Take every ~4th = ~68, plus
// deliberately pick the LONGEST / most-plane docs which are most likely to overflow.
const withLen = examples.map((e, i) => ({ ...e, i, len: e.src.length,
  planes: (e.src.match(/@plane/g) || []).length }));
const evenSample = withLen.filter((_, i) => i % 4 === 0);
const longest = [...withLen].sort((a, b) => b.len - a.len).slice(0, 15);
const mostPlanes = [...withLen].sort((a, b) => b.planes - a.planes).slice(0, 15);
const seen = new Set();
const sample = [];
for (const e of [...longest, ...mostPlanes, ...evenSample]) {
  if (!seen.has(e.slug)) { seen.add(e.slug); sample.push(e); }
}
console.log(`Total examples: ${examples.length}. Adversarial sample: ${sample.length}`);
console.log(`Max src len in sample: ${Math.max(...sample.map(s=>s.len))}, max planes: ${Math.max(...sample.map(s=>s.planes))}`);

const TOL = 1.0; // px tolerance for sub-pixel rounding

const browser = await webkit.launch();
const page = await browser.newPage({ viewport: { width: 520, height: 520 } });
const consoleErrors = [];
page.on('console', m => { if (m.type() === 'error') consoleErrors.push(m.text()); });
page.on('pageerror', e => consoleErrors.push('PAGEERROR: ' + e.message));

await page.goto(URL, { waitUntil: 'networkidle' });
await page.waitForFunction(() => customElements.get('three-md') !== undefined, { timeout: 15000 });

// Build a fresh element with the embed's height var.
await page.evaluate(() => {
  const el = document.createElement('three-md');
  el.id = 'retest';
  el.style.setProperty('--three-md-height', '420px');
  el.style.display = 'block';
  el.style.width = '480px';
  document.body.prepend(el);
});
await page.waitForTimeout(100);

async function measure() {
  return await page.evaluate(() => {
    const el = document.getElementById('retest');
    const root = el.shadowRoot;
    const stage = root.querySelector('.stage');
    if (!stage) return { error: 'no stage' };
    const sr = stage.getBoundingClientRect();
    const planes = [...root.querySelectorAll('.plane')];
    let worstBottom = 0, worstRight = 0, worstTop = 0, worstLeft = 0;
    let scrollOverflow = 0;
    const offenders = [];
    for (const p of planes) {
      const cs = getComputedStyle(p);
      if (cs.display === 'none') continue;
      const r = p.getBoundingClientRect();
      const ob = r.bottom - sr.bottom;
      const or = r.right - sr.right;
      const ot = sr.top - r.top;
      const ol = sr.left - r.left;
      if (ob > worstBottom) worstBottom = ob;
      if (or > worstRight) worstRight = or;
      if (ot > worstTop) worstTop = ot;
      if (ol > worstLeft) worstLeft = ol;
      // does the plane's own content overflow ITS box without a scroller?
      const oy = cs.overflowY;
      const hiddenScroll = (oy !== 'auto' && oy !== 'scroll') && (p.scrollHeight - p.clientHeight > 2);
      if (hiddenScroll) scrollOverflow = Math.max(scrollOverflow, p.scrollHeight - p.clientHeight);
    }
    // Also: does the STAGE itself have scrollable overflow (content beyond clip)?
    const stageScrollY = stage.scrollHeight - stage.clientHeight;
    const stageScrollX = stage.scrollWidth - stage.clientWidth;
    const stageOverflowHidden = getComputedStyle(stage).overflow;
    return {
      stage: { w: sr.width, h: sr.height },
      planeCount: planes.length,
      worstBottom, worstRight, worstTop, worstLeft,
      scrollOverflow, stageScrollY, stageScrollX, stageOverflowHidden,
    };
  });
}

const results = [];
for (const ex of sample) {
  for (const mode of ['layers', 'map']) {
    await page.evaluate((m) => {
      const el = document.getElementById('retest');
      el.setAttribute('mode', m);
    }, mode);
    await page.evaluate((src) => {
      const el = document.getElementById('retest');
      el.setSource(src);
    }, ex.src).catch(e => { results.push({ slug: ex.slug, mode, error: 'setSource: ' + e.message }); });
    // wait 2x rAF + 70ms + 2x rAF
    await page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
    await page.waitForTimeout(70);
    await page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
    const m = await measure();
    const overflow = Math.max(m.worstBottom||0, m.worstRight||0, m.worstTop||0, m.worstLeft||0);
    const fail = overflow > TOL || (m.stageOverflowHidden !== 'hidden' && (m.stageScrollY>TOL||m.stageScrollX>TOL));
    results.push({ slug: ex.slug, mode, overflow: +overflow.toFixed(2),
      wb: +(m.worstBottom||0).toFixed(2), wr: +(m.worstRight||0).toFixed(2),
      wt: +(m.worstTop||0).toFixed(2), wl: +(m.worstLeft||0).toFixed(2),
      stageScrollY: m.stageScrollY, stageOverflowHidden: m.stageOverflowHidden,
      scrollOverflowNoScroller: m.scrollOverflow, planeCount: m.planeCount, fail });
  }
}

const fails = results.filter(r => r.fail || r.error);
console.log('\n=== FAILS (overflow > ' + TOL + 'px or stage not clipping) ===');
if (fails.length === 0) console.log('NONE');
for (const f of fails) console.log(JSON.stringify(f));

// Worst offenders regardless of pass/fail
const sorted = [...results].filter(r=>!r.error).sort((a,b)=>b.overflow-a.overflow).slice(0,8);
console.log('\n=== WORST 8 BY OVERFLOW (incl passing) ===');
for (const s of sorted) console.log(`${s.slug} [${s.mode}] overflow=${s.overflow} (b=${s.wb} r=${s.wr} t=${s.wt} l=${s.wl}) stageClip=${s.stageOverflowHidden}`);

console.log('\n=== STAGE CLIP CHECK ===');
const notHidden = results.filter(r => r.stageOverflowHidden && r.stageOverflowHidden !== 'hidden');
console.log('Cases where stage overflow != hidden:', notHidden.length);

console.log('\nConsole/page errors during run:', consoleErrors.length);
consoleErrors.slice(0,10).forEach(e => console.log('  ', e.slice(0,160)));

fs.writeFileSync('/tmp/retest-results.json', JSON.stringify({ total: examples.length, sampled: sample.length, results, consoleErrors }, null, 2));
console.log('\nTotal measurements:', results.length, 'Fails:', fails.length);
await browser.close();
