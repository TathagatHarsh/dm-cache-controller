#!/usr/bin/env python3
"""Render selected signals of a VCD file as a waveform SVG (no dependencies).

usage: vcd2svg.py <file.vcd> <out.svg> <t_start_ns> <t_end_ns> [title]
"""
import sys

SIGNALS = [  # (name in VCD under tb_dm_cache, label, kind)
    ("clk", "clk", "bit"), ("rst", "rst", "bit"),
    ("cpu_req", "cpu_req", "bit"), ("cpu_we", "cpu_we", "bit"),
    ("cpu_addr", "cpu_addr", "bus"),
    ("state", "FSM state", "state"),
    ("mem_req", "mem_req", "bit"), ("mem_ready", "mem_ready", "bit"),
    ("cpu_ready", "cpu_ready", "bit"), ("cpu_hit", "cpu_hit", "bit"),
    ("cpu_rdata", "cpu_rdata", "bus"),
    ("hit_count", "hit_count", "dec"), ("miss_count", "miss_count", "dec"),
]
STATE_NAMES = {0: "IDLE", 1: "COMPARE", 2: "ALLOCATE", 3: "WRITE_MEM"}
STATE_COLORS = {0: "#eef2f7", 1: "#fff3c4", 2: "#ffd9d2", 3: "#d9ecff"}


def parse_vcd(path, wanted):
    ids, scope, changes, t = {}, [], {}, 0
    with open(path) as f:
        for line in f:
            tok = line.split()
            if not tok:
                continue
            if tok[0] == "$scope":
                scope.append(tok[2])
            elif tok[0] == "$upscope":
                scope.pop()
            elif tok[0] == "$var" and scope == ["tb_dm_cache"] and tok[4] in wanted:
                ids.setdefault(tok[3], tok[4])
                changes[tok[4]] = []
            elif tok[0][0] == "#":
                t = int(tok[0][1:])
            elif tok[0][0] in "01xz" and len(tok) == 1 and tok[0][1:] in ids:
                changes[ids[tok[0][1:]]].append((t, tok[0][0]))
            elif tok[0][0] == "b" and len(tok) == 2 and tok[1] in ids:
                changes[ids[tok[1]]].append((t, tok[0][1:]))
    return changes


def value_at(ch, t):
    v = "x"
    for tt, vv in ch:
        if tt > t:
            break
        v = vv
    return v


def to_int(v):
    try:
        return int(v, 2)
    except ValueError:
        return None


def main():
    vcd, out, t0, t1 = sys.argv[1], sys.argv[2], int(sys.argv[3]) * 1000, int(sys.argv[4]) * 1000
    title = sys.argv[5] if len(sys.argv) > 5 else ""
    ch = parse_vcd(vcd, {s[0] for s in SIGNALS})
    LBL, ROW, H, W = 110, 30, 18, 1500
    width = LBL + W + 20
    height = 40 + ROW * len(SIGNALS) + 20
    sx = lambda t: LBL + (t - t0) * W / (t1 - t0)
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
         f'font-family="Helvetica,Arial,sans-serif" font-size="12">',
         f'<rect width="{width}" height="{height}" fill="white"/>',
         f'<text x="{LBL}" y="20" font-size="14" font-weight="bold">{title}</text>']
    # grid at every rising clock edge
    for t, v in ch["clk"]:
        if t0 <= t <= t1 and v == "1":
            o.append(f'<line x1="{sx(t):.1f}" y1="30" x2="{sx(t):.1f}" y2="{height-15}" stroke="#e3e3e3"/>')
    for r, (name, label, kind) in enumerate(SIGNALS):
        y = 40 + r * ROW
        o.append(f'<text x="8" y="{y+H-4}" font-weight="bold">{label}</text>')
        pts = [(t0, value_at(ch[name], t0))] + [(t, v) for t, v in ch[name] if t0 < t < t1] + [(t1, None)]
        for (ta, va), (tb, _) in zip(pts, pts[1:]):
            xa, xb = sx(ta), sx(tb)
            if kind == "bit":
                yy = y if va == "1" else y + H
                o.append(f'<line x1="{xa:.1f}" y1="{yy}" x2="{xb:.1f}" y2="{yy}" stroke="#1f5fbf" stroke-width="1.6"/>')
                if ta != t0:
                    o.append(f'<line x1="{xa:.1f}" y1="{y}" x2="{xa:.1f}" y2="{y+H}" stroke="#1f5fbf" stroke-width="1.6"/>')
                if va == "1" and name != "clk":
                    o.append(f'<rect x="{xa:.1f}" y="{y}" width="{xb-xa:.1f}" height="{H}" fill="#1f5fbf" opacity="0.12"/>')
                continue
            n = to_int(va)
            if kind == "state":
                fill, txt = STATE_COLORS.get(n, "#fff"), STATE_NAMES.get(n, "?")
            elif kind == "dec":
                fill, txt = "#f4f4f4", "x" if n is None else str(n)
            else:
                fill, txt = "#f4f4f4", "x" if n is None else f"{n:08X}"
            o.append(f'<polygon points="{xa+2:.1f},{y+H/2} {xa+5:.1f},{y} {xb-3:.1f},{y} {xb:.1f},{y+H/2} '
                     f'{xb-3:.1f},{y+H} {xa+5:.1f},{y+H}" fill="{fill}" stroke="#555" stroke-width="1"/>')
            if xb - xa > 7.2 * len(txt) + 8:
                o.append(f'<text x="{(xa+xb)/2:.1f}" y="{y+H-4}" text-anchor="middle" font-family="Menlo,monospace" font-size="11">{txt}</text>')
    o.append(f'<text x="{LBL}" y="{height-3}" fill="#777" font-size="10">{t0//1000} ns</text>')
    o.append(f'<text x="{LBL+W}" y="{height-3}" fill="#777" font-size="10" text-anchor="end">{t1//1000} ns (10 ns / clock)</text>')
    o.append("</svg>")
    open(out, "w").write("\n".join(o))


if __name__ == "__main__":
    main()
