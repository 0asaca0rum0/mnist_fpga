`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/14/2026 12:15:50 PM
// Design Name: 
// Module Name: cmd_parser
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


module cmd_parser #(
    parameter CLK_FREQ = 100_000_000
) (
    input  wire         clk,
    input  wire         rst_n,
    // UART interface
    input  wire [7:0]   rx_byte,
    input  wire         rx_done,
    output reg  [7:0]   tx_byte,
    output reg          tx_start,
    // MLP core interface - 16 features packed into a 256-bit bus
    output reg  [255:0] features,
    output reg          start_inference,
    input  wire         result_valid,
    input  wire [3:0]   result_class,
    // Fault injection arm
    output reg          fault_armed,
    output reg          fault_target,
    output reg  [5:0]   fault_bit_pos,
    // Temporary test acknowledge
    output reg          img_ack
);

    localparam CMD_START  = 8'h01;
    localparam CMD_RESULT = 8'h02;
    localparam CMD_FAULT  = 8'hFA;

    localparam IDLE        = 0;
    localparam LOAD_IMG    = 1;
    localparam WAIT_RESULT = 2;
    localparam SEND_RESULT = 3;
    localparam FAULT_SETUP = 4;

    reg [2:0]   state;
    reg [7:0]   byte_cnt;
    reg [4:0]   word_cnt;
    reg [15:0]  word_buf;

    always @(posedge clk) begin
        if (!rst_n) begin
            state           <= IDLE;
            byte_cnt        <= 0;
            word_cnt        <= 0;
            start_inference <= 0;
            tx_start        <= 0;
            fault_armed     <= 0;
            img_ack         <= 0;
            features        <= 256'd0;
        end else begin
            start_inference <= 0;
            tx_start        <= 0;
            img_ack         <= 0;

            case (state)
                IDLE: begin
                    if (rx_done) begin
                        case (rx_byte)
                            CMD_START: begin
                                state    <= LOAD_IMG;
                                byte_cnt <= 0;
                                word_cnt <= 0;
                            end
                            CMD_RESULT: begin
                                state <= WAIT_RESULT;
                            end
                            CMD_FAULT: begin
                                state <= FAULT_SETUP;
                                byte_cnt <= 0;
                            end
                        endcase
                    end
                end

                LOAD_IMG: begin
                    if (rx_done) begin
                        if (byte_cnt == 0) begin
                            word_buf[7:0] <= rx_byte;
                            byte_cnt <= 1;
                        end else begin
                            word_buf[15:8] <= rx_byte;
                            // Write to the correct 16-bit slice of the 256-bit bus
                            features[(word_cnt)*16 +: 16] <= {rx_byte, word_buf[7:0]};
                            byte_cnt <= 0;
                            if (word_cnt == 15) begin
                                word_cnt <= 0;
                                start_inference <= 1;
                                img_ack <= 1;
                                state <= IDLE;
                            end else begin
                                word_cnt <= word_cnt + 1;
                            end
                        end
                    end
                end

                WAIT_RESULT: begin
                    if (result_valid) begin
                        tx_byte  <= {4'h0, result_class};
                        tx_start <= 1;
                        state    <= SEND_RESULT;
                    end
                end

                SEND_RESULT: state <= IDLE;

                FAULT_SETUP: begin
                    if (rx_done) begin
                        if (byte_cnt == 0) begin
                            fault_target <= rx_byte[0];
                            byte_cnt <= 1;
                        end else begin
                            fault_bit_pos <= rx_byte[5:0];
                            fault_armed   <= 1;
                            state <= IDLE;
                        end
                    end
                end
            endcase
        end
    end
endmodule