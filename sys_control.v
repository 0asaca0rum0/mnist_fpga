
`timescale 1ns / 1ps



module systolic_control #(
    parameter DATA_W = 16,
    parameter ACC_W  = 32
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [255:0] features,
    input  wire         start_inference,
    output wire [10:0]  rom_addr,
    input  wire [15:0]  rom_dout,
    output reg          sa_load,
    output reg  [1:0]   sa_load_row,
    output reg  [1:0]   sa_load_col,
    output reg  [15:0]  sa_weight,
    output wire [15:0]  sa_in0, sa_in1, sa_in2, sa_in3,
    output reg          sa_start,
    input  wire         sa_done,
    input  wire [31:0]  sa_out0, sa_out1, sa_out2, sa_out3,
    output reg          result_valid,
    output reg  [3:0]   result_class,
    output reg          debug_inference_active,
    output reg          debug_result_valid,
    output reg          debug_done_state
);

    localparam L1_OUT = 32, L1_IN = 16;
    localparam L2_OUT = 16, L2_IN = 32;
    localparam L3_OUT = 10, L3_IN = 16;

    localparam ROM_BASE_W1 = 0;
    localparam ROM_BASE_B1 = 512;
    localparam ROM_BASE_W2 = 544;
    localparam ROM_BASE_B2 = 1056;
    localparam ROM_BASE_W3 = 1072;
    localparam ROM_BASE_B3 = 1232;

    localparam [3:0]
        IDLE        = 0,
        LOAD_TILE   = 1,
        WAIT_START  = 2,   // one-cycle delay before starting SA
        RUN_TILE    = 3,
        WAIT_BIAS0  = 4,
        WAIT_BIAS1  = 5,
        APPLY_BIAS  = 6,
        DONE_ALL    = 7,
        WAIT_ARGMAX = 8;

    reg [3:0]  state;
    reg [1:0]  layer;
    reg [3:0]  og, ig;
    reg [1:0]  tile_row, tile_col;
    reg [2:0]  wait_cnt;
    reg [31:0] out_acc0, out_acc1, out_acc2, out_acc3;
    reg [15:0] input_buf [0:31];
    reg [15:0] next_buf  [0:31];
    reg [15:0] bias_word;
    reg [3:0]  bias_idx;

    wire [7:0] n_out = (layer==0) ? L1_OUT : (layer==1) ? L2_OUT : L3_OUT;
    wire [7:0] n_in  = (layer==0) ? L1_IN  : (layer==1) ? L2_IN  : L3_IN;
    wire [3:0] max_og = (n_out>>2) + ((n_out[1:0]!=0) ? 4'd1 : 4'd0);
    wire [3:0] max_ig = (n_in>>2);

    wire [10:0] w_base = (layer==0) ? ROM_BASE_W1 : (layer==1) ? ROM_BASE_W2 : ROM_BASE_W3;
    wire [10:0] b_base = (layer==0) ? ROM_BASE_B1 : (layer==1) ? ROM_BASE_B2 : ROM_BASE_B3;

    assign sa_in0 = input_buf[ig*4+0];
    assign sa_in1 = input_buf[ig*4+1];
    assign sa_in2 = input_buf[ig*4+2];
    assign sa_in3 = input_buf[ig*4+3];

    reg [1:0] prev_layer;
    always @(posedge clk) begin
        if (!rst_n) prev_layer <= 0;
        else prev_layer <= layer;
    end
    wire layer_changed = (layer != prev_layer);

    assign rom_addr = (state == LOAD_TILE) ? (w_base + ((ig*4 + tile_row)*n_out) + (og*4 + tile_col)) :
                      ((state == WAIT_BIAS0) || (state == WAIT_BIAS1)) ? (b_base + (og*4) + bias_idx) :
                      11'd0;

    // ------------------------------------------------------------
    // Bias / activation wires (must be declared before use)
    // ------------------------------------------------------------// ------------------------------------------------------------
    // Bias / activation wires
    // ------------------------------------------------------------
    wire signed [31:0] acc_sel = (bias_idx==0) ? $signed(out_acc0) :
                                 (bias_idx==1) ? $signed(out_acc1) :
                                 (bias_idx==2) ? $signed(out_acc2) : $signed(out_acc3);

    // [THE FIX IS HERE]: We shift Layer 0's bias left by 14 so it survives the right-shift later!
    wire signed [31:0] bias_ext = (layer == 0) ? ($signed({ {16{bias_word[15]}}, bias_word }) << 14) 
                                               : ($signed({ {16{bias_word[15]}}, bias_word }) << 7);
                                               
    wire signed [31:0] with_bias = acc_sel + bias_ext;
    
    // Standard truncate shift, matching Python
    wire signed [31:0] shifted   = (layer == 0) ? (with_bias >>> 14) : (with_bias >>> 7);

    // Saturate and ReLU
    wire [15:0] saturated = shifted > 32767 ? 16'd32767 :
                            shifted < -32768 ? 16'h8000 : shifted[15:0];
                            
    wire [15:0] activated = ((layer==0)||(layer==1)) ?
                             (saturated[15] ? 16'd0 : saturated) : saturated;

    // ------------------------------------------------------------
    // Buffer block (input_buf / next_buf)
    // ------------------------------------------------------------
    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1) begin
                input_buf[i] <= 0;
                next_buf[i]  <= 0;
            end
        end else begin
            if (state == IDLE && start_inference) begin
                for (i = 0; i < 32; i = i + 1)
                    next_buf[i] <= 0;
                input_buf[0]  <= features[15:0];
                input_buf[1]  <= features[31:16];
                input_buf[2]  <= features[47:32];
                input_buf[3]  <= features[63:48];
                input_buf[4]  <= features[79:64];
                input_buf[5]  <= features[95:80];
                input_buf[6]  <= features[111:96];
                input_buf[7]  <= features[127:112];
                input_buf[8]  <= features[143:128];
                input_buf[9]  <= features[159:144];
                input_buf[10] <= features[175:160];
                input_buf[11] <= features[191:176];
                input_buf[12] <= features[207:192];
                input_buf[13] <= features[223:208];
                input_buf[14] <= features[239:224];
                input_buf[15] <= features[255:240];
            end

            if (layer_changed && layer != 0) begin
                for (i = 0; i < 32; i = i + 1)
                    if (i < ((layer == 1) ? L2_IN : L3_IN))
                        input_buf[i] <= next_buf[i];
            end

            if (state == APPLY_BIAS)
                next_buf[og*4 + bias_idx] <= activated;
        end
    end

    // ------------------------------------------------------------
    // Main FSM
    // ------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= IDLE;
            layer    <= 0;
            og       <= 0; ig <= 0;
            tile_row <= 0; tile_col <= 0;
            wait_cnt <= 0;
            result_valid <= 0;
            result_class <= 0;
            sa_load  <= 0;
            sa_start <= 0;
            bias_idx <= 0;
            out_acc0 <= 0; out_acc1 <= 0; out_acc2 <= 0; out_acc3 <= 0;
            debug_inference_active <= 0;
            debug_result_valid <= 0;
            debug_done_state   <= 0;
        end else begin
            result_valid <= 0;
            sa_load  <= 0;
            sa_start <= 0;
            debug_result_valid <= 0;
            debug_inference_active <= (state != IDLE);
            debug_done_state <= (state == DONE_ALL);

            case (state)
                IDLE: begin
                    if (start_inference) begin
                        layer    <= 0;
                        og       <= 0; ig <= 0;
                        tile_row <= 0; tile_col <= 0;
                        state    <= LOAD_TILE;
                        out_acc0 <= 0; out_acc1 <= 0; out_acc2 <= 0; out_acc3 <= 0;
                    end
                end

                LOAD_TILE: begin
                    if (wait_cnt == 0) begin
                        wait_cnt <= 1;
                    end else begin
                        sa_weight   <= rom_dout;
                        sa_load     <= 1;
                        sa_load_row <= tile_row;
                        sa_load_col <= tile_col;
                        wait_cnt    <= 0;
                        if (tile_col == 3) begin
                            tile_col <= 0;
                            if (tile_row == 3) begin
                                tile_row <= 0;
                                state    <= WAIT_START;   // go to wait state instead of RUN_TILE directly
                            end else
                                tile_row <= tile_row + 1;
                        end else
                            tile_col <= tile_col + 1;
                    end
                end

                WAIT_START: begin
                    // Give one cycle for the last loaded weight to settle
                    sa_start <= 1;
                    state    <= RUN_TILE;
                end

                RUN_TILE: begin
                    if (sa_done) begin
                        out_acc0 <= out_acc0 + sa_out0;
                        out_acc1 <= out_acc1 + sa_out1;
                        out_acc2 <= out_acc2 + sa_out2;
                        out_acc3 <= out_acc3 + sa_out3;
                        if (ig == max_ig - 1) begin
                            bias_idx <= 0;
                            state    <= WAIT_BIAS0;
                        end else begin
                            ig       <= ig + 1;
                            tile_row <= 0;
                            tile_col <= 0;
                            state    <= LOAD_TILE;
                        end
                    end
                end

                WAIT_BIAS0: begin
                    state <= WAIT_BIAS1;
                end

                WAIT_BIAS1: begin
                    bias_word <= rom_dout;
                    state <= APPLY_BIAS;
                end

                APPLY_BIAS: begin
                    if (bias_idx == 3) begin
                        if (og == max_og - 1) begin
                            if (layer == 2)
                                state <= DONE_ALL;
                            else begin
                                layer    <= layer + 1;
                                og       <= 0; ig <= 0;
                                tile_row <= 0; tile_col <= 0;
                                out_acc0 <= 0; out_acc1 <= 0; out_acc2 <= 0; out_acc3 <= 0;
                                state    <= LOAD_TILE;
                            end
                        end else begin
                            og       <= og + 1;
                            ig       <= 0;
                            tile_row <= 0; tile_col <= 0;
                            out_acc0 <= 0; out_acc1 <= 0; out_acc2 <= 0; out_acc3 <= 0;
                            state    <= LOAD_TILE;
                        end
                    end else begin
                        bias_idx <= bias_idx + 1;
                        state <= WAIT_BIAS0;
                    end
                end

                DONE_ALL: begin
                    state <= WAIT_ARGMAX;
                end

                WAIT_ARGMAX: begin
                    result_valid <= 1;
                    result_class <= argmax_idx_r;
                    state <= IDLE;
                end
            endcase
        end
    end

    // ------------------------------------------------------------
    // Argmax pipeline
    // ------------------------------------------------------------
    wire [15:0] cmp01_w, cmp23_w, cmp45_w, cmp67_w, cmp89_w;
    wire [3:0]  cmp01_i, cmp23_i, cmp45_i, cmp67_i, cmp89_i;
    assign {cmp01_w, cmp01_i} = ($signed(next_buf[0]) > $signed(next_buf[1])) ? {next_buf[0], 4'd0} : {next_buf[1], 4'd1};
    assign {cmp23_w, cmp23_i} = ($signed(next_buf[2]) > $signed(next_buf[3])) ? {next_buf[2], 4'd2} : {next_buf[3], 4'd3};
    assign {cmp45_w, cmp45_i} = ($signed(next_buf[4]) > $signed(next_buf[5])) ? {next_buf[4], 4'd4} : {next_buf[5], 4'd5};
    assign {cmp67_w, cmp67_i} = ($signed(next_buf[6]) > $signed(next_buf[7])) ? {next_buf[6], 4'd6} : {next_buf[7], 4'd7};
    assign {cmp89_w, cmp89_i} = ($signed(next_buf[8]) > $signed(next_buf[9])) ? {next_buf[8], 4'd8} : {next_buf[9], 4'd9};

    reg [15:0] cmp01_w_r, cmp23_w_r, cmp45_w_r, cmp67_w_r, cmp89_w_r;
    reg [3:0]  cmp01_i_r, cmp23_i_r, cmp45_i_r, cmp67_i_r, cmp89_i_r;
    always @(posedge clk) begin
        if (!rst_n) begin
            cmp01_w_r <= 0; cmp23_w_r <= 0; cmp45_w_r <= 0; cmp67_w_r <= 0; cmp89_w_r <= 0;
            cmp01_i_r <= 0; cmp23_i_r <= 0; cmp45_i_r <= 0; cmp67_i_r <= 0; cmp89_i_r <= 0;
        end else begin
            cmp01_w_r <= cmp01_w; cmp23_w_r <= cmp23_w; cmp45_w_r <= cmp45_w; cmp67_w_r <= cmp67_w; cmp89_w_r <= cmp89_w;
            cmp01_i_r <= cmp01_i; cmp23_i_r <= cmp23_i; cmp45_i_r <= cmp45_i; cmp67_i_r <= cmp67_i; cmp89_i_r <= cmp89_i;
        end
    end

    wire [15:0] cmp0123_w, cmp4567_w;
    wire [3:0]  cmp0123_i, cmp4567_i;
    assign {cmp0123_w, cmp0123_i} = ($signed(cmp01_w_r) > $signed(cmp23_w_r)) ? {cmp01_w_r, cmp01_i_r} : {cmp23_w_r, cmp23_i_r};
    assign {cmp4567_w, cmp4567_i} = ($signed(cmp45_w_r) > $signed(cmp67_w_r)) ? {cmp45_w_r, cmp45_i_r} : {cmp67_w_r, cmp67_i_r};

    wire [15:0] cmp01234567_w;
    wire [3:0]  cmp01234567_i;
    assign {cmp01234567_w, cmp01234567_i} = ($signed(cmp0123_w) > $signed(cmp4567_w)) ? {cmp0123_w, cmp0123_i} : {cmp4567_w, cmp4567_i};

    wire [3:0] argmax_idx;
    assign argmax_idx = ($signed(cmp01234567_w) > $signed(cmp89_w_r)) ? cmp01234567_i : cmp89_i_r;

    reg [3:0] argmax_idx_r;
    always @(posedge clk) begin
        if (!rst_n) argmax_idx_r <= 0;
        else argmax_idx_r <= argmax_idx;
    end

endmodule