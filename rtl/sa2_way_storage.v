`timescale 1ns/1ps
// ============================================================================
// sa2_way_storage.v  --  storage for a 2-way set-associative cache
//
//   way 0 : data RAM + tag RAM + valid RAM   (reuses the Phase I modules)
//   way 1 : data RAM + tag RAM + valid RAM
//   lru   : 1 bit per set -> number of the LEAST recently used way
//
//  Default 1 KB, 16 B blocks: 64 blocks / 2 ways = 32 sets per way.
//  Both ways are read in parallel (asynchronous read) so the two tag
//  compares happen in the same cycle. Only the selected way is written.
// ============================================================================
module sa2_way_storage #(
    parameter SETS       = 32,
    parameter INDEX_W    = 5,
    parameter TAG_W      = 23,
    parameter BLOCK_BITS = 128,
    parameter WSEL_W     = 2
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire [INDEX_W-1:0]    index,
    // write port (one way at a time)
    input  wire                  wr_way,       // which way to write
    input  wire                  block_we,     // refill whole block + tag + valid
    input  wire [BLOCK_BITS-1:0] block_wdata,
    input  wire [TAG_W-1:0]      tag_wdata,
    input  wire                  word_we,      // write hit: one word
    input  wire [WSEL_W-1:0]     word_sel,
    input  wire [31:0]           word_wdata,
    // LRU bit
    input  wire                  lru_we,
    input  wire                  lru_wdata,
    output wire                  lru,
    // parallel read of both ways
    output wire [BLOCK_BITS-1:0] block0, block1,
    output wire [TAG_W-1:0]      tag0,   tag1,
    output wire                  valid0, valid1
);
    // ---- way 0 / way 1: Phase I RAM modules, write-enabled per way ----
    cache_data_ram #(.LINES(SETS), .INDEX_W(INDEX_W), .BLOCK_BITS(BLOCK_BITS), .WSEL_W(WSEL_W)) d0 (
        .clk(clk), .index(index), .block_we(block_we & ~wr_way), .block_wdata(block_wdata),
        .word_we(word_we & ~wr_way), .word_sel(word_sel), .word_wdata(word_wdata), .block_rdata(block0));
    cache_data_ram #(.LINES(SETS), .INDEX_W(INDEX_W), .BLOCK_BITS(BLOCK_BITS), .WSEL_W(WSEL_W)) d1 (
        .clk(clk), .index(index), .block_we(block_we & wr_way), .block_wdata(block_wdata),
        .word_we(word_we & wr_way), .word_sel(word_sel), .word_wdata(word_wdata), .block_rdata(block1));

    cache_tag_ram #(.LINES(SETS), .INDEX_W(INDEX_W), .TAG_W(TAG_W)) t0 (
        .clk(clk), .index(index), .we(block_we & ~wr_way), .wdata(tag_wdata), .rdata(tag0));
    cache_tag_ram #(.LINES(SETS), .INDEX_W(INDEX_W), .TAG_W(TAG_W)) t1 (
        .clk(clk), .index(index), .we(block_we & wr_way), .wdata(tag_wdata), .rdata(tag1));

    valid_ram #(.LINES(SETS), .INDEX_W(INDEX_W)) v0 (.clk(clk), .rst(rst), .index(index), .set(block_we & ~wr_way), .valid(valid0));
    valid_ram #(.LINES(SETS), .INDEX_W(INDEX_W)) v1 (.clk(clk), .rst(rst), .index(index), .set(block_we &  wr_way), .valid(valid1));

    // ---- LRU bits: flip-flops so reset clears them (way 0 is LRU after reset) ----
    reg [SETS-1:0] lru_bits;
    always @(posedge clk) begin
        if (rst)         lru_bits        <= {SETS{1'b0}};
        else if (lru_we) lru_bits[index] <= lru_wdata;
    end
    assign lru = lru_bits[index];
endmodule
