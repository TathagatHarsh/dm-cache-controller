#!/usr/bin/env bash
# Compile + simulate the cache, then regenerate waveform / diagram figures.
# Needs: iverilog (brew install icarus-verilog). Optional: graphviz, librsvg.
set -euo pipefail
cd "$(dirname "$0")/../sim"
iverilog -g2005 -Wall -o dm_cache.vvp ../rtl/*.v ../tb/tb_dm_cache.v
vvp -n dm_cache.vvp | tee sim_output.txt
grep -q "ALL CHECKS PASSED" sim_output.txt || { echo "SIMULATION FAILED"; exit 1; }

F=../docs/figures
python3 ../scripts/vcd2svg.py dm_cache.vcd $F/wave_miss_then_hits.svg 10 205 "Read miss (12 cycles: COMPARE -> ALLOCATE) followed by 3 read hits (1 cycle each)"
python3 ../scripts/vcd2svg.py dm_cache.vcd $F/wave_write_through.svg 200 500 "Write hit, read-back hit, write miss (no-allocate) - every write goes to memory"
python3 ../scripts/vcd2svg.py dm_cache.vcd $F/wave_directed_full.svg 0 910 "Full directed test: 11 accesses, 6 hits / 5 misses"
if command -v rsvg-convert >/dev/null; then
  for f in $F/wave_*.svg; do rsvg-convert -z 2 -o "${f%.svg}.png" "$f"; rsvg-convert -f pdf -o "${f%.svg}.pdf" "$f"; done
fi
if command -v dot >/dev/null; then
  for f in block_diagram fsm; do dot -Tpdf $F/$f.dot -o $F/$f.pdf; dot -Tpng -Gdpi=200 $F/$f.dot -o $F/$f.png; done
fi
echo "Done. Results: sim/results.csv, sim/trace_log.csv, waveform: sim/dm_cache.vcd (open in GTKWave)"
