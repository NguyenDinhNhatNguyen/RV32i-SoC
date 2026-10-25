`timescale 1ns/1ps
`default_nettype none
// reset_sync - 2-flop reset synchronizer (RTL-09), docs/spec/soc_spec.md section 1.
// Asynchronous assert: rst_n_i = 0 drives rst_n_o = 0 at once, without waiting for a clock.
// Synchronous deassert: rst_n_o rises on the second rising edge after rst_n_i rises.
// SDC: only a false path from the rst_n pin into these two flops. Paths from rst_n_o to
// the reset pins of other flops must be checked for recovery/removal (STA-01).

module reset_sync (
    input  wire clk,
    input  wire rst_n_i,        // External reset pin, active low
    output wire rst_n_o         // Shared reset for every block
);

    // Two separate flops: flop 2 resets the whole SoC, flop 1 is data only
    // (Verilator reports SYNCASYNCNET if they share one vector)
    reg meta_q;
    reg sync_q;

    always @(posedge clk or negedge rst_n_i) begin
        if (!rst_n_i) begin
            meta_q <= 1'b0;
            sync_q <= 1'b0;
        end else begin
            meta_q <= 1'b1;
            sync_q <= meta_q;
        end
    end

    assign rst_n_o = sync_q;

endmodule

`default_nettype wire
