`timescale 1ns/1ps
// ============================================================================
// sa2_cache.v  --  TOP of the 2-way set-associative LRU cache (synthesizable)
//
//  Same CPU and main-memory interface as dm_cache, so both can be dropped
//  into the same testbench and compared on identical traces.
//  Default: 1 KB, 16-byte blocks, 2 ways x 32 sets  ->  tag 23 | index 5 | offset 4
// ============================================================================
module sa2_cache #(
    parameter ADDR_W      = 32,
    parameter CACHE_BYTES = 1024,
    parameter BLOCK_BYTES = 16,
    parameter BLOCK_BITS  = BLOCK_BYTES * 8          // derived, do not override
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  cpu_req,
    input  wire                  cpu_we,
    input  wire [ADDR_W-1:0]     cpu_addr,
    input  wire [31:0]           cpu_wdata,
    output wire [31:0]           cpu_rdata,
    output wire                  cpu_ready,
    output wire                  cpu_hit,
    output wire                  mem_req,
    output wire                  mem_we,
    output wire [ADDR_W-1:0]     mem_addr,
    output wire [31:0]           mem_wdata,
    input  wire [BLOCK_BITS-1:0] mem_rdata,
    input  wire                  mem_ready,
    output wire [1:0]            state,
    output wire [31:0]           hit_count,
    output wire [31:0]           miss_count
);
    localparam SETS     = CACHE_BYTES / BLOCK_BYTES / 2;
    localparam OFFSET_W = $clog2(BLOCK_BYTES);
    localparam INDEX_W  = $clog2(SETS);
    localparam TAG_W    = ADDR_W - INDEX_W - OFFSET_W;
    localparam WSEL_W   = OFFSET_W - 2;

    wire [ADDR_W-1:0]     addr_q;
    wire [31:0]           wdata_q;
    wire [TAG_W-1:0]      tag    = addr_q[ADDR_W-1 : INDEX_W+OFFSET_W];
    wire [INDEX_W-1:0]    index  = addr_q[INDEX_W+OFFSET_W-1 : OFFSET_W];
    wire [WSEL_W-1:0]     word_sel = addr_q[OFFSET_W-1 : 2];
    wire [TAG_W-1:0]      tag0, tag1;
    wire [BLOCK_BITS-1:0] block0, block1, hit_block;
    wire                  valid0, valid1, lru, hit, hit_way, victim_way;
    wire                  wr_way, data_block_we, data_word_we, lru_we, lru_wdata, rdata_sel_mem;

    sa2_way_storage #(.SETS(SETS), .INDEX_W(INDEX_W), .TAG_W(TAG_W), .BLOCK_BITS(BLOCK_BITS), .WSEL_W(WSEL_W)) u_store (
        .clk(clk), .rst(rst), .index(index),
        .wr_way(wr_way), .block_we(data_block_we), .block_wdata(mem_rdata), .tag_wdata(tag),
        .word_we(data_word_we), .word_sel(word_sel), .word_wdata(wdata_q),
        .lru_we(lru_we), .lru_wdata(lru_wdata), .lru(lru),
        .block0(block0), .block1(block1), .tag0(tag0), .tag1(tag1), .valid0(valid0), .valid1(valid1));

    way_select #(.TAG_W(TAG_W), .BLOCK_BITS(BLOCK_BITS)) u_sel (
        .tag(tag), .tag0(tag0), .tag1(tag1), .valid0(valid0), .valid1(valid1), .lru(lru),
        .block0(block0), .block1(block1), .hit(hit), .hit_way(hit_way), .victim_way(victim_way), .block_out(hit_block));

    sa2_cache_controller #(.ADDR_W(ADDR_W), .OFFSET_W(OFFSET_W)) u_ctrl (
        .clk(clk), .rst(rst),
        .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
        .cpu_ready(cpu_ready), .cpu_hit(cpu_hit), .rdata_sel_mem(rdata_sel_mem),
        .hit(hit), .hit_way(hit_way), .victim_way(victim_way),
        .addr_q(addr_q), .wdata_q(wdata_q), .wr_way(wr_way),
        .data_block_we(data_block_we), .data_word_we(data_word_we), .lru_we(lru_we), .lru_wdata(lru_wdata),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_ready(mem_ready),
        .state(state), .hit_count(hit_count), .miss_count(miss_count));

    wire [BLOCK_BITS-1:0] src_block = rdata_sel_mem ? mem_rdata : hit_block;
    assign cpu_rdata = src_block[word_sel*32 +: 32];
endmodule
