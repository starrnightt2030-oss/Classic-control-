// Screenshots of the web preview (CI). node shoot.js <baseUrl> <outDir>
const puppeteer = require('puppeteer');
(async () => {
  const [base, out] = process.argv.slice(2);
  const browser = await puppeteer.launch({ args: ['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const shots = [
    ['lab_edit_desktop', '?demo=0', 1600, 1000],
    ['lab_run_desktop', '?demo=1', 1600, 1000],
    ['lab_library_desktop', '?demo=2', 1600, 1000],
    ['lab_run_phone', '?demo=1', 412, 915],
    ['lab_short_desktop', '?demo=3', 1600, 1000],
    ['lab_burn_desktop', '?demo=4', 1600, 1000],
    ['schem_edit_desktop', '?page=schem&demo=3', 1600, 1000],
    ['schem_run_desktop', '?page=schem&demo=1', 1600, 1000],
    ['schem_library_desktop', '?page=schem&demo=2', 1600, 1000],
    ['schem_run_phone', '?page=schem&demo=1', 412, 915],
  ];
  for (const [name, q, w, h] of shots) {
    const page = await browser.newPage();
    await page.setViewport({ width: w, height: h, deviceScaleFactor: 1 });
    page.on('console', m => console.log(name, m.type(), m.text().slice(0, 300)));
    page.on('pageerror', e => console.log(name, 'pageerror', String(e).slice(0, 300)));
    await page.goto(base + q, { waitUntil: 'networkidle0', timeout: 90000 });
    await new Promise(r => setTimeout(r, name.includes('run') ? 9000 : 6000));
    await page.screenshot({ path: `${out}/${name}.png` });
    await page.close();
  }
  await browser.close();
})();
