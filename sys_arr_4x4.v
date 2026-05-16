`timescale 1ns / 1ps

module systolic_array_4x4 #(
    parameter DATA_W = 16,
    parameter ACC_W  = 32
) (
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire                     load,
    input  wire [1:0]               load_row,
    input  wire [1:0]               load_col,
    input  wire signed [DATA_W-1:0] weight_in,

    input  wire signed [DATA_W-1:0] in_data0,
    input  wire signed [DATA_W-1:0] in_data1,
    input  wire signed [DATA_W-1:0] in_data2,
    input  wire signed [DATA_W-1:0] in_data3,

    input  wire                     start,
    output wire                     done,

    output wire signed [ACC_W-1:0]  out_acc0,
    output wire signed [ACC_W-1:0]  out_acc1,
    output wire signed [ACC_W-1:0]  out_acc2,
    output wire signed [ACC_W-1:0]  out_acc3
);

    // 2D arrays to connect PEs
    // act_wire[row][col] is the activation going into PE(row, col)
    wire signed [DATA_W-1:0] act_wire [0:3][0:4];
    
    // psum_wire[row][col] is the partial sum going into PE(row, col)
    wire signed [ACC_W-1:0]  psum_wire [0:4][0:3];

    // Load signals decoder
    wire load_pe [0:3][0:3];

    // Delay registers for staggered inputs (skewing)
    reg signed [DATA_W-1:0] d1_r1;
    reg signed [DATA_W-1:0] d1_r2, d2_r2;
    reg signed [DATA_W-1:0] d1_r3, d2_r3, d3_r3;

    // Running state and cycle counter
    reg [3:0] busy_cnt;
    reg       running;

    // Input skewing logic
    always @(posedge clk) begin
        if (!rst_n) begin
            d1_r1 <= 0;
            d1_r2 <= 0; d2_r2 <= 0;
            d1_r3 <= 0; d2_r3 <= 0; d3_r3 <= 0;
        end else if (running || start) begin
            // Row 1
            d1_r1 <= in_data1;
            // Row 2
            d1_r2 <= in_data2; d2_r2 <= d1_r2;
            // Row 3
            d1_r3 <= in_data3; d2_r3 <= d1_r3; d3_r3 <= d2_r3;
        end
    end

    // Connect skewed inputs to the array (Activations flow RIGHT)
    assign act_wire[0][0] = running ? in_data0 : 0;
    assign act_wire[1][0] = running ? d1_r1 : 0;
    assign act_wire[2][0] = running ? d2_r2 : 0;
    assign act_wire[3][0] = running ? d3_r3 : 0;

    // Initialize top row partial sums to 0 (Partial Sums flow DOWN)
    assign psum_wire[0][0] = 0;
    assign psum_wire[0][1] = 0;
    assign psum_wire[0][2] = 0;
    assign psum_wire[0][3] = 0;

    // Output wires for each PE
    wire signed [DATA_W-1:0] act_out [0:3][0:3];
    wire signed [ACC_W-1:0]  psum_out [0:3][0:3];

    genvar r, c;
    generate
        for (r = 0; r < 4; r = r + 1) begin : row
            for (c = 0; c < 4; c = c + 1) begin : col
                // Decode load signal
                assign load_pe[r][c] = load && (load_row == r) && (load_col == c);

                // Connect outputs of this PE to the inputs of the next PE
                assign act_wire[r][c+1] = act_out[r][c];
                assign psum_wire[r+1][c] = psum_out[r][c];

                pe #(
                    .DATA_W(DATA_W),
                    .ACC_W(ACC_W)
                ) pe_inst (
                    .clk          (clk),
                    .rst_n        (rst_n),
                    .act_in       (act_wire[r][c]),
                    .psum_in      (psum_wire[r][c]),
                    .act_out      (act_out[r][c]),
                    .psum_out     (psum_out[r][c]),
                    .load_weight  (load_pe[r][c]),
                    .weight_in    (weight_in)
                );
            end
        end
    endgenerate

    // ---- Capture outputs at BOTTOM row after pipeline ----
    assign out_acc0 = psum_out[3][0];
    assign out_acc1 = psum_out[3][1];
    assign out_acc2 = psum_out[3][2];
    assign out_acc3 = psum_out[3][3];

    // ---- Running & done counter ----
    always @(posedge clk) begin
        if (!rst_n) begin
            running  <= 0;
            busy_cnt <= 0;
        end else begin
            if (start && !running) begin
                running  <= 1;
                busy_cnt <= 0;
            end else if (running) begin
                if (busy_cnt == 7) begin // 4x4 array needs 2N-1 cycles
                    running <= 0;
                end else begin
                    busy_cnt <= busy_cnt + 1;
                end
            end
        end
    end

    // Pulse done when the last result is captured
    assign done = (running && busy_cnt == 7);

endmodule