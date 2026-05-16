`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/14/2026 06:28:27 PM
// Design Name: 
// Module Name: test_top
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

module rom_test_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        uart_rx,
    output wire        uart_tx,
    output wire [3:0]  debug_led
);

    wire internal_rst_n = ~rst_n;

    // ---- UART ----
    wire [7:0] rx_byte;
    wire       rx_done;
    wire [7:0] tx_byte;
    wire       tx_start;
    wire       tx_done;   // ADDED

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
        .tx_data  (tx_byte),
        .tx_start (tx_start),
        .tx       (uart_tx),
        .tx_done  (tx_done)
    );

    // ---- ROM ----
    wire [10:0] rom_addr;
    wire [15:0] rom_dout;
    weight_roms rom (
        .clk   (clk),
        .rst_n (internal_rst_n),
        .addr  (rom_addr),
        .dout  (rom_dout)
    );

    // ---- FSM ----
    localparam IDLE      = 0;
    localparam READ_ADDR = 1;
    localparam WAIT_ROM  = 2;
    localparam SEND_LO   = 3;
    localparam WAIT_TX1  = 4;   // NEW
    localparam SEND_HI   = 5;
    localparam WAIT_TX2  = 6;   // NEW

    reg [2:0] state;
    reg [10:0] address;
    reg [7:0]  byte_cnt;
    reg [15:0] data_reg;

    reg        tx_start_reg;
    reg [7:0]  tx_byte_reg;

    assign tx_start = tx_start_reg;
    assign tx_byte  = tx_byte_reg;
    assign rom_addr = address;

    always @(posedge clk) begin
        if (!internal_rst_n) begin
            state <= IDLE;
            address <= 0;
            byte_cnt <= 0;
            tx_start_reg <= 0;
        end else begin
            tx_start_reg <= 0;   // pulse by default

            case (state)
                IDLE: begin
                    if (rx_done && rx_byte == 8'h03) begin
                        state <= READ_ADDR;
                        byte_cnt <= 0;
                    end
                end

                READ_ADDR: begin
                    if (rx_done) begin
                        if (byte_cnt == 0) begin
                            address[7:0] <= rx_byte;
                            byte_cnt <= 1;
                        end else begin
                            address[10:8] <= rx_byte[2:0];
                            byte_cnt <= 0;
                            state <= WAIT_ROM;
                        end
                    end
                end

                WAIT_ROM: begin
                    // ROM data valid next cycle, capture it
                    data_reg <= rom_dout;
                    state <= SEND_LO;
                end

                SEND_LO: begin
                    tx_byte_reg <= data_reg[7:0];
                    tx_start_reg <= 1;
                    state <= WAIT_TX1;
                end

                WAIT_TX1: begin
                    // Wait for transmitter to finish
                    if (tx_done)
                        state <= SEND_HI;
                end

                SEND_HI: begin
                    tx_byte_reg <= data_reg[15:8];
                    tx_start_reg <= 1;
                    state <= WAIT_TX2;
                end

                WAIT_TX2: begin
                    if (tx_done)
                        state <= IDLE;
                end
            endcase
        end
    end

    // Debug LEDs: show FSM state[2:0] and tx_start
    assign debug_led = {state[2:0], tx_start_reg};

endmodule