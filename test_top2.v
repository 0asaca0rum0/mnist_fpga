`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/14/2026 06:52:52 PM
// Design Name: 
// Module Name: test_top2
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


module sa_test_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        uart_rx,
    output wire        uart_tx,
    output wire [3:0]  debug_led
);

    wire internal_rst_n = ~rst_n;

    // UART
    wire [7:0] rx_byte;
    wire       rx_done;
    wire [7:0] tx_byte;
    wire       tx_start;
    wire       tx_done;

    uart_rx #(.CLK_FREQ(100_000_000)) rx (
        .clk(clk), .rst_n(internal_rst_n), .rx(uart_rx),
        .rx_data(rx_byte), .rx_done(rx_done)
    );

    uart_tx #(.CLK_FREQ(100_000_000)) tx (
        .clk(clk), .rst_n(internal_rst_n),
        .tx_data(tx_byte), .tx_start(tx_start),
        .tx(uart_tx), .tx_done(tx_done)
    );

    // Systolic array
    wire        sa_load, sa_start, sa_done;
    wire [1:0]  sa_load_row, sa_load_col;
    wire [15:0] sa_weight;
    wire [15:0] sa_in0, sa_in1, sa_in2, sa_in3;
    wire [31:0] sa_out0, sa_out1, sa_out2, sa_out3;

    systolic_array_4x4 #(16,32) sa (
        .clk(clk), .rst_n(internal_rst_n),
        .load(sa_load), .load_row(sa_load_row), .load_col(sa_load_col), .weight_in(sa_weight),
        .in_data0(sa_in0), .in_data1(sa_in1), .in_data2(sa_in2), .in_data3(sa_in3),
        .start(sa_start), .done(sa_done),
        .out_acc0(sa_out0), .out_acc1(sa_out1), .out_acc2(sa_out2), .out_acc3(sa_out3)
    );

    // FSM
    localparam IDLE       = 0;
    localparam LOAD_W     = 1;   // receive 16 weights (32 bytes)
    localparam LOAD_X     = 2;   // receive 4 inputs (8 bytes)
    localparam RUN_SA     = 3;   // start and wait for done
    localparam SEND_RES   = 4;   // send 16 bytes of results (4x32-bit LE)
    localparam WAIT_TX    = 5;

    reg [3:0] state;
    reg [7:0] byte_idx;     // generic byte counter
    reg [4:0] word_idx;     // for weights or inputs
    reg [1:0] w_row, w_col;
    reg [15:0] tmp_low;
    reg [15:0] in_vec [0:3];
    reg [31:0] results [0:3];
    reg [7:0] send_byte;

    // Output registers
    reg        sa_load_r, sa_start_r;
    reg [1:0]  sa_load_row_r, sa_load_col_r;
    reg [15:0] sa_weight_r;
    reg [15:0] sa_in0_r, sa_in1_r, sa_in2_r, sa_in3_r;
    reg        tx_start_r;
    reg [7:0]  tx_byte_r;

    assign sa_load = sa_load_r;
    assign sa_start = sa_start_r;
    assign sa_load_row = sa_load_row_r;
    assign sa_load_col = sa_load_col_r;
    assign sa_weight = sa_weight_r;
    assign sa_in0 = sa_in0_r;
    assign sa_in1 = sa_in1_r;
    assign sa_in2 = sa_in2_r;
    assign sa_in3 = sa_in3_r;
    assign tx_start = tx_start_r;
    assign tx_byte = tx_byte_r;

    always @(posedge clk) begin
        if (!internal_rst_n) begin
            state <= IDLE;
            byte_idx <= 0;
            word_idx <= 0;
            w_row <= 0; w_col <= 0;
            sa_load_r <= 0;
            sa_start_r <= 0;
            tx_start_r <= 0;
        end else begin
            sa_load_r <= 0;
            sa_start_r <= 0;
            tx_start_r <= 0;

            case (state)
                IDLE: begin
                    if (rx_done && rx_byte == 8'h10) begin
                        state <= LOAD_W;
                        byte_idx <= 0;
                        word_idx <= 0;
                        w_row <= 0; w_col <= 0;
                    end
                end

                LOAD_W: begin
                    if (rx_done) begin
                        if (byte_idx == 0) begin
                            tmp_low[7:0] <= rx_byte;
                            byte_idx <= 1;
                        end else begin
                            // Full 16-bit weight received
                            sa_load_r <= 1;
                            sa_load_row_r <= w_row;
                            sa_load_col_r <= w_col;
                            sa_weight_r <= {rx_byte, tmp_low[7:0]};
                            byte_idx <= 0;
                            // Advance cell
                            if (w_col == 3) begin
                                w_col <= 0;
                                if (w_row == 3) begin
                                    w_row <= 0;
                                    state <= LOAD_X;
                                    word_idx <= 0;
                                    byte_idx <= 0;
                                end else
                                    w_row <= w_row + 1;
                            end else
                                w_col <= w_col + 1;
                        end
                    end
                end

                LOAD_X: begin
                    if (rx_done) begin
                        if (byte_idx == 0) begin
                            tmp_low[7:0] <= rx_byte;
                            byte_idx <= 1;
                        end else begin
                            in_vec[word_idx] <= {rx_byte, tmp_low[7:0]};
                            byte_idx <= 0;
                            if (word_idx == 3) begin
                                sa_in0_r <= in_vec[0];
                                sa_in1_r <= in_vec[1];
                                sa_in2_r <= in_vec[2];
                                sa_in3_r <= in_vec[3];
                                sa_start_r <= 1;
                                state <= RUN_SA;
                            end else
                                word_idx <= word_idx + 1;
                        end
                    end
                end

                RUN_SA: begin
                    if (sa_done) begin
                        results[0] <= sa_out0;
                        results[1] <= sa_out1;
                        results[2] <= sa_out2;
                        results[3] <= sa_out3;
                        state <= SEND_RES;
                        send_byte <= 0;
                    end
                end

                SEND_RES: begin
                    if (!tx_start_r) begin   // not currently transmitting
                        // Select byte from results array
                        case (send_byte[3:2])   // which result (0-3)
                            2'd0: tx_byte_r <= results[0][{send_byte[1:0], 3'b000} +: 8];
                            2'd1: tx_byte_r <= results[1][{send_byte[1:0], 3'b000} +: 8];
                            2'd2: tx_byte_r <= results[2][{send_byte[1:0], 3'b000} +: 8];
                            2'd3: tx_byte_r <= results[3][{send_byte[1:0], 3'b000} +: 8];
                        endcase
                        tx_start_r <= 1;
                        state <= WAIT_TX;
                    end
                end

                WAIT_TX: begin
                    if (tx_done) begin
                        if (send_byte == 15) begin
                            state <= IDLE;
                        end else begin
                            send_byte <= send_byte + 1;
                            state <= SEND_RES;
                        end
                    end
                end
            endcase
        end
    end

    assign debug_led = state[3:0];

endmodule