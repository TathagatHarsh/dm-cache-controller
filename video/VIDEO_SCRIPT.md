# Prototype Video: Voiceover Script (5:00)

The animated film is in `video/film/out/dm_cache_film.mp4`. Its on-screen captions are these exact lines, at these exact times, so each member can read their part while watching.

**How to record:** play the film (muted) and read your lines when your name appears. Record on a phone in a quiet room, one file per member, starting from your first timestamp. Send the files back and they get mixed into the film (music ducked under voice). Or record all five together in one take over screen share.

| Time | Speaker | Line |
|---|---|---|
| 0:00–0:07 | **Tathagat Harsh** | Where does address 0x1000 live? In a direct-mapped cache: in exactly one line. |
| 0:07–0:12 | **Tathagat Harsh** | This is our CSA222 project: a Direct-Mapped Cache Controller in Verilog. |
| 0:12–0:23 | **Tathagat Harsh** | I'm Tathagat Harsh, and with me are M S Thejas, Garv Verma, Parv Goyal and Vaibhav Rajput. |
| 0:23–0:30 | **Tathagat Harsh** | A cache is a small, fast SRAM between the CPU and slow DRAM. It works because programs have locality. |
| 0:30–0:40 | **Garv Verma** | Our cache is 1 KB with 16-byte blocks, so it has 64 lines. |
| 0:40–0:52 | **Garv Verma** | A 32-bit address splits into a 22-bit tag, a 6-bit index and a 4-bit offset. |
| 0:52–1:04 | **Garv Verma** | Direct-mapped means each block has exactly one possible line, chosen by the index. Same index means a fight. |
| 1:04–1:14 | **Garv Verma** | My tag comparator gives: hit = valid AND stored tag equals request tag. |
| 1:14–1:20 | **Garv Verma** | If the valid bit is 0, it's a miss, even when the tags match. |
| 1:20–1:30 | **M S Thejas** | The cache stores everything in three arrays: valid bits, tags and data. |
| 1:30–1:40 | **M S Thejas** | Valid bits are flip-flops: one reset clears all 64, so a garbage tag never gives a false hit. |
| 1:40–1:51 | **M S Thejas** | On a miss the data RAM takes a whole 16-byte block in one cycle. On a write hit, just one word. |
| 1:51–2:10 | **M S Thejas** | Direct-mapped gives the fastest hit path: one compare, no replacement policy. The cost is conflict misses. |
| 2:10–2:18 | **Tathagat Harsh** | I designed the controller: a four-state finite state machine. |
| 2:18–2:29 | **Tathagat Harsh** | IDLE latches the request. COMPARE checks the tag. A read miss goes to ALLOCATE and waits ten cycles for memory. |
| 2:29–2:35 | **Tathagat Harsh** | A read hit finishes in a single cycle. |
| 2:35–2:49 | **Tathagat Harsh** | Every write goes to WRITE_MEM: write-through, no-write-allocate. Memory is always up to date, so no dirty bits. |
| 2:49–3:00 | **Tathagat Harsh** | The hit and miss counters live here, so the hardware measures its own hit rate. |
| 3:00–3:13 | **Parv Goyal** | My main-memory model has a ten-cycle latency and returns a whole 128-bit block in one transfer. |
| 3:13–3:25 | **Parv Goyal** | dm_cache.v connects six modules into one cache, with main memory outside it. |
| 3:25–3:33 | **Parv Goyal** | One command compiles and runs the full testbench. |
| 3:33–3:50 | **Parv Goyal** | In the waveform the first read misses and takes 12 cycles. The next three reads hit in one cycle each. |
| 3:50–4:00 | **Vaibhav Rajput** | My testbench checks all 2,187 accesses against a golden reference model. Zero errors. |
| 4:00–4:20 | **Vaibhav Rajput** | Sequential: 75%, one miss per 4-word block. Repeated: 93.75%, temporal locality. Random: about 10%. |
| 4:20–4:30 | **Vaibhav Rajput** | Conflict: 0%. Two addresses 1 KB apart share line 0 and keep evicting each other. |
| 4:30–4:42 | **Vaibhav Rajput** | Measured AMAT matches 1 + miss rate × 11 on every single trace. |
| 4:42–4:52 | **Vaibhav Rajput** | In Phase II we'll synthesize on Vivado and compare against a 2-way LRU cache. |
| 4:52–5:00 | **Vaibhav Rajput** | Thank you! |

Speaking time: Tathagat ~1:20 (intro + controller), Garv 0:50, Thejas 0:50, Parv 0:50, Vaibhav 1:10.

Rebuild the film after changing any line: edit `CAPS` in `video/film/index.html`, then `cd video/film && node render.mjs full`.
