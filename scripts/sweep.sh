#!/usr/bin/env bash
# Phase II parameter sweep: every configuration runs the full self-checking
# testbench (tb/tb_cache.v) for both the direct-mapped and the 2-way LRU cache.
# Output: sim/phase2/sweep.csv (one row per configuration x trace)
set -euo pipefail
cd "$(dirname "$0")/../sim/phase2"
rm -f results_p2.csv
run() {  # assoc cache_bytes block_bytes latency
  iverilog -g2005 -Ptb_cache.ASSOC=$1 -Ptb_cache.CACHE_BYTES=$2 -Ptb_cache.BLOCK_BYTES=$3 -Ptb_cache.MEM_LATENCY=$4 \
           -o sweep.vvp ../../rtl/*.v ../../tb/tb_cache.v
  vvp -n sweep.vvp > sweep_run.log
  if grep -q "ALL CHECKS PASSED" sweep_run.log; then r=PASS; else r=FAIL; fi
  printf "  assoc=%s size=%5sB block=%2sB latency=%2s  %s\n" "$1" "$2" "$3" "$4" "$r"
  [ "$r" = PASS ] || { cat sweep_run.log; exit 1; }
}
echo "cache size sweep";   for A in 1 2; do for C in 256 512 1024 2048 4096; do run $A $C 16 10; done; done
echo "block size sweep";   for A in 1 2; do for B in 8 32 64; do run $A 1024 $B 10; done; done
echo "memory latency sweep"; for A in 1 2; do for L in 5 20 50; do run $A 1024 16 $L; done; done
{ echo "assoc,cache_bytes,block_bytes,latency,trace,accesses,hits,hit_rate_pct,amat_measured,amat_formula,wt_bytes,wb_bytes"; cat results_p2.csv; } > sweep.csv
rm -f results_p2.csv sweep.vvp sweep_run.log
echo "$(($(wc -l < sweep.csv) - 1)) rows -> sim/phase2/sweep.csv"
