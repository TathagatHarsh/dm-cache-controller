#!/usr/bin/env bash
# Open-source synthesis for a Xilinx 7-series (Artix-7) target with Yosys.
# Reports LUT / FF / LUTRAM / carry usage and ABC's LUT-level depth (critical path).
# usage: synth/synth_yosys.sh [dm_cache|sa2_cache]   (default: both)
set -euo pipefail
cd "$(dirname "$0")/.."
RTL="rtl/addr_decoder.v rtl/tag_comparator.v rtl/cache_rams.v rtl/cache_controller.v rtl/dm_cache.v rtl/sa2_way_storage.v rtl/way_select.v rtl/sa2_cache_controller.v rtl/sa2_cache.v"
mkdir -p synth/reports
for TOP in ${1:-dm_cache sa2_cache}; do
  echo "== $TOP"
  yosys -q -l synth/reports/$TOP.log -p "read_verilog $RTL; synth_xilinx -family xc7 -top $TOP -flatten -abc9;
        tee -q -o synth/reports/${TOP}_stat.txt stat"
  grep -E "cells|LUT|FD|RAM|CARRY|MUXF" synth/reports/${TOP}_stat.txt | head -20
  grep "lev =" synth/reports/$TOP.log | tail -1   # ABC LUT mapping: logic levels
done
