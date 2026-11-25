`timescale 1ns/1ps
// ============================================================================
// sa2_cache_controller.v  --  FSM for the 2-way set-associative LRU cache
//
//  Same 4 states and same write-through / no-write-allocate policy as the
//  direct-mapped controller, plus:
//    * on a read miss it remembers the VICTIM way and refills that way
//    * it updates the set's LRU bit on every hit and every refill:
//          lru <= the way that was NOT just used
//
//   IDLE      : latch request
//   COMPARE   : hit / miss decided (both ways compared in parallel)
//                 read hit  -> data, LRU update, done (1 cycle)
//                 read miss -> latch victim, ALLOCATE
//                 write     -> (hit: update word in hit way + LRU) WRITE_MEM
//   ALLOCATE  : wait mem_ready, refill victim way, LRU update, return word
//   WRITE_MEM : wait mem_ready (write-through)
// ============================================================================
module sa2_cache_controller #(
    parameter ADDR_W   = 32,
    parameter OFFSET_W = 4
)(
    input  wire              clk,
    input  wire              rst,
    // CPU side
    input  wire              cpu_req,
    input  wire              cpu_we,
    input  wire [ADDR_W-1:0] cpu_addr,
    input  wire [31:0]       cpu_wdata,
    output wire              cpu_ready,
    output wire              cpu_hit,
    output wire              rdata_sel_mem,
    // datapath status
    input  wire              hit,
    input  wire              hit_way,
    input  wire              victim_way,
    // datapath control
    output reg  [ADDR_W-1:0] addr_q,
    output reg  [31:0]       wdata_q,
    output wire              wr_way,
    output wire              data_block_we,
    output wire              data_word_we,
    output wire              lru_we,
    output wire              lru_wdata,
    // memory side
    output wire              mem_req,
    output wire              mem_we,
    output wire [ADDR_W-1:0] mem_addr,
    output wire [31:0]       mem_wdata,
    input  wire              mem_ready,
    // debug / counters
    output reg  [1:0]        state,
    output reg  [31:0]       hit_count,
    output reg  [31:0]       miss_count
);
    localparam IDLE = 2'd0, COMPARE = 2'd1, ALLOCATE = 2'd2, WRITE_MEM = 2'd3;

    reg we_q, hit_q, victim_q;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE; addr_q <= 0; wdata_q <= 0; we_q <= 0; hit_q <= 0; victim_q <= 0;
            hit_count <= 0; miss_count <= 0;
        end else begin
            case (state)
                IDLE: if (cpu_req) begin
                    addr_q <= cpu_addr; wdata_q <= cpu_wdata; we_q <= cpu_we; state <= COMPARE;
                end
                COMPARE: begin
                    hit_q    <= hit;
                    victim_q <= victim_way;
                    if (hit) hit_count  <= hit_count  + 1;
                    else     miss_count <= miss_count + 1;
                    if (we_q)     state <= WRITE_MEM;
                    else if (hit) state <= IDLE;
                    else          state <= ALLOCATE;
                end
                ALLOCATE:  if (mem_ready) state <= IDLE;
                WRITE_MEM: if (mem_ready) state <= IDLE;
            endcase
        end
    end

    wire in_compare = (state == COMPARE);
    wire in_alloc   = (state == ALLOCATE);
    wire in_wmem    = (state == WRITE_MEM);

    // which way gets written / touched
    assign wr_way        = in_alloc ? victim_q : hit_way;
    assign data_word_we  = in_compare & we_q & hit;            // write hit
    assign data_block_we = in_alloc & mem_ready;               // refill victim
    // LRU: the way just used becomes MRU, so the other one becomes LRU
    assign lru_we        = (in_compare & hit) | data_block_we;
    assign lru_wdata     = ~wr_way;

    assign mem_req   = in_alloc | in_wmem;
    assign mem_we    = in_wmem;
    assign mem_addr  = in_alloc ? {addr_q[ADDR_W-1:OFFSET_W], {OFFSET_W{1'b0}}} : addr_q;
    assign mem_wdata = wdata_q;

    assign cpu_ready     = (in_compare & ~we_q & hit) | ((in_alloc | in_wmem) & mem_ready);
    assign cpu_hit       = in_compare ? hit : hit_q;
    assign rdata_sel_mem = in_alloc;
endmodule
