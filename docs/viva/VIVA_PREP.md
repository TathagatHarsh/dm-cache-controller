# Viva preparation: Direct-Mapped & 2-Way Cache Controllers

Each member: know **your own files line by line**, the **common questions** at the end, and our **headline numbers**.
Open your files on GitHub while revising; every answer below points at real code.

**Headline numbers:** 1 KB, 16 B blocks, 32-bit address · DM split 22 / 6 / 4 · 2-way split 23 / 5 / 4 · hit = 1 cycle, miss = L + 2 = 12 cycles (L = 10) · AMAT = 1 + m × 11 · 59,510 accesses checked, 0 errors · conflict trace 0 % → 98.44 % · 412 → 805 logic LUTs · 6 → 7 LUT levels.

---

## Tathagat Harsh: controllers (`cache_controller.v`, `sa2_cache_controller.v`)

**60-second pitch:** Both controllers are 4-state FSMs: IDLE latches the request, COMPARE decides hit or miss, ALLOCATE waits for memory and refills, WRITE_MEM does the write-through. A read hit finishes in COMPARE (1 cycle); a read miss takes L + 2 cycles. The 2-way version adds two things: it latches the **victim way** in COMPARE, and it updates the set's **LRU bit** to the way *not* used, on every hit and every refill.

| Question | Answer |
|---|---|
| Why 4 states? | One per job: wait, look up, refill, write to memory. It's the Patterson & Hennessy controller with WRITE-BACK replaced by WRITE_MEM, because we're write-through. |
| Moore or Mealy? | Mixed. Memory signals (`mem_req`, `mem_we`) depend only on state (Moore, glitch-free). `cpu_ready` and RAM write-enables also use `hit` / `mem_ready` (Mealy) so a hit finishes in the same cycle. |
| Why is a miss 12 cycles? | 1 cycle COMPARE + 10 cycles memory latency + 1 cycle where `mem_ready` is high and the block is written, so L + 2. |
| Why latch the victim? | So the way chosen in COMPARE can't change while we wait in ALLOCATE; the refill goes to exactly the way we decided on. |
| How does LRU work with 2 ways? | One bit per set stores the least recently used way. After using way w we write `lru = ~w`. |
| What happens on a write miss? | No-write-allocate: the word goes straight to memory, the cache isn't touched and LRU doesn't change. |
| Where are the hit/miss counters? | In the controller, incremented once per access in COMPARE. The testbench checks them against the reference model after every trace. |

## M S Thejas: storage (`cache_rams.v`, `sa2_way_storage.v`)

**60-second pitch:** Three arrays: the **data RAM** (64 × 128 bits = 1 KB), the **tag RAM** (64 × 22) and the **valid bits** (64 × 1). Reads are asynchronous, so lookup and compare fit in one cycle; writes happen on the clock edge. The data RAM supports a whole-block refill or a single-word write. In Phase II `sa2_way_storage` reuses the same modules twice (way 0, way 1), with 32 sets each, plus 32 LRU bits.

| Question | Answer |
|---|---|
| Why are valid bits flip-flops, not RAM? | So one reset clears all of them in a single cycle. Otherwise garbage in the tag RAM could produce a false hit after power-up. |
| Total storage? | 64 × (1 + 22 + 128) = 9,664 bits, of which 8,192 are data. |
| Why asynchronous reads? | Index, read, compare and hit all happen in the COMPARE cycle, giving a 1-cycle hit. On the FPGA they map to distributed LUTRAM (RAM64M / RAM32M). |
| Block write vs word write? | `block_we` on refill writes all 128 bits; `word_we` on a write hit writes one 32-bit word, selected by `word_sel*32 +: 32`. |
| How is the 2-way storage different? | Same RAMs, instantiated per way, and each way's write-enable is ANDed with `wr_way`. Both ways are read in parallel so both tags can be compared at once. |
| Why does the 2-way tag have 23 bits? | Two ways means 32 sets, so the index is 5 bits and the tag gets one extra bit: 32 − 5 − 4 = 23. |

## Garv Verma: address split & hit logic (`addr_decoder.v`, `tag_comparator.v`, `way_select.v`)

**60-second pitch:** The decoder splits the address into tag [31:10], index [9:4], word [3:2] and byte [1:0]. The comparator gives hit = valid AND (stored tag == request tag). In Phase II `way_select` runs **two comparators in parallel**, picks the hitting way's block, and chooses the **victim**: an invalid way first, otherwise the LRU way.

