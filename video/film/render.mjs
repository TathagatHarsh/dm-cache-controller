// node render.mjs cues    -> cues.json (visual hit times, read by audio.py)
// node render.mjs sheet   -> out/sheet_N.jpg, one frame per beat (contact sheets)
// node render.mjs frames 12.5 40 ...  -> out/frame_<t>.png (full-res spot checks)
// node render.mjs full    -> cues + audio + parallel frame render + H.264 (CRF 16, yuv420p) + mux
import { chromium } from 'playwright';
import { spawn, execFileSync } from 'node:child_process';
import fs from 'node:fs'; import path from 'node:path'; import { fileURLToPath } from 'node:url';

const dir = path.dirname(fileURLToPath(import.meta.url));
const out = path.join(dir, 'out'); fs.mkdirSync(out, { recursive: true });
const FPS = 30, W = 1920, H = 1080, WORKERS = 4;
const [mode = 'full', ...rest] = process.argv.slice(2);
const query = rest.includes('--nocaps') ? '?nocaps' : '';

async function openPage(browser) {
  const page = await browser.newPage({ viewport: { width: W, height: H } });
  await page.goto('file://' + path.join(dir, 'index.html') + query);
  await page.waitForFunction(() => window.READY === true);
  return page;
}
const shot = (page, t, opts = {}) => page.evaluate(t => window.seek(t), t).then(() => page.screenshot({ type: 'jpeg', quality: 95, ...opts }));
const run = (cmd, args) => execFileSync(cmd, args, { cwd: dir, stdio: 'inherit' });

async function dumpCues(browser) {
  const page = await openPage(browser);
  const cues = await page.evaluate(() => window.CUES); const dur = await page.evaluate(() => window.DURATION);
  fs.writeFileSync(path.join(dir, 'cues.json'), JSON.stringify({ duration: dur, cues }, null, 1));
  await page.close(); console.log(`cues.json: ${cues.length} cues`); return dur;
}

async function sheet(browser) {
  const beats = fs.existsSync(path.join(dir, 'beats.json')) ? JSON.parse(fs.readFileSync(path.join(dir, 'beats.json'))).beats : null;
  const dur = await page0dur(browser);
  const times = beats || Array.from({ length: Math.floor(dur * 2) }, (_, i) => i * 0.5);
  const page = await openPage(browser); const tmp = path.join(out, 'sheet_tmp'); fs.rmSync(tmp, { recursive: true, force: true }); fs.mkdirSync(tmp);
  for (let i = 0; i < times.length; i++) fs.writeFileSync(path.join(tmp, `f${String(i).padStart(4, '0')}.jpg`), await shot(page, times[i] + 0.25, { quality: 70 }));
  const per = 100; // 10 x 10 tiles per sheet, 50 s at 120 BPM
  for (let s = 0; s * per < times.length; s++)
    run('ffmpeg', ['-y', '-loglevel', 'error', '-start_number', String(s * per), '-i', path.join(tmp, 'f%04d.jpg'), '-frames:v', '1',
      '-vf', `scale=384:-1,tile=10x10:padding=4`,
      path.join(out, `sheet_${s + 1}.jpg`)]);
  fs.rmSync(tmp, { recursive: true, force: true }); await page.close(); console.log('sheets written to out/');
}
async function page0dur(browser) { const p = await openPage(browser); const d = await p.evaluate(() => window.DURATION); await p.close(); return d; }

async function frames(browser, ts) {
  const page = await openPage(browser);
  for (const t of ts) fs.writeFileSync(path.join(out, `frame_${t}.png`), await page.evaluate(t => window.seek(t), +t).then(() => page.screenshot({ type: 'png' })));
  await page.close(); console.log('frames written');
}

async function full(browser) {
  const dur = await dumpCues(browser);
  run('python3', ['-P', path.join(dir, 'audio.py')]);
  const N = Math.round(dur * FPS), chunk = Math.ceil(N / WORKERS), t0 = Date.now();
  await Promise.all(Array.from({ length: WORKERS }, async (_, w) => {
    const a = w * chunk, b = Math.min(N, a + chunk), page = await openPage(browser);
    const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-',
      '-vf', 'scale=in_range=pc:out_range=tv,format=yuv420p', '-c:v', 'libx264', '-preset', 'medium', '-crf', '16', '-pix_fmt', 'yuv420p', '-color_range', 'tv', '-r', String(FPS), path.join(out, `seg${w}.mp4`)], { stdio: ['pipe', 'inherit', 'inherit'] });
    const done = new Promise(r => ff.on('close', r));
    for (let i = a; i < b; i++) {
      const buf = await shot(page, i / FPS);
      if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
      if (w === 0 && i % 300 === 0) console.log(`  worker0 ${i - a}/${b - a}  ${((Date.now() - t0) / 1000).toFixed(0)}s`);
    }
    ff.stdin.end(); await done; await page.close();
  }));
  fs.writeFileSync(path.join(out, 'segs.txt'), Array.from({ length: WORKERS }, (_, w) => `file 'seg${w}.mp4'`).join('\n'));
  const name = query ? 'dm_cache_film_nocaps.mp4' : 'dm_cache_film.mp4';
  run('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', path.join(out, 'segs.txt'), '-i', path.join(out, 'mix.wav'),
    '-c:v', 'copy', '-c:a', 'aac', '-b:a', '256k', '-shortest', '-movflags', '+faststart', path.join(out, name)]);
  for (let w = 0; w < WORKERS; w++) fs.rmSync(path.join(out, `seg${w}.mp4`)); fs.rmSync(path.join(out, 'segs.txt'));
  console.log(`done: out/${name} in ${((Date.now() - t0) / 1000).toFixed(0)}s`);
}

// Use Playwright's own browser if present, else any Chromium already in the Playwright cache.
async function launch() {
  try { return await chromium.launch(); } catch (e) {
    const cache = path.join(process.env.HOME, 'Library/Caches/ms-playwright');
    const found = fs.existsSync(cache) && fs.readdirSync(cache).filter(d => /^chromium-\d+$/.test(d)).sort().reverse()
      .map(d => path.join(cache, d, 'chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing')).find(fs.existsSync);
    if (!found) throw e;
    return chromium.launch({ executablePath: found });
  }
}
const browser = await launch();
try {
  if (mode === 'cues') await dumpCues(browser);
  else if (mode === 'sheet') await sheet(browser);
  else if (mode === 'frames') await frames(browser, rest.filter(x => !x.startsWith('--')));
  else await full(browser);
} finally { await browser.close(); }
