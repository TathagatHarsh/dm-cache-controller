// ============================================================================
// addr_decoder.v  --  splits a 32-bit byte address into TAG | INDEX | OFFSET
//
//  Default config: 1 KB cache, 16-byte blocks, 32-bit address
//    lines      = 1024 / 16  = 64      -> INDEX_W  = 6
//    block size = 16 bytes             -> OFFSET_W = 4  (2 word-select + 2 byte)
//    TAG_W      = 32 - 6 - 4 = 22
//
//   31                     10 9        4 3     2 1    0
//  +-------------------------+----------+-------+------+
//  |        TAG (22)         | INDEX(6) | WORD  | BYTE |
//  +-------------------------+----------+-------+------+
// ============================================================================
`timescale 1ns/1ps
module addr_decoder #(
    parameter ADDR_W      = 32,
    parameter CACHE_BYTES = 1024,
    parameter BLOCK_BYTES = 16,
    // derived widths (do not override)
    parameter OFFSET_W    = $clog2(BLOCK_BYTES),
    parameter INDEX_W     = $clog2(CACHE_BYTES / BLOCK_BYTES),
    parameter TAG_W       = ADDR_W - INDEX_W - OFFSET_W,
    parameter WSEL_W      = OFFSET_W - 2          // selects 32-bit word in block
)(
    input  wire [ADDR_W-1:0]   addr,
    output wire [TAG_W-1:0]    tag,
    output wire [INDEX_W-1:0]  index,
    output wire [WSEL_W-1:0]   word_sel
);
    assign tag      = addr[ADDR_W-1          : INDEX_W+OFFSET_W];
    assign index    = addr[INDEX_W+OFFSET_W-1 : OFFSET_W];
    assign word_sel = addr[OFFSET_W-1        : 2];
endmodule
