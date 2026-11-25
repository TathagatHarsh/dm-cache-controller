// ============================================================================
// tb_cache.v  --  Phase II self-checking testbench for BOTH caches
//
//   -P tb_cache.ASSOC=1  -> dm_cache   (direct-mapped)
//   -P tb_cache.ASSOC=2  -> sa2_cache  (2-way set-associative, LRU)
//   also CACHE_BYTES, BLOCK_BYTES, MEM_LATENCY for parameter sweeps
//
//  * Golden reference model (any associativity 1/2, true LRU) predicts hit/miss
//    and data for EVERY access; hardware counters are checked per trace.
//  * Same 6 traces as Phase I + an LRU directed test (A B A C A B, one set)
//    + a write_loop trace (write locality) for the write-back comparison.
//  * Traffic model: bytes on the memory bus for the RTL's write-through /
//    no-write-allocate policy vs a write-back / write-allocate shadow model
//    (same organisation and LRU), so both policies see identical traces.
//  * Appends one row per trace to results_p2.csv.  +vcd dumps the directed test.
// ============================================================================
`timescale 1ns/1ps
module tb_cache;
    parameter ASSOC       = 1;
    parameter CACHE_BYTES = 1024;
    parameter BLOCK_BYTES = 16;
    parameter MEM_LATENCY = 10;
    localparam WORDS = BLOCK_BYTES / 4, BLOCKS = CACHE_BYTES / BLOCK_BYTES, SETS = BLOCKS / ASSOC;
    localparam OFFSET_W = $clog2(BLOCK_BYTES);

    reg         clk = 0, rst = 1, cpu_req = 0, cpu_we = 0;
    reg  [31:0] cpu_addr = 0, cpu_wdata = 0;
    wire [31:0] cpu_rdata, mem_addr, mem_wdata, hit_count, miss_count;
    wire        cpu_ready, cpu_hit, mem_req, mem_we, mem_ready;
    wire [32*WORDS-1:0] mem_rdata;
    wire [1:0]  state;
    always #5 clk = ~clk;

    generate if (ASSOC == 1) begin : g_dut
        dm_cache  #(.CACHE_BYTES(CACHE_BYTES), .BLOCK_BYTES(BLOCK_BYTES)) dut (.clk(clk), .rst(rst),
            .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata), .cpu_rdata(cpu_rdata),
            .cpu_ready(cpu_ready), .cpu_hit(cpu_hit), .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
            .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ready(mem_ready), .state(state),
            .hit_count(hit_count), .miss_count(miss_count));
    end else begin : g_dut
        sa2_cache #(.CACHE_BYTES(CACHE_BYTES), .BLOCK_BYTES(BLOCK_BYTES)) dut (.clk(clk), .rst(rst),
            .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata), .cpu_rdata(cpu_rdata),
            .cpu_ready(cpu_ready), .cpu_hit(cpu_hit), .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
            .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ready(mem_ready), .state(state),
            .hit_count(hit_count), .miss_count(miss_count));
    end endgenerate

    main_memory #(.MEM_LATENCY(MEM_LATENCY), .BLOCK_WORDS(WORDS)) mem_u (.clk(clk), .mem_req(mem_req), .mem_we(mem_we),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ready(mem_ready));

    // ---------------- golden model (write-through, no-write-allocate) -------
    reg [31:0] ref_mem [0:16383];
    reg        rv [0:2*SETS-1];  reg [31:0] rb [0:2*SETS-1];  reg rl [0:SETS-1];
    // ---------------- traffic shadow model (write-back, write-allocate) -----
    reg        wv [0:2*SETS-1];  reg [31:0] wbk [0:2*SETS-1]; reg wd [0:2*SETS-1]; reg wl [0:SETS-1];

    integer i, errors = 0, fsum;
    integer n_acc, n_hit, n_rd, n_rd_hit, cyc_rd, wt_bytes, wb_bytes, seq_no;
    reg [8*12-1:0] tname;

    function integer way_of(input [31:0] blk, input integer s);   // -1 if miss
        begin way_of = -1;
            if (rv[2*s] && rb[2*s] == blk) way_of = 0;
            else if (ASSOC == 2 && rv[2*s+1] && rb[2*s+1] == blk) way_of = 1;
        end endfunction

    task cold_reset;
        begin
            rst = 1; @(posedge clk); @(posedge clk); #1 rst = 0;
            for (i = 0; i < 2 * SETS; i = i + 1) begin rv[i] = 0; wv[i] = 0; wd[i] = 0; end
            for (i = 0; i < SETS; i = i + 1) begin rl[i] = 0; wl[i] = 0; end
            n_acc = 0; n_hit = 0; n_rd = 0; n_rd_hit = 0; cyc_rd = 0; wt_bytes = 0; wb_bytes = 0; seq_no = 0;
        end endtask

    task wb_model(input we, input [31:0] blk);      // write-back + write-allocate traffic
        integer s, w, v;
        begin
            s = blk % SETS; w = -1;
            if (wv[2*s] && wbk[2*s] == blk) w = 0; else if (ASSOC == 2 && wv[2*s+1] && wbk[2*s+1] == blk) w = 1;
            if (w < 0) begin                          // miss: evict (write back if dirty), fetch block
                v = (ASSOC == 1) ? 0 : !wv[2*s] ? 0 : !wv[2*s+1] ? 1 : wl[s];
                if (wv[2*s+v] && wd[2*s+v]) wb_bytes = wb_bytes + BLOCK_BYTES;
                wb_bytes = wb_bytes + BLOCK_BYTES; wv[2*s+v] = 1; wbk[2*s+v] = blk; wd[2*s+v] = 0; w = v;
            end
            if (we) wd[2*s+w] = 1;
            wl[s] = ~w[0];
        end endtask

    task access(input we, input [31:0] addr, input [31:0] wdata);
        reg [31:0] blk, exp_data; integer s, w, v, cyc; reg exp_hit;
        begin
            blk = addr >> OFFSET_W; s = blk % SETS; w = way_of(blk, s); exp_hit = (w >= 0);
            exp_data = ref_mem[addr[15:2]];
            @(negedge clk); cpu_req = 1; cpu_we = we; cpu_addr = addr; cpu_wdata = wdata;
            @(negedge clk); cpu_req = 0; cyc = 1;
            while (!cpu_ready) begin @(negedge clk); cyc = cyc + 1; end
            if (cpu_hit !== exp_hit) begin errors = errors + 1;
                $display("ERROR %0s #%0d addr=%h expected %s", tname, seq_no, addr, exp_hit ? "HIT" : "MISS"); end
            if (!we && cpu_rdata !== exp_data) begin errors = errors + 1;
                $display("ERROR %0s #%0d addr=%h data %h expected %h", tname, seq_no, addr, cpu_rdata, exp_data); end
            // golden model update (write-through, no-write-allocate, LRU)
            if (we) begin ref_mem[addr[15:2]] = wdata; wt_bytes = wt_bytes + 4; if (exp_hit) rl[s] = ~w[0]; end
            else if (exp_hit) rl[s] = ~w[0];
            else begin
                v = (ASSOC == 1) ? 0 : !rv[2*s] ? 0 : !rv[2*s+1] ? 1 : rl[s];
                rv[2*s+v] = 1; rb[2*s+v] = blk; rl[s] = ~v[0]; wt_bytes = wt_bytes + BLOCK_BYTES;
            end
            wb_model(we, blk);
            n_acc = n_acc + 1; if (exp_hit) n_hit = n_hit + 1;
            if (!we) begin n_rd = n_rd + 1; cyc_rd = cyc_rd + cyc; if (exp_hit) n_rd_hit = n_rd_hit + 1; end
            seq_no = seq_no + 1; @(posedge clk);
        end endtask

    task report;
        real hr, am, af; integer s;
        begin
            @(negedge clk);
            for (s = 0; s < 2 * SETS; s = s + 1) if (wv[s] && wd[s]) wb_bytes = wb_bytes + BLOCK_BYTES;  // final flush
            hr = 100.0 * n_hit / n_acc;
            am = n_rd ? 1.0 * cyc_rd / n_rd : 0;
            af = n_rd ? 1.0 + (1.0 - 1.0 * n_rd_hit / n_rd) * (MEM_LATENCY + 1) : 0;
            if (hit_count !== n_hit || miss_count !== n_acc - n_hit) begin errors = errors + 1;
                $display("ERROR %0s hw counters %0d/%0d expected %0d/%0d", tname, hit_count, miss_count, n_hit, n_acc - n_hit); end
            $display("| %10s | %5d | %5d | %7.2f%% | %6.2f | %6.2f | %7d | %7d |", tname, n_acc, n_hit, hr, am, af, wt_bytes, wb_bytes);
            $fdisplay(fsum, "%0d,%0d,%0d,%0d,%0s,%0d,%0d,%0.2f,%0.3f,%0.3f,%0d,%0d", ASSOC, CACHE_BYTES, BLOCK_BYTES, MEM_LATENCY,
                      tname, n_acc, n_hit, hr, am, af, wt_bytes, wb_bytes);
        end endtask

    reg [31:0] lfsr, a; integer k, p;
    initial begin
        for (i = 0; i < 16384; i = i + 1) ref_mem[i] = mem_u.init_word(i);
        fsum = $fopen("results_p2.csv", "a");
        if ($test$plusargs("vcd")) begin $dumpfile("cache_p2.vcd"); $dumpvars(0, tb_cache); end
        $display("\n%0s: %0d B, %0d B blocks, %0d sets x %0d way(s), latency %0d", ASSOC == 1 ? "direct-mapped" : "2-way LRU",
                 CACHE_BYTES, BLOCK_BYTES, SETS, ASSOC, MEM_LATENCY);
        $display("| trace      | acc   | hits  | hit rate | AMAT m | AMAT f | WT bytes| WB bytes|");

        tname = "directed"; cold_reset;
        access(0, 32'h1000, 0); access(0, 32'h1000, 0); access(0, 32'h1004, 0); access(0, 32'h100C, 0);
        access(1, 32'h1008, 32'hDEADBEEF); access(0, 32'h1008, 0);
        access(1, 32'h3000, 32'hCAFEF00D); access(0, 32'h3000, 0);
        access(0, 32'h1400, 0); access(0, 32'h1000, 0); access(0, 32'h1008, 0);
        if (mem_u.mem[32'h1008 >> 2] !== 32'hDEADBEEF || mem_u.mem[32'h3000 >> 2] !== 32'hCAFEF00D) begin
            errors = errors + 1; $display("ERROR write-through did not reach memory"); end
        report;
        if ($test$plusargs("vcd")) $dumpoff;

        tname = "lru"; cold_reset;   // A B A C A B: all in one set (1 KB apart)
        access(0, 32'h7000, 0); access(0, 32'h7400, 0); access(0, 32'h7000, 0);
        access(0, 32'h7800, 0); access(0, 32'h7000, 0); access(0, 32'h7400, 0);
        report;

        tname = "sequential"; cold_reset;
        for (k = 0; k < 512; k = k + 1) access(0, 32'h2000 + 4 * k, 0);
        report;

        tname = "repeated"; cold_reset;
        for (p = 0; p < 4; p = p + 1) for (k = 0; k < 128; k = k + 1) access(0, 32'h4000 + 4 * k, 0);
        report;

        tname = "random"; cold_reset; lfsr = 32'hACE12468;
        for (k = 0; k < 512; k = k + 1) begin lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
            access(0, {19'd0, lfsr[12:2], 2'b00}, 0); end
        report;

        tname = "conflict"; cold_reset;
        for (k = 0; k < 64; k = k + 1) begin access(0, 32'h5000, 0); access(0, 32'h5400, 0); end
        report;

        tname = "mixed_rw"; cold_reset; lfsr = 32'h13579BDF;
        for (k = 0; k < 512; k = k + 1) begin lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
            a = {21'd0, lfsr[10:2], 2'b00} + 32'h6000;
            if (lfsr[20:18] < 3'd3) access(1, a, lfsr ^ 32'hF0F00F0F); else access(0, a, 0); end
        report;

        tname = "write_loop"; cold_reset;   // 512 B array written 4 times: write locality
        for (p = 0; p < 4; p = p + 1) for (k = 0; k < 128; k = k + 1) access(1, 32'h8000 + 4 * k, p * 1000 + k);
        report;

        if (errors == 0) $display("ALL CHECKS PASSED"); else $display("FAILED: %0d errors", errors);
        $fclose(fsum); $finish;
    end
endmodule
