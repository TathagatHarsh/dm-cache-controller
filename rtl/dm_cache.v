// ============================================================================
// dm_cache.v  --  TOP of the direct-mapped cache (synthesizable)
//
//                 +-------------- dm_cache -----------------------------+
//   CPU  <------> | cache_controller (FSM) --> addr_q --> addr_decoder   |
//                 |        ^ hit                 tag | index | word_sel  |
//                 |        |                         v                   |
//                 |  tag_comparator <-- tag RAM, valid RAM, data RAM     |
//                 +------------------------------------------------------+
//                                     |  mem_req / mem_ready
//                                     v
//                               main memory (external)
// ============================================================================
`timescale 1ns/1ps
module dm_cache #(
    parameter ADDR_W      = 32,
    parameter CACHE_BYTES = 1024,
    parameter BLOCK_BYTES = 16,
    parameter BLOCK_BITS  = BLOCK_BYTES * 8   // derived, do not override
)(
    input  wire              clk,
    input  wire              rst,
    // CPU interface
    input  wire              cpu_req,
    input  wire              cpu_we,
    input  wire [ADDR_W-1:0] cpu_addr,
    input  wire [31:0]       cpu_wdata,
    output wire [31:0]       cpu_rdata,
    output wire              cpu_ready,
    output wire              cpu_hit,
    // Main-memory interface
    output wire              mem_req,
    output wire              mem_we,
    output wire [ADDR_W-1:0] mem_addr,
    output wire [31:0]       mem_wdata,
    input  wire [BLOCK_BITS-1:0] mem_rdata,
    input  wire              mem_ready,
    // Performance counters / debug
    output wire [1:0]        state,
    output wire [31:0]       hit_count,
    output wire [31:0]       miss_count
);
    localparam LINES      = CACHE_BYTES / BLOCK_BYTES;
    localparam OFFSET_W   = $clog2(BLOCK_BYTES);
    localparam INDEX_W    = $clog2(LINES);
    localparam TAG_W      = ADDR_W - INDEX_W - OFFSET_W;
    localparam WSEL_W     = OFFSET_W - 2;

    wire [ADDR_W-1:0]     addr_q;
    wire [31:0]           wdata_q;
    wire [TAG_W-1:0]      tag, stored_tag;
    wire [INDEX_W-1:0]    index;
    wire [WSEL_W-1:0]     word_sel;
    wire                  valid, hit;
    wire                  data_block_we, data_word_we, tag_we, valid_set;
    wire                  rdata_sel_mem;
    wire [BLOCK_BITS-1:0] cache_block;

    addr_decoder #(.ADDR_W(ADDR_W), .CACHE_BYTES(CACHE_BYTES), .BLOCK_BYTES(BLOCK_BYTES))
    u_dec (.addr(addr_q), .tag(tag), .index(index), .word_sel(word_sel));

    cache_tag_ram #(.LINES(LINES), .INDEX_W(INDEX_W), .TAG_W(TAG_W))
    u_tag (.clk(clk), .index(index), .we(tag_we), .wdata(tag), .rdata(stored_tag));

    valid_ram #(.LINES(LINES), .INDEX_W(INDEX_W))
    u_valid (.clk(clk), .rst(rst), .index(index), .set(valid_set), .valid(valid));

    cache_data_ram #(.LINES(LINES), .INDEX_W(INDEX_W), .BLOCK_BITS(BLOCK_BITS), .WSEL_W(WSEL_W))
    u_data (.clk(clk), .index(index),
            .block_we(data_block_we), .block_wdata(mem_rdata),
            .word_we(data_word_we), .word_sel(word_sel), .word_wdata(wdata_q),
            .block_rdata(cache_block));

    tag_comparator #(.TAG_W(TAG_W))
    u_cmp (.valid(valid), .stored_tag(stored_tag), .req_tag(tag), .hit(hit));

    cache_controller #(.ADDR_W(ADDR_W), .OFFSET_W(OFFSET_W))
    u_ctrl (.clk(clk), .rst(rst),
            .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
            .cpu_ready(cpu_ready), .cpu_hit(cpu_hit), .rdata_sel_mem(rdata_sel_mem),
            .hit(hit), .addr_q(addr_q), .wdata_q(wdata_q),
            .data_block_we(data_block_we), .data_word_we(data_word_we),
            .tag_we(tag_we), .valid_set(valid_set),
            .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
            .mem_wdata(mem_wdata), .mem_ready(mem_ready),
            .state(state), .hit_count(hit_count), .miss_count(miss_count));

    // Read data: on a hit from the cache line, on a miss straight from the
    // block that memory is returning (saves one cycle vs. re-reading the cache)
    wire [BLOCK_BITS-1:0] src_block = rdata_sel_mem ? mem_rdata : cache_block;
    assign cpu_rdata = src_block[word_sel*32 +: 32];
endmodule
