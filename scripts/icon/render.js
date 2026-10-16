// node render.js IN.svg OUT.png WIDTH HEIGHT — renders an SVG with Chromium (Playwright), transparent background.
const path = require('path');
const { chromium } = require('playwright');
(async () => {
  const [, , inp, out, w, h] = process.argv;
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: +w, height: +h } });
  await page.goto('file://' + path.resolve(inp));
  await page.screenshot({ path: out, omitBackground: true });
  await browser.close();
})();
