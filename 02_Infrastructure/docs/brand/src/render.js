// SVG -> PNG with headless Chromium (Playwright).
// usage: node render.js <in.svg> <out.png> <width> <height> [transparent=0|1] [scale=1]
const fs = require('fs');
const { chromium } = require('playwright');

(async () => {
  const [inp, out, w, h, tr, sc] = process.argv.slice(2);
  let svg = fs.readFileSync(inp, 'utf8');
  svg = svg.replace(/<svg([^>]*)>/, (m, attrs) =>
    `<svg${attrs.replace(/\s(width|height)="[^"]*"/g, '')} width="${w}" height="${h}" style="display:block">`);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: +w, height: +h }, deviceScaleFactor: +(sc || 1) });
  await page.setContent(`<!doctype html><html><body style="margin:0;background:${tr === '1' ? 'transparent' : '#fff'}">${svg}</body></html>`);
  await page.screenshot({ path: out, omitBackground: tr === '1', clip: { x: 0, y: 0, width: +w, height: +h } });
  await browser.close();
})();
