// node render.js in.svg out.png W H
const { chromium } = require('playwright');
(async () => { const [,, inp, out, w, h] = process.argv; const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: +w, height: +h } });
await p.goto('file://' + require('path').resolve(inp)); await p.screenshot({ path: out, omitBackground: true }); await b.close(); })();
