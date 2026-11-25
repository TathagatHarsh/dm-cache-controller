`timescale 1ns/1ps
// ============================================================================
// way_select.v  --  parallel tag compare + way select for a 2-way cache
//
//   hit0 = valid0 & (tag0 == tag)        hit1 = valid1 & (tag1 == tag)
//   hit  = hit0 | hit1                   hit_way = hit1
//   victim (way to refill on a miss):
//       an invalid way if there is one (way 0 first), else the LRU way
//   block_out = block of the hitting way (word select happens in the top)
// ============================================================================
module way_select #(
    parameter TAG_W      = 23,
    parameter BLOCK_BITS = 128
)(
    input  wire [TAG_W-1:0]      tag,
    input  wire [TAG_W-1:0]      tag0, tag1,
    input  wire                  valid0, valid1,
    input  wire                  lru,          // least recently used way
    input  wire [BLOCK_BITS-1:0] block0, block1,
    output wire                  hit,
    output wire                  hit_way,
    output wire                  victim_way,
    output wire [BLOCK_BITS-1:0] block_out
);
    wire hit0, hit1;
    tag_comparator #(.TAG_W(TAG_W)) c0 (.valid(valid0), .stored_tag(tag0), .req_tag(tag), .hit(hit0));
    tag_comparator #(.TAG_W(TAG_W)) c1 (.valid(valid1), .stored_tag(tag1), .req_tag(tag), .hit(hit1));

    assign hit        = hit0 | hit1;
    assign hit_way    = hit1;
    assign victim_way = !valid0 ? 1'b0 : !valid1 ? 1'b1 : lru;
    assign block_out  = hit1 ? block1 : block0;
endmodule
