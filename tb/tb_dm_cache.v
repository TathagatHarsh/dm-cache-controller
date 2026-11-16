// ============================================================================
// tb_dm_cache.v  --  self-checking testbench for the direct-mapped cache
//
//  * A golden reference model (ref_valid / ref_tag / ref_mem) predicts, for
//    EVERY access, whether it must HIT or MISS and what data must come back.
//    Any mismatch is reported as an ERROR.
//  * Runs 6 traces, resetting (cold cache) before each one:
//      T0 directed   : hand-written corner cases (also dumped to the VCD)
//      T1 sequential : 512 consecutive words (2 KB)    -> spatial locality
//      T2 repeated   : 128 words x 4 passes (512 B)    -> temporal locality
//      T3 random     : 512 random words in 8 KB        -> little locality
//      T4 conflict   : 2 addresses 1 KB apart, x64     -> thrashing
//      T5 mixed      : 512 random reads/writes in 2 KB (~3/8 writes)
//  * Prints hit rate, miss rate, measured AMAT and formula AMAT per trace,
//    writes results.csv (summary) and trace_log.csv (every access).
// ============================================================================
`timescale 1ns/1ps
module tb_dm_cache;
    parameter MEM_LATENCY = 10;
    localparam LINES = 64;

    reg         clk = 0, rst = 1;
    reg         cpu_req = 0, cpu_we = 0;
    reg  [31:0] cpu_addr = 0, cpu_wdata = 0;
    wire [31:0] cpu_rdata;
    wire        cpu_ready, cpu_hit;
    wire        mem_req, mem_we, mem_ready;
    wire [31:0] mem_addr, mem_wdata;
    wire [127:0] mem_rdata;
    wire [1:0]  state;
    wire [31:0] hit_count, miss_count;

    always #5 clk = ~clk;   // 100 MHz

    dm_cache dut (
        .clk(clk), .rst(rst),
        .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready), .cpu_hit(cpu_hit),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata), .mem_ready(mem_ready),
        .state(state), .hit_count(hit_count), .miss_count(miss_count));

    main_memory #(.MEM_LATENCY(MEM_LATENCY)) mem_u (
        .clk(clk), .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ready(mem_ready));

    // ------------------------------------------------ golden reference model
    reg [31:0] ref_mem   [0:16383];
    reg        ref_valid [0:LINES-1];
    reg [21:0] ref_tag   [0:LINES-1];

    integer i, errors = 0, fsum, flog;
    // per-trace statistics
    integer n_acc, n_hit, n_rd, n_rd_hit, cyc_rd_total, cyc_total;
    integer seq_no;
    reg [8*12-1:0] tname;

    task cold_reset;
        begin
            rst = 1; @(posedge clk); @(posedge clk); #1 rst = 0;
            for (i = 0; i < LINES; i = i + 1) ref_valid[i] = 0;
            n_acc = 0; n_hit = 0; n_rd = 0; n_rd_hit = 0;
            cyc_rd_total = 0; cyc_total = 0; seq_no = 0;
        end
    endtask

    // one CPU access, fully checked
    task access(input we, input [31:0] addr, input [31:0] wdata);
        reg [5:0]  idx;
        reg [21:0] tg;
        reg        exp_hit;
        reg [31:0] exp_data;
        integer    cyc;
        begin
            idx      = addr[9:4];
            tg       = addr[31:10];
            exp_hit  = ref_valid[idx] && (ref_tag[idx] == tg);
            exp_data = ref_mem[addr[15:2]];

            @(negedge clk);
            cpu_req = 1; cpu_we = we; cpu_addr = addr; cpu_wdata = wdata;
            @(negedge clk);
            cpu_req = 0;
            cyc = 1;
            while (!cpu_ready) begin @(negedge clk); cyc = cyc + 1; end

            // ---- checks ----
            if (cpu_hit !== exp_hit) begin
                errors = errors + 1;
                $display("ERROR %0s #%0d addr=%h expected %s got %s", tname, seq_no,
                         addr, exp_hit ? "HIT" : "MISS", cpu_hit ? "HIT" : "MISS");
            end
            if (!we && cpu_rdata !== exp_data) begin
                errors = errors + 1;
                $display("ERROR %0s #%0d addr=%h data expected %h got %h",
                         tname, seq_no, addr, exp_data, cpu_rdata);
            end

            // ---- update reference model ----
            if (we) ref_mem[addr[15:2]] = wdata;           // write-through
            else if (!exp_hit) begin                       // read miss: allocate
                ref_valid[idx] = 1; ref_tag[idx] = tg;
            end                                            // write miss: no-allocate

            // ---- statistics + log ----
            n_acc = n_acc + 1; cyc_total = cyc_total + cyc;
            if (exp_hit) n_hit = n_hit + 1;
            if (!we) begin
                n_rd = n_rd + 1; cyc_rd_total = cyc_rd_total + cyc;
                if (exp_hit) n_rd_hit = n_rd_hit + 1;
            end
            $fdisplay(flog, "%0s,%0d,%s,0x%h,0x%h,%0d,%0d,%0d,%0d", tname, seq_no,
                      we ? "W" : "R", addr, tg, idx, addr[3:2], cpu_hit, cyc);
            seq_no = seq_no + 1;
            @(posedge clk);   // controller returns to IDLE
        end
    endtask

    task report;
        real hr, mr, amat_meas, amat_formula;
        begin
            @(negedge clk);   // let the last counter update (NBA) settle
            hr = 100.0 * n_hit / n_acc;
            mr = 100.0 - hr;
            amat_meas    = (n_rd > 0) ? 1.0 * cyc_rd_total / n_rd : 0;
            amat_formula = (n_rd > 0) ? 1.0 + (1.0 - 1.0 * n_rd_hit / n_rd) * (MEM_LATENCY + 1) : 0;
            if (hit_count !== n_hit || miss_count !== n_acc - n_hit) begin
                errors = errors + 1;
                $display("ERROR %0s hw counters hit=%0d miss=%0d, expected %0d/%0d",
                         tname, hit_count, miss_count, n_hit, n_acc - n_hit);
            end
            $display("| %10s | %6d | %5d | %5d | %7.2f%% | %7.2f%% | %6.2f | %6.2f |",
                     tname, n_acc, n_hit, n_acc - n_hit, hr, mr, amat_meas, amat_formula);
            $fdisplay(fsum, "%0s,%0d,%0d,%0d,%0.2f,%0.2f,%0.3f,%0.3f", tname, n_acc, n_hit,
                      n_acc - n_hit, hr, mr, amat_meas, amat_formula);
        end
    endtask

    // ------------------------------------------------------------- stimulus
    reg [31:0] lfsr, a;
    integer k, p;

    initial begin
        for (i = 0; i < 16384; i = i + 1) ref_mem[i] = mem_u.init_word(i);
        fsum = $fopen("results.csv", "w");
        flog = $fopen("trace_log.csv", "w");
        $fdisplay(fsum, "trace,accesses,hits,misses,hit_rate_pct,miss_rate_pct,amat_measured_cycles,amat_formula_cycles");
        $fdisplay(flog, "trace,seq,op,addr,tag,index,word,hit,cycles");

        $dumpfile("dm_cache.vcd");
        $dumpvars(0, tb_dm_cache);

        $display("\nDirect-mapped cache: 1 KB, 16 B blocks, 64 lines, write-through / no-write-allocate, MEM_LATENCY=%0d", MEM_LATENCY);
        $display("+------------+--------+-------+-------+----------+----------+--------+--------+");
        $display("| trace      | access |  hits | miss  | hit rate | miss rate| AMAT m | AMAT f |");
        $display("+------------+--------+-------+-------+----------+----------+--------+--------+");

        // ---- T0 directed corner cases ------------------------------------
        tname = "directed"; cold_reset;
        access(0, 32'h0000_1000, 0);             // cold miss (valid bit = 0)
        access(0, 32'h0000_1000, 0);             // temporal hit, same word
        access(0, 32'h0000_1004, 0);             // spatial hit, same block
        access(0, 32'h0000_100C, 0);             // spatial hit, last word
        access(1, 32'h0000_1008, 32'hDEAD_BEEF); // write HIT -> cache + memory
        access(0, 32'h0000_1008, 0);             // read back new value (hit)
        access(1, 32'h0000_3000, 32'hCAFE_F00D); // write MISS -> memory only
        access(0, 32'h0000_3000, 0);             // read -> MISS (no-allocate), sees CAFEF00D
        access(0, 32'h0000_1400, 0);             // same index as 0x1000, other tag -> MISS, evicts
        access(0, 32'h0000_1000, 0);             // conflict MISS again
        access(0, 32'h0000_1008, 0);             // hit, DEADBEEF survived via write-through
        if (mem_u.mem[32'h1008 >> 2] !== 32'hDEAD_BEEF || mem_u.mem[32'h3000 >> 2] !== 32'hCAFE_F00D) begin
            errors = errors + 1; $display("ERROR write-through did not reach main memory");
        end
        report;
        $dumpoff;   // keep the VCD small: waveform = directed test only

        // ---- T1 sequential ----------------------------------------------
        tname = "sequential"; cold_reset;
        for (k = 0; k < 512; k = k + 1) access(0, 32'h0000_2000 + 4*k, 0);
        report;

        // ---- T2 repeated (loop over 512 B, 4 passes) ---------------------
        tname = "repeated"; cold_reset;
        for (p = 0; p < 4; p = p + 1)
            for (k = 0; k < 128; k = k + 1) access(0, 32'h0000_4000 + 4*k, 0);
        report;

        // ---- T3 random (8 KB window) --------------------------------------
        tname = "random"; cold_reset; lfsr = 32'hACE1_2468;
        for (k = 0; k < 512; k = k + 1) begin
            lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
            access(0, {19'd0, lfsr[12:2], 2'b00}, 0);
        end
        report;

        // ---- T4 conflict / thrashing --------------------------------------
        tname = "conflict"; cold_reset;
        for (k = 0; k < 64; k = k + 1) begin
            access(0, 32'h0000_5000, 0);
            access(0, 32'h0000_5400, 0);         // +1 KB -> same index, other tag
        end
        report;

        // ---- T5 mixed reads / writes --------------------------------------
        tname = "mixed_rw"; cold_reset; lfsr = 32'h1357_9BDF;
        for (k = 0; k < 512; k = k + 1) begin
            lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
            a = {21'd0, lfsr[10:2], 2'b00} + 32'h0000_6000;
            if (lfsr[20:18] < 3'd3) access(1, a, lfsr ^ 32'hF0F0_0F0F);  // ~3/8 writes
            else                    access(0, a, 0);
        end
        report;

        $display("+------------+--------+-------+-------+----------+----------+--------+--------+");
        $display("AMAT m = measured avg read latency (cycles); AMAT f = 1 + read_miss_rate x %0d", MEM_LATENCY + 1);
        if (errors == 0) $display("\nALL CHECKS PASSED (every access matched the reference model)\n");
        else             $display("\nFAILED: %0d errors\n", errors);
        $fclose(fsum); $fclose(flog);
        $finish;
    end
endmodule