| Question | Answer |
|---|---|
| Derive the field widths. | 1024 / 16 = 64 lines gives a 6-bit index; 16 B blocks give a 4-bit offset (2 bits word, 2 bits byte); the tag is 32 − 6 − 4 = 22 bits. |
| Why AND with valid? | A never-filled line might hold garbage that happens to match; valid = 0 must always mean a miss. |
| What is a conflict miss? | Two blocks with the same index evict each other even though the cache isn't full. Our conflict trace (0x5000 / 0x5400) gets 0 % in DM and 98.44 % in 2-way. |
| Victim choice? | `!valid0 ? 0 : !valid1 ? 1 : lru`. Filling an empty way never throws away useful data. |
| Why is the 2-way cache slower? | The way-select multiplexer after the compare adds a logic level: 6 → 7 LUT levels, about 204 → 185 MHz (estimated). That's Hill's argument for direct-mapped caches. |
| Why is the address latched before decoding? | The controller registers `addr_q` in IDLE, so the decoder sees a stable address for the whole access. |

## Parv Goyal: memory, integration, synthesis (`main_memory.v`, `dm_cache.v`, `sa2_cache.v`, `synth/`)

**60-second pitch:** `main_memory` is a behavioural DRAM model: after `MEM_LATENCY` cycles it pulses `mem_ready` and returns a whole block (`BLOCK_WORDS` words) on one wide bus. The top levels connect the modules, and on a miss they forward the requested word straight from the incoming block, which saves a cycle. Synthesis with Yosys for Artix-7: DM uses 412 logic LUTs + 544 LUTRAM LUTs + 202 FFs; 2-way uses 805 + 1,056 + 234.

| Question | Answer |
|---|---|
| Is main_memory synthesizable? | It isn't meant to be; it's a simulation model of DRAM. Only `dm_cache` / `sa2_cache` are synthesized. |
| Why return the whole block at once? | It keeps the controller simple: one handshake per refill. Real DRAM uses bursts; that's a known limitation in our report. |
| How was Fmax obtained? | Estimated: ABC's LUT mapping gives 6 / 7 levels, × ~0.5 ns per level + ~1.3 ns LUTRAM read + ~0.6 ns register overhead ≈ 4.9 / 5.4 ns. `synth/vivado_synth.tcl` gives the exact post-route value. |
| Why LUTRAM, not BRAM? | Asynchronous reads (needed for the 1-cycle hit) map to distributed RAM; block RAM has synchronous reads. |
| Percentage of the FPGA used? | xc7a35t has 20,800 LUTs: DM ≈ 4.6 %, 2-way ≈ 8.9 %. |
| Why the same interface for both caches? | So one testbench and the same traces drive both: a fair comparison. |

## Vaibhav Rajput: verification & results (`tb_dm_cache.v`, `tb_cache.v`, `sweep.sh`, `plot_results.py`)

**60-second pitch:** The testbench contains a **golden reference model** that predicts, for every access, hit or miss and the data that must come back, and checks the hardware counters after each trace. The Phase II testbench works for 1 or 2 ways, any size, block size and latency; the sweep ran 22 configurations × 8 traces = 59,510 accesses with zero errors. It also contains a write-back traffic model.

| Question | Answer |
|---|---|
| Why does sequential give exactly 75 %? | 4 words per block: one compulsory miss, then 3 hits. |
| Why does repeated give 93.75 %? | A 512 B array fits in 1 KB: 32 cold misses out of 512 accesses, then everything hits. |
| Why is 2-way worse on random (9.38 vs 10.35 %)? | The 8 KB working set is capacity-bound; associativity only fixes conflicts, and halving the sets changes which blocks collide. |
| Why does the 2-way advantage disappear at 2 KB? | With 128 lines, 0x5000 and 0x5400 no longer share a line, so the direct-mapped cache has no conflict to fix. |
| Write-back vs write-through? | WB halves traffic on the write loop (1,024 vs 2,048 B) but moves more on scattered writes (6,464 vs 3,720 B), because write-allocate fetches whole blocks. |
| How do you know the AMAT is right? | Measured cycles match 1 + m × (L + 1) exactly on every trace, so the controller timing is correct. |

---

## Common questions (everyone)

1. **What is a cache, and why does it work?** A small, fast SRAM that holds recently used blocks. It works because of temporal locality (reuse) and spatial locality (neighbouring addresses).
2. **Direct-mapped vs set-associative?** DM: one possible line per block, so 1 compare, fast and cheap, but conflict misses. N-way: N possible places, so N compares + mux + replacement state, fewer conflict misses.
3. **The 3 Cs?** Compulsory (first access), capacity (working set too big), conflict (same index). Associativity removes conflict misses.
4. **AMAT?** Hit time + miss rate × miss penalty = 1 + m × 11 cycles in our design.
5. **Write-through vs write-back?** WT writes memory on every store (simple, memory always correct, more traffic). WB writes only dirty blocks on eviction (needs dirty bits, less traffic when writes have locality).
6. **Why not always use more associativity?** More LUTs (2× here) and a slower hit path. Hill's effective time: on the mixed workload DM ≈ 35.2 ns vs 2-way ≈ 37.7 ns per read.
7. **How did you verify?** A self-checking testbench with a reference model checks every access (hit/miss + data + counters), plus waveforms.
8. **What would you do next?** Exact Vivado timing, a victim cache (Jouppi 1990), a write buffer or RTL write-back, and real program traces from a RISC-V core.
