`timescale 1ns/1ps
// ============================================================================
// cache_rams.v  --  the three storage arrays of the cache
//
//   cache_data_ram : LINES x BLOCK_BITS  (64 x 128 bits = 1 KB of data)
//   cache_tag_ram  : LINES x TAG_W       (64 x 22 bits)
//   valid_ram      : LINES x 1           (64 bits, cleared on reset)
//
// Reads are combinational (asynchronous) so lookup + compare fit in one cycle.
// Writes happen on the rising clock edge.
// ============================================================================

// ---------------------------------------------------------------- data RAM --
module cache_data_ram #(
    parameter LINES      = 64,
    parameter INDEX_W    = 6,
    parameter BLOCK_BITS = 128,
    parameter WSEL_W     = 2
)(
    input  wire                  clk,
    input  wire [INDEX_W-1:0]    index,
    // full-block write (refill from main memory on a miss)
    input  wire                  block_we,
    input  wire [BLOCK_BITS-1:0] block_wdata,
    // single-word write (CPU write hit)
    input  wire                  word_we,
    input  wire [WSEL_W-1:0]     word_sel,
    input  wire [31:0]           word_wdata,
    output wire [BLOCK_BITS-1:0] block_rdata
);
    reg [BLOCK_BITS-1:0] mem [0:LINES-1];

    always @(posedge clk) begin
        if (block_we)
            mem[index] <= block_wdata;
        else if (word_we)
            mem[index][word_sel*32 +: 32] <= word_wdata;
    end

    assign block_rdata = mem[index];
endmodule

// ----------------------------------------------------------------- tag RAM --
module cache_tag_ram #(
    parameter LINES   = 64,
    parameter INDEX_W = 6,
    parameter TAG_W   = 22
)(
    input  wire               clk,
    input  wire [INDEX_W-1:0] index,
    input  wire               we,
    input  wire [TAG_W-1:0]   wdata,
    output wire [TAG_W-1:0]   rdata
);
    reg [TAG_W-1:0] mem [0:LINES-1];

    always @(posedge clk)
        if (we) mem[index] <= wdata;

    assign rdata = mem[index];
endmodule

// --------------------------------------------------------------- valid RAM --
// Kept in flip-flops (not block RAM) so that every bit can be cleared in a
// single cycle on reset -> the cache always starts "cold" and correct.
module valid_ram #(
    parameter LINES   = 64,
    parameter INDEX_W = 6
)(
    input  wire               clk,
    input  wire               rst,
    input  wire [INDEX_W-1:0] index,
    input  wire               set,
    output wire               valid
);
    reg [LINES-1:0] v;

    always @(posedge clk) begin
        if (rst)      v        <= {LINES{1'b0}};
        else if (set) v[index] <= 1'b1;
    end

    assign valid = v[index];
endmodule
