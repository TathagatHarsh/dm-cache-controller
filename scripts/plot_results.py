#!/usr/bin/env python3
"""Phase II figures from sim/phase2/sweep.csv and synth reports -> docs/figures/p2_*.svg/.pdf/.png
(no third-party packages; PDF/PNG via rsvg-convert if available)"""
import csv, os, re, subprocess
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'); FIG = os.path.join(ROOT, 'docs', 'figures')
R = list(csv.DictReader(open(os.path.join(ROOT, 'sim', 'phase2', 'sweep.csv'))))
DM, SA, WT, WB, INK, GRID, DIM = '#5B6270', '#E8590C', '#5B6270', '#E8590C', '#1F2328', '#E4E6EA', '#6B7280'
WORK = ['sequential', 'repeated', 'random', 'conflict', 'mixed_rw']

def val(a, c, b, l, t, k='hit_rate_pct'):
    return float(next(r[k] for r in R if (r['assoc'], r['cache_bytes'], r['block_bytes'], r['latency'], r['trace']) == (str(a), str(c), str(b), str(l), t)))
mean = lambda xs: sum(xs) / len(xs)

class Chart:
    def __init__(s, title, ylab, ymax, w=760, h=430):
        s.w, s.h, s.ymax, s.x0, s.x1, s.y0, s.y1 = w, h + 24, ymax, 74, w - 20, h - 50, 84
        s.o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h + 24}" font-family="Helvetica,Arial,sans-serif">',
               f'<rect width="{w}" height="{h + 24}" fill="white"/>',
               f'<text x="{s.x0}" y="26" font-size="19" font-weight="bold" fill="{INK}">{title}</text>',
               f'<text x="16" y="{(s.y0 + s.y1) / 2}" font-size="14" fill="{DIM}" transform="rotate(-90 16 {(s.y0 + s.y1) / 2})" text-anchor="middle">{ylab}</text>']
        for i in range(6):
            v = ymax * i / 5; y = s.Y(v)
            s.o += [f'<line x1="{s.x0}" x2="{s.x1}" y1="{y:.1f}" y2="{y:.1f}" stroke="{GRID}"/>',
                    f'<text x="{s.x0 - 8}" y="{y + 5:.1f}" font-size="13" fill="{DIM}" text-anchor="end">{v:g}</text>']
    def Y(s, v): return s.y0 - (s.y0 - s.y1) * v / s.ymax
    def legend(s, items):
        x = s.x0                                         # legend row under the title
        for lab, col in items:
            s.o += [f'<rect x="{x}" y="41" width="14" height="14" rx="2" fill="{col}"/>', f'<text x="{x + 20}" y="53" font-size="14" fill="{INK}">{lab}</text>']
            x += 14 + 8 * len(lab) + 34
    def bars(s, cats, series, fmt='{:.0f}'):
        n, gw = len(series), (s.x1 - s.x0) / len(cats); bw = gw * 0.72 / n
        for i, c in enumerate(cats):
            for j, (lab, col, vals) in enumerate(series):
                x = s.x0 + i * gw + gw * 0.14 + j * bw; y = s.Y(vals[i])
                s.o += [f'<rect x="{x:.1f}" y="{y:.1f}" width="{bw - 3:.1f}" height="{s.y0 - y:.1f}" fill="{col}" rx="1.5"/>',
                        f'<text x="{x + bw / 2 - 1.5:.1f}" y="{y - 5:.1f}" font-size="12" fill="{INK}" text-anchor="middle">{fmt.format(vals[i])}</text>']
            s.o.append(f'<text x="{s.x0 + (i + .5) * gw:.1f}" y="{s.y0 + 22}" font-size="14" fill="{INK}" text-anchor="middle">{c}</text>')
        s.legend([(l, c) for l, c, _ in series])
    def lines(s, xs, xlab, series, fmt='{:.1f}'):
        X = lambda i: s.x0 + 30 + i * (s.x1 - s.x0 - 60) / (len(xs) - 1)
        for i, x in enumerate(xs): s.o.append(f'<text x="{X(i):.1f}" y="{s.y0 + 22}" font-size="14" fill="{INK}" text-anchor="middle">{x}</text>')
        s.o.append(f'<text x="{(s.x0 + s.x1) / 2}" y="{s.h - 18}" font-size="14" fill="{DIM}" text-anchor="middle">{xlab}</text>')
        for lab, col, vals, dash in series:
            pts = ' '.join(f'{X(i):.1f},{s.Y(v):.1f}' for i, v in enumerate(vals))
            s.o.append(f'<polyline points="{pts}" fill="none" stroke="{col}" stroke-width="3" {"stroke-dasharray=\"7 5\"" if dash else ""}/>')
            for i, v in enumerate(vals):
                s.o += [f'<circle cx="{X(i):.1f}" cy="{s.Y(v):.1f}" r="4.5" fill="white" stroke="{col}" stroke-width="2.5"/>']
        s.legend([(l, c) for l, c, _, _ in series])
    def save(s, name):
        p = os.path.join(FIG, name + '.svg'); open(p, 'w').write('\n'.join(s.o + ['</svg>']))
        for ext, args in (('pdf', ['-f', 'pdf']), ('png', ['-z', '2'])):
            try: subprocess.run(['rsvg-convert', *args, '-o', p[:-3] + ext, p], check=True)
            except (FileNotFoundError, subprocess.CalledProcessError): pass
        print('  docs/figures/' + name + '.svg')

