`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/13/2026 05:59:14 PM
// Design Name: 
// Module Name: uart_echo
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

module uart_echo_top (
    input  wire clk,
    input  wire rst_n,          // external active-high button (pressed = 1)
    input  wire uart_rx,
    output wire uart_tx
);

    wire internal_rst_n = ~rst_n;   // make it active-low internally

    wire [7:0] rx_byte;
    wire       rx_done;

    uart_rx #(.CLK_FREQ(100_000_000)) receiver (
        .clk     (clk),
        .rst_n   (internal_rst_n),
        .rx      (uart_rx),
        .rx_data (rx_byte),
        .rx_done (rx_done)
    );

    uart_tx #(.CLK_FREQ(100_000_000)) transmitter (
        .clk      (clk),
        .rst_n    (internal_rst_n),
        .tx_data  (rx_byte),
        .tx_start (rx_done),
        .tx       (uart_tx),
        .tx_done  ()
    );

endmodule