`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/14/2026 01:20:08 PM
// Design Name: 
// Module Name: top_uart_test
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

module top_uart_cmd_test (
    input  wire clk,
    input  wire rst_n,          // active-high button (Basys 3)
    input  wire uart_rx,
    output wire uart_tx
);

    wire internal_rst_n = ~rst_n;

    // ---- UART ----
    wire [7:0] rx_byte;
    wire       rx_done;

    uart_rx #(.CLK_FREQ(100_000_000)) receiver (
        .clk     (clk),
        .rst_n   (internal_rst_n),
        .rx      (uart_rx),
        .rx_data (rx_byte),
        .rx_done (rx_done)
    );

    // ---- Command Parser ----
    wire [255:0] features;
    wire         start_inference;
    wire         fault_armed, fault_target;
    wire [5:0]   fault_bit_pos;
    wire         img_ack;
    wire [7:0]   tx_byte_parser;
    wire         tx_start_parser;

    cmd_parser parser (
        .clk             (clk),
        .rst_n           (internal_rst_n),
        .rx_byte         (rx_byte),
        .rx_done         (rx_done),
        .tx_byte         (tx_byte_parser),
        .tx_start        (tx_start_parser),
        .features        (features),
        .start_inference (start_inference),
        .result_valid    (1'b0),
        .result_class    (4'd0),
        .fault_armed     (fault_armed),
        .fault_target    (fault_target),
        .fault_bit_pos   (fault_bit_pos),
        .img_ack         (img_ack)
    );

    // ---- ACK handling & TX Mux ----
    reg         ack_start;
    reg [7:0]   ack_byte;
    reg         ack_done;

    // Detect new CMD_START to reset ACK state
    wire cmd_start_detect = rx_done && (rx_byte == 8'h01);

    always @(posedge clk) begin
        if (!internal_rst_n) begin
            ack_start <= 0;
            ack_byte  <= 0;
            ack_done  <= 0;
        end else begin
            if (cmd_start_detect) begin
                // New image transaction - clear any previous ACK state
                ack_start <= 0;
                ack_byte  <= 0;
                ack_done  <= 0;
            end else if (img_ack && !ack_done) begin
                ack_start <= 1;
                ack_byte  <= 8'hAA;
                ack_done  <= 1;
            end else begin
                ack_start <= 0;
            end
        end
    end

    wire tx_start_final = (ack_start) ? 1'b1 : tx_start_parser;
    wire [7:0] tx_byte_final = (ack_start) ? ack_byte : tx_byte_parser;

    uart_tx #(.CLK_FREQ(100_000_000)) transmitter (
        .clk      (clk),
        .rst_n    (internal_rst_n),
        .tx_data  (tx_byte_final),
        .tx_start (tx_start_final),
        .tx       (uart_tx),
        .tx_done  ()
    );

endmodule