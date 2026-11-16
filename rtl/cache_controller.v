`timescale 1ns/1ps
// ============================================================================
// cache_controller.v  --  4-state FSM that runs the direct-mapped cache
//
//  Policy : write-through, no-write-allocate (memory is always up to date,
//           so no dirty bits and no write-back are needed).
//
//  States
//   IDLE      : wait for cpu_req; latch address / data / we.
//   COMPARE   : tag RAM + valid RAM are read, comparator says HIT or MISS.
//                 read  hit  -> return word, cpu_ready = 1, back to IDLE
//                 read  miss -> go to ALLOCATE (fetch block from memory)
//                 write hit  -> update the word in cache, go to WRITE_MEM
//                 write miss -> (no allocate) go straight to WRITE_MEM
//   ALLOCATE  : hold mem_req until mem_ready, then write the whole block,
//               the tag and valid=1 into the cache and return the word.
//   WRITE_MEM : hold mem_req (mem_we=1) until mem_ready (write-through).
//
//  Timing with MEM_LATENCY = L:   read hit = 1 cycle,
//                                 read miss / any write = L + 2 cycles.
// ============================================================================
module cache_controller #(
    parameter ADDR_W   = 32,
    parameter OFFSET_W = 4
)(
    input  wire              clk,
    input  wire              rst,
    // ---- CPU side ----
    input  wire              cpu_req,     // 1-cycle request pulse
    input  wire              cpu_we,      // 1 = write, 0 = read
    input  wire [ADDR_W-1:0] cpu_addr,
    input  wire [31:0]       cpu_wdata,
    output wire              cpu_ready,   // access finished this cycle
    output wire              cpu_hit,     // valid together with cpu_ready
    output wire              rdata_sel_mem, // 1 = return word from memory block
    // ---- datapath status / control ----
    input  wire              hit,         // from tag_comparator
    output reg  [ADDR_W-1:0] addr_q,      // latched request address
    output reg  [31:0]       wdata_q,
    output wire              data_block_we,
    output wire              data_word_we,
    output wire              tag_we,
    output wire              valid_set,
    // ---- main-memory side ----
    output wire              mem_req,
    output wire              mem_we,
    output wire [ADDR_W-1:0] mem_addr,
    output wire [31:0]       mem_wdata,
    input  wire              mem_ready,
    // ---- debug / performance counters ----
    output reg  [1:0]        state,
    output reg  [31:0]       hit_count,
    output reg  [31:0]       miss_count
);
    localparam IDLE      = 2'd0,
               COMPARE   = 2'd1,
               ALLOCATE  = 2'd2,
               WRITE_MEM = 2'd3;

    reg we_q;
    reg hit_q;   // remembers whether the current access was a hit

    // ------------------------------------------------ state register + regs --
    always @(posedge clk) begin
        if (rst) begin
            state      <= IDLE;
            addr_q     <= 0;
            wdata_q    <= 0;
            we_q       <= 0;
            hit_q      <= 0;
            hit_count  <= 0;
            miss_count <= 0;
        end else begin
            case (state)
                IDLE: if (cpu_req) begin
                    addr_q  <= cpu_addr;
                    wdata_q <= cpu_wdata;
                    we_q    <= cpu_we;
                    state   <= COMPARE;
                end

                COMPARE: begin
                    hit_q <= hit;
                    if (hit) hit_count  <= hit_count  + 1;
                    else     miss_count <= miss_count + 1;

                    if (we_q)       state <= WRITE_MEM;   // write-through
                    else if (hit)   state <= IDLE;        // read hit done
                    else            state <= ALLOCATE;    // read miss
                end

                ALLOCATE:  if (mem_ready) state <= IDLE;
                WRITE_MEM: if (mem_ready) state <= IDLE;
            endcase
        end
    end

    // --------------------------------------------- outputs (combinational) --
    wire in_compare = (state == COMPARE);
    wire in_alloc   = (state == ALLOCATE);
    wire in_wmem    = (state == WRITE_MEM);

    // cache array writes
    assign data_word_we  = in_compare & we_q & hit;       // write hit
    assign data_block_we = in_alloc & mem_ready;          // refill
    assign tag_we        = data_block_we;
    assign valid_set     = data_block_we;

    // main-memory interface (Moore: depends on state only)
    assign mem_req   = in_alloc | in_wmem;
    assign mem_we    = in_wmem;
    assign mem_addr  = in_alloc ? {addr_q[ADDR_W-1:OFFSET_W], {OFFSET_W{1'b0}}} // block-aligned
                                : addr_q;
    assign mem_wdata = wdata_q;

    // CPU handshake
    assign cpu_ready     = (in_compare & ~we_q & hit) | ((in_alloc | in_wmem) & mem_ready);
    assign cpu_hit       = in_compare ? hit : hit_q;
    assign rdata_sel_mem = in_alloc;
endmodule
