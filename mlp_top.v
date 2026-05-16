`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/14/2026 02:53:19 PM
// Design Name: 
// Module Name: mlp_top
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


module mlp_fpga_top (
    input  wire clk,
    input  wire rst_n,
    input  wire uart_rx,
    output wire uart_tx,
    output wire [3:0] debug_led
);
    wire internal_rst_n = ~rst_n;

    // ---- UART ----
    wire [7:0] rx_byte;
    wire       rx_done;
    wire [7:0] tx_byte;
    wire       tx_start;

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
        .tx_done  ()
    );

    // ---- Command parser ----
    wire [255:0] features;
    wire         start_inference;
    wire         result_valid_mlp_pulse;
    wire [3:0]   result_class_mlp_pulse;
    wire         fault_armed, fault_target;
    wire [5:0]   fault_bit_pos;

    cmd_parser parser (
        .clk             (clk),
        .rst_n           (internal_rst_n),
        .rx_byte         (rx_byte),
        .rx_done         (rx_done),
        .tx_byte         (tx_byte),
        .tx_start        (tx_start),
        .features        (features),
        .start_inference (start_inference),
        .result_valid    (result_latched_valid),   // use latched version
        .result_class    (result_latched_class),   // use latched version
        .fault_armed     (fault_armed),
        .fault_target    (fault_target),
        .fault_bit_pos   (fault_bit_pos),
        .img_ack         ()
    );

    // ---- Result latch (captures pulse and holds until next start_inference) ----
    reg [3:0] result_latched_class;
    reg       result_latched_valid;
    always @(posedge clk) begin
        if (!internal_rst_n) begin
            result_latched_valid <= 0;
            result_latched_class <= 0;
        end else begin
            if (start_inference) begin
                result_latched_valid <= 0;   // clear on new image
            end else if (result_valid_mlp_pulse) begin
                result_latched_valid <= 1;
                result_latched_class <= result_class_mlp_pulse;
            end
        end
    end

    // ---- Weight ROM ----
    wire [10:0] rom_addr;
    wire [15:0] rom_dout;

    weight_roms wrom (
        .clk   (clk),
        .rst_n (internal_rst_n),
        .addr  (rom_addr),
        .dout  (rom_dout)
    );

    // ---- Systolic control ----
    wire        sa_load, sa_start, sa_done;
    wire [1:0]  sa_load_row, sa_load_col;
    wire [15:0] sa_weight;
    wire [15:0] sa_in0, sa_in1, sa_in2, sa_in3;
    wire [31:0] sa_out0, sa_out1, sa_out2, sa_out3;
    wire        debug_inference_active, debug_result_valid, debug_done_state;

    systolic_control #(.DATA_W(16), .ACC_W(32)) ctrl (
        .clk             (clk),
        .rst_n           (internal_rst_n),
        .features        (features),
        .start_inference (start_inference),
        .rom_addr        (rom_addr),
        .rom_dout        (rom_dout),
        .sa_load         (sa_load),
        .sa_load_row     (sa_load_row),
        .sa_load_col     (sa_load_col),
        .sa_weight       (sa_weight),
        .sa_in0          (sa_in0),
        .sa_in1          (sa_in1),
        .sa_in2          (sa_in2),
        .sa_in3          (sa_in3),
        .sa_start        (sa_start),
        .sa_done         (sa_done),
        .sa_out0         (sa_out0),
        .sa_out1         (sa_out1),
        .sa_out2         (sa_out2),
        .sa_out3         (sa_out3),
        .result_valid    (result_valid_mlp_pulse),
        .result_class    (result_class_mlp_pulse),
        .debug_inference_active (debug_inference_active),
        .debug_result_valid     (debug_result_valid),
        .debug_done_state       (debug_done_state)
    );

    // ---- Systolic array 4x4 ----
    systolic_array_4x4 #(.DATA_W(16), .ACC_W(32)) sa (
        .clk       (clk),
        .rst_n     (internal_rst_n),
        .load      (sa_load),
        .load_row  (sa_load_row),
        .load_col  (sa_load_col),
        .weight_in (sa_weight),
        .in_data0  (sa_in0),
        .in_data1  (sa_in1),
        .in_data2  (sa_in2),
        .in_data3  (sa_in3),
        .start     (sa_start),
        .done      (sa_done),
        .out_acc0  (sa_out0),
        .out_acc1  (sa_out1),
        .out_acc2  (sa_out2),
        .out_acc3  (sa_out3)
    );

    // ---- Debug LEDs: show latched result if valid, else inference active ----
    // This gives a clear visual indication: when inference finishes, the LEDs freeze on the class.
    assign debug_led = result_latched_valid ? result_latched_class : {debug_inference_active, debug_done_state, debug_result_valid, start_inference};

endmodule