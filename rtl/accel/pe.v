`timescale 1ns/1ps
// ==============================================================================
// Processing Element (PE) for Systolic Array Matrix Multiplier
// Precision: 8-bit signed inputs (a_in, b_in), 20-bit accumulator (c_out)
// ==============================================================================

module pe (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,         // RTL-05: update only while running, so Genus gates every flop
    input  wire        clr_acc,    // Clear the accumulator
    input  wire        valid_in,   // Input data valid
    input  wire signed [7:0]  a_in,  // A data (moves horizontally)
    input  wire signed [7:0]  b_in,  // B data (moves vertically)
    output reg  signed [7:0]  a_out, // Forward A to the PE on the right
    output reg  signed [7:0]  b_out, // Forward B to the PE below
    output reg         valid_out,
    output reg  signed [19:0] c_out  // Local accumulated value
);

    wire signed [15:0] mult_res;
    assign mult_res = a_in * b_in;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out     <= 8'sd0;
            b_out     <= 8'sd0;
            valid_out <= 1'b0;
            c_out     <= 20'sd0;
        end else begin
            if (clr_acc) begin
                // RTL-05: also clear the pipeline registers, because with en=0 they keep
                // the values of the previous run
                a_out     <= 8'sd0;
                b_out     <= 8'sd0;
                valid_out <= 1'b0;
                c_out     <= valid_in ? {{4{mult_res[15]}}, mult_res} : 20'sd0;
            end else if (en) begin
                // Pass data on to the neighbouring PEs
                a_out     <= a_in;
                b_out     <= b_in;
                valid_out <= valid_in;

                // Multiply and accumulate (MAC)
                if (valid_in)
                    c_out <= c_out + {{4{mult_res[15]}}, mult_res};
            end
        end
    end

endmodule
