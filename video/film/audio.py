"""Synthesize score + SFX for the film, measure the beat grid, mix to -14 LUFS.
reads cues.json  ->  writes beats.json, out/score.wav, out/mix.wav"""
import json, os, re, subprocess
import numpy as np, soundfile as sf, librosa

HERE = os.path.dirname(os.path.abspath(__file__)); OUT = os.path.join(HERE, 'out')
SR, BPM = 48000, 120
spec = json.load(open(os.path.join(HERE, 'cues.json')))
DUR = float(spec['duration']); N = int(SR * DUR); BEAT = 60 / BPM; BAR = 4 * BEAT
rng = np.random.default_rng(7)

def place(buf, t, sig, g=1.0):
    i = int(round(t * SR)); j = min(len(buf), i + len(sig))
    if 0 <= i < len(buf): buf[i:j] += g * sig[:j - i]
def tt(d): return np.arange(int(d * SR)) / SR
def midi(n): return 440 * 2 ** ((n - 69) / 12)

# ---------------- score: Am - F - C - G, 2 s bars ----------------
music = np.zeros(N)
CHORDS = [(57, 60, 64), (53, 57, 60), (48, 55, 64), (55, 59, 62)]
kick_t = tt(0.4); kick = np.sin(2 * np.pi * np.cumsum(45 + 80 * np.exp(-kick_t * 28)) / SR) * np.exp(-kick_t * 8)
hat_t = tt(0.06); hat = np.diff(rng.standard_normal(len(hat_t) + 1)) * np.exp(-hat_t * 70)
def pad(notes, d):
    x = tt(d); s = np.zeros_like(x)
    for n in notes:
        for det in (-0.08, 0.08):
            f = midi(n + det)
            for h in (1, 2, 3, 4): s += np.sin(2 * np.pi * f * h * x) / (h * h)
    env = np.minimum(1, x / 0.4) * np.minimum(1, (d - x) / 0.5)
    return s * env / (len(notes) * 4)
def bass(n, d=0.45):
    x = tt(d); f = midi(n - 12); return (np.sin(2 * np.pi * f * x) + 0.3 * np.sin(4 * np.pi * f * x)) * np.exp(-x * 5)

section_starts = [0, 30, 80, 130, 180, 230]
for b in range(int(DUR / BAR)):
    t0 = b * BAR; ch = CHORDS[b % 4]
    place(music, t0, pad(ch, BAR + 0.4), 0.22)
    end_card = t0 >= DUR - 8
    for k in range(4):
        tb = t0 + k * BEAT
        if not end_card: place(music, tb, kick, 0.55 if k % 2 == 0 else 0.4)
        place(music, tb + BEAT / 2, hat, 0.05)
        place(music, tb, bass(ch[0] if k < 3 else ch[1]), 0.30)
for s in section_starts[1:]:        # 2-second riser into every section change
    x = tt(2.0); place(music, s - 2.0, rng.standard_normal(len(x)) * (x / 2.0) ** 3 * 0.12)

# ---------------- measure the beat grid ----------------
y22 = librosa.resample(music.astype(np.float32), orig_sr=SR, target_sr=22050)
env = librosa.onset.onset_strength(y=y22, sr=22050, fmax=180, n_mels=32)          # kick band only
tempo, frames = librosa.beat.beat_track(onset_envelope=env, sr=22050, start_bpm=BPM, units='time')
beats = [round(float(b), 4) for b in frames]
json.dump({'bpm': float(np.atleast_1d(tempo)[0]), 'beats': beats}, open(os.path.join(HERE, 'beats.json'), 'w'))
grid = np.array(beats)

# ---------------- SFX, snapped to the measured grid ----------------
def sfx(kind):
    if kind == 'tick':
        x = tt(0.035); return np.sin(2 * np.pi * 2000 * x) * np.exp(-x * 120) * 0.5
    if kind == 'pop':
        x = tt(0.08); return np.sin(2 * np.pi * np.cumsum(700 + 900 * x / 0.08) / SR) * np.exp(-x * 45) * 0.6
    if kind == 'hit':
        x = tt(0.09); a = np.sin(2 * np.pi * 880 * x) * np.exp(-x * 30); b = np.sin(2 * np.pi * 1320 * x) * np.exp(-x * 30)
        return np.concatenate([a, b]) * 0.6
    if kind == 'miss':
        x = tt(0.18); return np.tanh(3 * np.sin(2 * np.pi * np.cumsum(330 - 160 * x / 0.18) / SR)) * np.exp(-x * 14) * 0.35
    if kind == 'type':
        s = np.zeros(int(0.5 * SR))
        for k in range(8): place(s, k * 0.055, np.diff(rng.standard_normal(200)) * np.exp(-np.arange(199) / 25) * 0.25)
        return s
    if kind == 'boom':
        x = tt(1.2); return (np.sin(2 * np.pi * np.cumsum(38 + 60 * np.exp(-x * 6)) / SR) * np.exp(-x * 2.5) + rng.standard_normal(len(x)) * np.exp(-x * 9) * 0.25) * 0.9
    return np.zeros(1)