traces = ['sequential', 'repeated', 'random', 'conflict', 'mixed_rw', 'lru']
c = Chart('Hit rate per trace (1 KB, 16 B blocks)', 'hit rate (%)', 100)
c.bars(traces, [('direct-mapped', DM, [val(1, 1024, 16, 10, t) for t in traces]), ('2-way LRU', SA, [val(2, 1024, 16, 10, t) for t in traces])]); c.save('p2_hit_per_trace')

sizes = [256, 512, 1024, 2048, 4096]
c = Chart('Mean hit rate vs cache size (5 workload traces)', 'mean hit rate (%)', 100)
c.lines([f'{s // 1024} KB' if s >= 1024 else f'{s} B' for s in sizes], 'cache capacity',
        [('direct-mapped', DM, [mean([val(1, s, 16, 10, t) for t in WORK]) for s in sizes], False),
         ('2-way LRU', SA, [mean([val(2, s, 16, 10, t) for t in WORK]) for s in sizes], False)]); c.save('p2_hit_vs_size')

blocks = [8, 16, 32, 64]
c = Chart('Hit rate vs block size (1 KB cache)', 'hit rate (%)', 100)
c.lines([f'{b} B' for b in blocks], 'block size',
        [('sequential', DM, [val(1, 1024, b, 10, 'sequential') for b in blocks], False),
         ('mixed r/w DM', SA, [val(1, 1024, b, 10, 'mixed_rw') for b in blocks], False),
         ('mixed r/w 2-way', SA, [val(2, 1024, b, 10, 'mixed_rw') for b in blocks], True)]); c.save('p2_hit_vs_block')

lats = [5, 10, 20, 50]
c = Chart('Measured AMAT vs memory latency (mixed r/w)', 'AMAT (cycles)', 35)
c.lines([str(l) for l in lats], 'main-memory latency L (cycles)',
        [('direct-mapped', DM, [val(1, 1024, 16, l, 'mixed_rw', 'amat_measured') for l in lats], False),
         ('2-way LRU', SA, [val(2, 1024, 16, l, 'mixed_rw', 'amat_measured') for l in lats], False)]); c.save('p2_amat_vs_latency')

tt = ['sequential', 'random', 'mixed_rw', 'write_loop']
c = Chart('Memory traffic: write-through vs write-back (direct-mapped)', 'bytes moved', 8000)
c.bars(tt, [('write-through (RTL)', WT, [val(1, 1024, 16, 10, t, 'wt_bytes') for t in tt]),
            ('write-back (model)', WB, [val(1, 1024, 16, 10, t, 'wb_bytes') for t in tt])], '{:.0f}'); c.save('p2_traffic')

def stat(top):
    t = open(os.path.join(ROOT, 'synth', 'reports', top + '_stat.txt')).read()
    g = lambda pat: sum(int(n) for n in re.findall(r'^\s*(\d+)\s+' + pat + r'\s*$', t, re.M))
    return {'LUT (logic)': g(r'LUT\d'), 'LUTRAM LUTs': 4 * (g('RAM64M') + g('RAM32M')), 'flip-flops': g(r'FD\w+'), 'CARRY4': g('CARRY4')}
d, s = stat('dm_cache'), stat('sa2_cache'); keys = list(d)
c = Chart('FPGA resources, Artix-7 (Yosys synth_xilinx)', 'count', 1200)
c.bars(keys, [('direct-mapped', DM, [d[k] for k in keys]), ('2-way LRU', SA, [s[k] for k in keys])]); c.save('p2_resources')
print('resources', d, s)
