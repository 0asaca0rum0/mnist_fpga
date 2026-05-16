`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/13/2026 05:58:16 PM
// Design Name: 
// Module Name: uart_tx
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


module uart_tx #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD = 9600
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  tx_data,
    input  wire        tx_start,
    output reg         tx,
    output reg         tx_done
);

    localparam BAUD_DIV = CLK_FREQ / BAUD;   // 10416

    reg [15:0]  baud_cnt;
    reg [3:0]   bit_cnt;   // 0=start,1..8=data,9=stop
    reg [7:0]   data_reg;
    reg         active;

    always @(posedge clk) begin
        if (!rst_n) begin
            tx      <= 1;
            tx_done <= 0;
            active  <= 0;
            baud_cnt<= 0;
            bit_cnt <= 0;
        end else begin
            tx_done <= 0;

            if (!active && tx_start) begin
                // latch data and start transmitting
                data_reg <= tx_data;
                active   <= 1;
                baud_cnt <= 0;
                bit_cnt  <= 0;
            end

            if (active) begin
                if (baud_cnt == BAUD_DIV - 1) begin
                    baud_cnt <= 0;
                    bit_cnt  <= bit_cnt + 1;
                    case (bit_cnt)
                        0: tx <= 0;            // start bit
                        1: tx <= data_reg[0];
                        2: tx <= data_reg[1];
                        3: tx <= data_reg[2];
                        4: tx <= data_reg[3];
                        5: tx <= data_reg[4];
                        6: tx <= data_reg[5];
                        7: tx <= data_reg[6];
                        8: tx <= data_reg[7];
                        9: begin
                            tx      <= 1;      // stop bit
                            tx_done <= 1;
                            active  <= 0;
                        end
                    endcase
                end else begin
                    baud_cnt <= baud_cnt + 1;
                end
            end
        end
    end
endmodule