fx = np.zeros(N); snapped = 0
for c in spec['cues']:
    t = c['t']
    if c['type'] != 'type' and len(grid):
        j = np.argmin(np.abs(grid - t))
        if abs(grid[j] - t) < 0.2: t = grid[j]; snapped += 1
    place(fx, t, sfx(c['type']))

# ---------------- mix, stereo, loudness ----------------
os.makedirs(OUT, exist_ok=True)
VOICE = os.path.join(HERE, '..', 'voiceover', 'voice.wav')
if os.path.exists(VOICE):   # recorded narration: duck music ~12 dB and SFX ~6 dB under speech
    v, vsr = sf.read(VOICE); v = v[:N] if len(v) >= N else np.pad(v, (0, N - len(v)))
    hop = int(0.01 * SR); lvl = np.sqrt(np.convolve(v ** 2, np.ones(hop) / hop, 'same'))
    gate = (lvl > np.percentile(lvl[lvl > 0], 20) * 0.5).astype(float) if np.any(lvl > 0) else np.zeros(N)
    env = np.zeros(N); a_c, r_c = np.exp(-1 / (0.03 * SR)), np.exp(-1 / (0.45 * SR)); e = 0.0
    for i in range(0, N, hop):                       # attack 30 ms / release 450 ms, per 10 ms block
        g = gate[i]; e = (a_c if g > e else r_c) ** hop * (e - g) + g; env[i:i + hop] = e
    duck_m, duck_f = 1 - 0.75 * env, 1 - 0.5 * env
    active = v[env > 0.5]
    vg = 10 ** (10 / 20) * 0.9 * np.sqrt(np.mean(music ** 2)) * 0.25 / max(1e-6, np.sqrt(np.mean(active ** 2))) if len(active) else 0
    print(f'voice: {np.mean(env > 0.5) * 100:.0f}% of the film has speech, voice gain {vg:.2f}')
else:
    v = np.zeros(N); duck_m = duck_f = np.ones(N); vg = 0
mix = np.stack([0.9 * music * duck_m + 0.75 * fx * duck_f + vg * v, 0.9 * music * duck_m + 0.75 * np.roll(fx * duck_f, 24) + vg * v], 1)
fade = np.minimum(1, (DUR - np.arange(N) / SR) / 3.0)[:, None]; mix *= fade
raw = os.path.join(OUT, 'mix_raw.wav'); sf.write(raw, (mix / np.max(np.abs(mix)) * 0.5).astype(np.float32), SR)
def lufs(p):
    r = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-i', p, '-af', 'ebur128=peak=true', '-f', 'null', '-'], capture_output=True, text=True).stderr
    return float(re.findall(r'I:\s+(-?[\d.]+) LUFS', r)[-1]), float(re.findall(r'Peak:\s+(-?[\d.]+) dBFS', r)[-1])
y0, _ = sf.read(raw); g = 1.0
def limit(x, knee=0.45, ceil=0.68):  # soft limiter, ceiling ~ -1.7 dBFS leaves true-peak headroom
    a = np.abs(x); return np.where(a > knee, np.sign(x) * (knee + (ceil - knee) * np.tanh((a - knee) / (ceil - knee))), x)
for _ in range(4):                  # gain -> limit -> measure until integrated loudness is -14 LUFS
    y = limit(y0 * g); sf.write(os.path.join(OUT, 'mix.wav'), y.astype(np.float32), SR)
    I, pk = lufs(os.path.join(OUT, 'mix.wav')); g *= 10 ** ((-14 - I) / 20)
    if abs(I + 14) < 0.15: break
sf.write(os.path.join(OUT, 'score.wav'), (music / np.max(np.abs(music)) * 0.5).astype(np.float32), SR)
os.remove(raw)
I1, pk = lufs(os.path.join(OUT, 'mix.wav'))
print(f'beat grid: {len(beats)} beats @ {float(np.atleast_1d(tempo)[0]):.1f} BPM | {snapped}/{len(spec["cues"])} cues snapped | mix {I1:.1f} LUFS, peak {pk:.1f} dBFS')
