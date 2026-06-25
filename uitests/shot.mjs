import { webkit } from 'playwright';
import fs from 'fs';
const URL = 'https://corvidlabs.github.io/3md/embed-example.html?theme=dark';
const examples = JSON.parse(fs.readFileSync('/tmp/all-examples.json', 'utf8'));
const get = s => examples.find(e => e.slug === s).src;
const browser = await webkit.launch();
const page = await browser.newPage({ viewport: { width: 520, height: 600 } });
await page.goto(URL, { waitUntil: 'networkidle' });
await page.waitForFunction(() => customElements.get('three-md') !== undefined);
await page.evaluate(() => {
  const el = document.createElement('three-md'); el.id='retest';
  el.style.setProperty('--three-md-height','420px'); el.style.display='block'; el.style.width='480px';
  document.body.prepend(el);
});
async function shot(slug, mode, file) {
  await page.evaluate(m => document.getElementById('retest').setAttribute('mode', m), mode);
  await page.evaluate(src => document.getElementById('retest').setSource(src), get(slug));
  await page.evaluate(() => new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));
  await page.waitForTimeout(120);
  // Draw the stage clip rect outline so overflow is visible, and reveal overflow by un-hiding clip on a CLONE measure
  const info = await page.evaluate(() => {
    const el=document.getElementById('retest'); const root=el.shadowRoot;
    const stage=root.querySelector('.stage'); const sr=stage.getBoundingClientRect();
    const planes=[...root.querySelectorAll('.plane')].filter(p=>getComputedStyle(p).display!=='none');
    let maxR=0; for(const p of planes){const r=p.getBoundingClientRect(); maxR=Math.max(maxR, r.right-sr.right, sr.left-r.left, r.bottom-sr.bottom);}
    return {overflow:+maxR.toFixed(1), stageRight:+sr.right.toFixed(1), stageBottom:+sr.bottom.toFixed(1)};
  });
  const el = await page.locator('#retest');
  await el.screenshot({ path: '/tmp/'+file });
  console.log(slug, mode, '->', file, JSON.stringify(info));
}
await shot('game-of-life','map','gol-map.png');
await shot('game-of-life','layers','gol-layers.png');
await shot('spanish-ser-vs-estar-flashcards','map','spanish-map.png');
await browser.close();
