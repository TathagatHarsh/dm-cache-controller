`timescale 1ns/1ps
// ============================================================================
// tag_comparator.v  --  HIT = valid AND (stored tag == requested tag)
// A line that was never filled (valid = 0) can never hit, even if the garbage
// in its tag RAM happens to match.
// ============================================================================
module tag_comparator #(
    parameter TAG_W = 22
)(
    input  wire             valid,
    input  wire [TAG_W-1:0] stored_tag,
    input  wire [TAG_W-1:0] req_tag,
    output wire             hit
);
    assign hit = valid & (stored_tag == req_tag);
endmodule
