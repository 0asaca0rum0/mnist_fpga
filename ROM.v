`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/14/2026 02:08:12 PM
// Design Name: 
// Module Name: ROM
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module weight_roms (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [10:0] addr,        // 11 bits to cover 0..1241
    output reg  [15:0] dout
);
    reg [15:0] mem [0:1241];
    integer i;
    initial begin
        $readmemh("w1.mem", mem, 0, 511);
        $readmemh("b1.mem", mem, 512, 543);
        $readmemh("w2.mem", mem, 544, 1055);
        $readmemh("b2.mem", mem, 1056, 1071);
        $readmemh("w3.mem", mem, 1072, 1231);
        $readmemh("b3.mem", mem, 1232, 1241);
    end
    always @(posedge clk) begin
        dout <= mem[addr];
    end
endmodule