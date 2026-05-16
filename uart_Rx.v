`timescale 1ns / 1ps

module uart_rx #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD = 9600,
    parameter OVERSAMPLE = 16
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        rx,
    output reg [7:0]   rx_data,
    output reg         rx_done
);

    localparam BAUD_DIV = CLK_FREQ / (BAUD * OVERSAMPLE);  // 100e6/(9600*16)=651

    reg [15:0]  baud_cnt;
    reg [3:0]   bit_cnt;          // counts oversample ticks within a bit
    reg [3:0]   data_bit;         // which data bit 0..7 (8 = stop)
    reg         sync_rx, prev_rx; // synchroniser
    reg [1:0]   state;
    localparam  IDLE=0, START=1, DATA=2, STOP=3;

    // Double synchronise the async input
    always @(posedge clk) begin
        sync_rx <= rx;
        prev_rx <= sync_rx;
    end

    // Detect falling edge for start bit
    wire falling_edge = (prev_rx == 1 && sync_rx == 0);

    // Baud tick
    wire baud_tick = (baud_cnt == BAUD_DIV - 1);
    
    // SINGLE ALWAYS BLOCK FOR baud_cnt
    always @(posedge clk) begin
        if (!rst_n)
            baud_cnt <= 0;
        else if (state == IDLE && falling_edge) // Clear and sync to incoming edge
            baud_cnt <= 0;
        else if (baud_tick || state == IDLE)
            baud_cnt <= 0;
        else
            baud_cnt <= baud_cnt + 1;
    end

    // FSM BLOCK (Removed baud_cnt statement from here)
    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= IDLE;
            rx_done  <= 0;
            rx_data  <= 0;
            bit_cnt  <= 0;
            data_bit <= 0;
        end else begin
            rx_done <= 0;   // one-cycle pulse by default

            case (state)
                IDLE: begin
                    if (falling_edge) begin
                        state   <= START;
                        bit_cnt <= 0;
                        // baud_cnt <= 0; // REMOVED TO FIX MULTI-DRIVEN NET ERROR
                    end
                end

                START: begin
                    if (baud_tick) begin
                        if (bit_cnt == (OVERSAMPLE/2)-1) begin   // middle of start bit
                            state    <= DATA;
                            data_bit <= 0;
                            bit_cnt  <= 0;
                        end else begin
                            bit_cnt <= bit_cnt + 1;
                        end
                    end
                end

                DATA: begin
    if (baud_tick) begin
        if (bit_cnt == OVERSAMPLE-1) begin
            rx_data[data_bit] <= sync_rx;   // sample the current bit
            bit_cnt <= 0;

            if (data_bit == 7) begin
                state <= STOP;               // all 8 data bits done
            end else begin
                data_bit <= data_bit + 1;
            end
        end else begin
            bit_cnt <= bit_cnt + 1;
        end
    end
end

                STOP: begin
                    if (baud_tick) begin
                        if (bit_cnt == OVERSAMPLE-1) begin
                            if (sync_rx == 1) begin
                                rx_done <= 1;    // valid frame
                            end
                            state <= IDLE;
                        end else begin
                            bit_cnt <= bit_cnt + 1;
                        end
                    end
                end
            endcase
        end
    end
endmodule
