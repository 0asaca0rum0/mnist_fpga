`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/14/2026 07:10:24 PM
// Design Name: 
// Module Name: pe
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

module pe #(
    parameter DATA_W = 16,
    parameter ACC_W  = 32
)(
    input wire clk,
    input wire rst_n,

    input wire signed [DATA_W-1:0] act_in,
    input wire signed [ACC_W-1:0]  psum_in,

    output reg signed [DATA_W-1:0] act_out,
    output reg signed [ACC_W-1:0]  psum_out,

    input wire load_weight,
    input wire signed [DATA_W-1:0] weight_in
);

    reg signed [DATA_W-1:0] weight;

    always @(posedge clk) begin
        if (!rst_n) begin
            weight   <= 0;
            act_out  <= 0;
            psum_out <= 0;
        end else begin
            if (load_weight)
                weight <= weight_in;

            act_out  <= act_in;
            psum_out <= psum_in + act_in * weight;
        end
    end

endmodule