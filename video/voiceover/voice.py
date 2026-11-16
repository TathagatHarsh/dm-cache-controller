"""Cut each member's voice note into lines (whisper word timestamps + quietest gap),
clean it up, and place every line at its caption time.  -> voice.wav, voice_timing.json
Run from anywhere:  python3 -P video/voiceover/voice.py"""
import json, os, re, subprocess, difflib
import numpy as np, soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__)); WORK = os.path.join(HERE, 'work')
FILM = os.path.join(HERE, '..', 'film'); SR = 48000; DUR = 300
html = open(os.path.join(FILM, 'index.html')).read()
caps = [(int(a), int(b), w, t) for a, b, w, t in re.findall(r"\[(\d+), (\d+), '([A-Z ]+)', [\"'](.+?)[\"']\],\n", html)]
PARTS = {'T1': (0, 30), 'G1': (30, 80), 'M1': (80, 130), 'T2': (130, 180), 'P1': (180, 230), 'V1': (230, 300)}
norm = lambda s: re.sub(r'[^a-z0-9]', '', s.lower())

def clean(k):  # high-pass, gentle denoise, normalise loudness per speaker
    src, dst = os.path.join(WORK, k + '.wav'), os.path.join(WORK, k + '_clean.wav')
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', src, '-af',
                    'highpass=f=80,afftdn=nf=-30,acompressor=threshold=-20dB:ratio=3:attack=5:release=120,loudnorm=I=-18:TP=-2:LRA=7',
                    '-ar', str(SR), '-ac', '1', dst], check=True)
    y, _ = sf.read(dst); return y

def energy(y, hop):
    return 20 * np.log10(np.sqrt(np.convolve(y ** 2, np.ones(hop) / hop, 'same')) + 1e-9)

voice = np.zeros(SR * DUR); report = []
for k, (p0, p1) in PARTS.items():
    lines = [(a, b, t) for a, b, w, t in caps if p0 <= a < p1]
    y = clean(k); db = energy(y, int(0.02 * SR))
    words = [(norm(s['text']), s['offsets']['from'] / 1000, s['offsets']['to'] / 1000)
             for s in json.load(open(os.path.join(WORK, k + '.json')))['transcription'] if norm(s['text'])]
    exp, owner = [], []
    for li, (_, _, t) in enumerate(lines):
        for wd in t.split():
            if norm(wd): exp.append(norm(wd)); owner.append(li)
    sm = difflib.SequenceMatcher(None, exp, [w[0] for w in words], autojunk=False)
    match = {}
    for blk in sm.get_matching_blocks():
        for j in range(blk.size): match[blk.a + j] = blk.b + j
    # boundary between line li-1 and li: quietest 0.2 s window between last matched word of li-1 and first of li
    cuts = [0.0]
    for li in range(1, len(lines)):
        prev = [match[i] for i in match if owner[i] == li - 1]; nxt = [match[i] for i in match if owner[i] == li]
        lo = words[max(prev)][2] - 0.4 if prev else cuts[-1]
        hi = words[min(nxt)][1] + 0.4 if nxt else lo + 1.0
        lo, hi = max(lo, cuts[-1] + 0.2), max(hi, lo + 0.3)
        a, b = int(lo * SR), min(len(y), int(hi * SR))
        win = int(0.2 * SR); seg = db[a:b]
        best = a + (int(np.argmin(np.convolve(seg, np.ones(win) / win, 'valid'))) + win // 2 if len(seg) > win else len(seg) // 2)
        cuts.append(best / SR)
    cuts.append(len(y) / SR)
    pieces = []
    for li in range(len(lines)):
        s, e = int(cuts[li] * SR), int(cuts[li + 1] * SR); seg = y[s:e]; d = db[s:e]
        thr = np.percentile(db, 97) - 32; on = np.where(d > thr)[0]
        if len(on): seg = seg[max(0, on[0] - int(0.08 * SR)): on[-1] + int(0.15 * SR)]
        f = int(0.01 * SR); seg = seg.copy(); seg[:f] *= np.linspace(0, 1, f); seg[-f:] *= np.linspace(1, 0, f)
        pieces.append(seg)
    # place sequentially; if the part would overrun, speed up the whole part (pitch kept) just enough
    gap, lead = 0.2, 0.25
    def layout(ps):
        t, out = None, []
        for (a, b, _), seg in zip(lines, ps):
            st = a + lead if t is None else max(a + lead, t + gap); t = st + len(seg) / SR; out.append(st)
        return out, t
    tempo = 1.0
    for cand in np.arange(1.0, 1.151, 0.01):          # smallest speed-up that fits the part
        tempo = float(cand)
        if layout([s[:int(len(s) / tempo)] for s in pieces])[1] <= p1 - 0.25: break
    if tempo > 1.0:
        sped = []
        for seg in pieces:
            tmp_i, tmp_o = os.path.join(WORK, '_i.wav'), os.path.join(WORK, '_o.wav'); sf.write(tmp_i, seg, SR)
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', tmp_i, '-af', f'atempo={tempo:.3f}', tmp_o], check=True)
            sped.append(sf.read(tmp_o)[0])
        pieces = sped
    starts, end = layout(pieces)
    if end > p1 - 0.25:                                # still too long: pack lines backward from the part end
        latest = p1 - 0.25
        for li in range(len(pieces) - 1, -1, -1):
            starts[li] = min(starts[li], latest - len(pieces[li]) / SR); latest = starts[li] - 0.12
        if starts[0] < p0 + 0.05: print(f'  WARNING {k}: does not fit even at {tempo:.2f}x')
        end = starts[-1] + len(pieces[-1]) / SR
    for (a, b, t), seg, st in zip(lines, pieces, starts):
        i = int(st * SR); voice[i:i + len(seg)] += seg[:max(0, len(voice) - i)]
        report.append({'part': k, 'caption': f'{a}-{b}', 'placed_start': round(st, 2), 'placed_end': round(st + len(seg) / SR, 2),
                       'late_by': round(st - a, 2), 'early_by': round(max(0, a - st), 2), 'tempo': round(tempo, 3), 'text': t})
    print(f"{k}: {len(lines)} lines, matched {len(match)}/{len(exp)} words, tempo {tempo:.3f}, ends {end:.2f}s (part ends {p1})")
sf.write(os.path.join(HERE, 'voice.wav'), voice.astype(np.float32), SR)
# captions follow the voice: each caption starts when its line is spoken
open(os.path.join(FILM, 'cap_times.js'), 'w').write('window.CAP_TIMES = ' + json.dumps([[r['placed_start'] - 0.1, r['placed_end']] for r in report]) + ';\n')
json.dump(report, open(os.path.join(HERE, 'voice_timing.json'), 'w'), indent=1)
late = max(r['late_by'] for r in report); print(f'max delay after caption: {late:.2f}s')
for r in report:
    if r['late_by'] > 1.0: print('  late:', r['part'], r['caption'], r['late_by'], r['text'][:50])
