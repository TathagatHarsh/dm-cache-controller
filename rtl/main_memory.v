`timescale 1ns/1ps
// ============================================================================
// main_memory.v  --  behavioural main memory (DRAM model) for simulation
//
//  * MEM_WORDS 32-bit words (default 16K words = 64 KB, address bits above
//    that wrap around).
//  * Every request takes MEM_LATENCY cycles, then mem_ready pulses for one
//    cycle. Reads return a whole block (BLOCK_WORDS words) on one wide bus;
//    writes store one 32-bit word.
//  * Contents are initialised with init_word(i) so the testbench can predict
//    every value it should read back.
// ============================================================================
module main_memory #(
    parameter ADDR_W      = 32,
    parameter MEM_WORDS   = 16384,
    parameter MEM_LATENCY = 10,
    parameter BLOCK_WORDS = 4          // words per cache block (block size / 4)
)(
    input  wire              clk,
    input  wire              mem_req,
    input  wire              mem_we,
    input  wire [ADDR_W-1:0] mem_addr,
    input  wire [31:0]       mem_wdata,
    output reg  [32*BLOCK_WORDS-1:0] mem_rdata,
    output reg               mem_ready
);
    localparam AW = $clog2(MEM_WORDS);

    reg [31:0] mem [0:MEM_WORDS-1];
    reg [7:0]  cnt;

    // Same formula is used by the testbench reference model.
    function [31:0] init_word(input integer i);
        init_word = (i * 32'h9E3779B1) ^ 32'h5A5A_5A5A;
    endfunction

    integer i;
    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1) mem[i] = init_word(i);
        mem_ready = 0;
        mem_rdata = 0;
        cnt       = 0;
    end

    wire [AW-1:0] waddr = mem_addr[AW+1:2];             // word address
    wire [AW-1:0] baddr = waddr & ~(BLOCK_WORDS - 1);   // first word of block

    always @(posedge clk) begin
        mem_ready <= 1'b0;
        if (mem_req && !mem_ready) begin
            if (cnt == MEM_LATENCY - 1) begin
                cnt       <= 0;
                mem_ready <= 1'b1;
                if (mem_we)
                    mem[waddr] <= mem_wdata;
                else
                    for (i = 0; i < BLOCK_WORDS; i = i + 1)
                        mem_rdata[32*i +: 32] <= mem[baddr + i];
            end else
                cnt <= cnt + 1;
        end else
            cnt <= 0;
    end
endmodule
