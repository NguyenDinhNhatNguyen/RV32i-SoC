`timescale 1ns/1ps
`default_nettype none
// tb_rv32_regfile - self-checking testbench for rv32_regfile.
// Checks: every register is 0 after reset, x0 ignores writes, a written value
// shows only after the clock edge (no bypass), random reads and writes against an array
// model, asynchronous reset in the middle of a cycle.
// Plusargs: +seed=<n> +n=<random cycles> +timeout=<ns>

module tb_rv32_regfile;

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         we = 1'b0;
    reg  [4:0]  rd_addr = 5'd0;
    reg  [31:0] rd_data = 32'h0;
    reg  [4:0]  rs1_addr = 5'd0;
    reg  [4:0]  rs2_addr = 5'd0;
    wire [31:0] rs1_data, rs2_data;

    rv32_regfile dut (
        .clk(clk), .rst_n(rst_n),
        .we_i(we), .rd_addr_i(rd_addr), .rd_data_i(rd_data),
        .rs1_addr_i(rs1_addr), .rs1_data_o(rs1_data),
        .rs2_addr_i(rs2_addr), .rs2_data_o(rs2_data)
    );

    always #5 clk = ~clk;

    reg [31:0] model [0:31];

    integer errors = 0;
    integer checks = 0;
    integer seed   = 1;
    integer seed0;
    integer n_rand = 50000;
    integer timeout_ns = 10000000;
    integer i;

    task check_port(input [4:0] addr, input [31:0] got, input [8*4-1:0] port);
        begin
            checks = checks + 1;
            if (got !== model[addr]) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("FAIL: t=%0t %0s x%0d got=%h exp=%h", $time, port, addr, got, model[addr]);
            end
        end
    endtask

    task check_all;
        integer r;
        begin
            for (r = 0; r < 32; r = r + 1) begin
                rs1_addr = r;
                rs2_addr = 31 - r;
                #0.1;
                check_port(rs1_addr, rs1_data, "rs1");
                check_port(rs2_addr, rs2_data, "rs2");
            end
        end
    endtask

    task clear_model;
        integer r;
        begin
            for (r = 0; r < 32; r = r + 1) model[r] = 32'h0;
        end
    endtask

    // One clock cycle: set inputs after the falling edge, check reads just
    // before the rising edge, then update the model on the rising edge.
    task cycle(input t_we, input [4:0] t_rd, input [31:0] t_data,
               input [4:0] t_rs1, input [4:0] t_rs2);
        begin
            @(negedge clk);
            we = t_we; rd_addr = t_rd; rd_data = t_data;
            rs1_addr = t_rs1; rs2_addr = t_rs2;
            #4;
            // Still reads the old value even when rd == rs (no bypass)
            check_port(rs1_addr, rs1_data, "rs1");
            check_port(rs2_addr, rs2_data, "rs2");
            @(posedge clk);
            if (t_we && t_rd != 5'd0) model[t_rd] = t_data;
        end
    endtask

    initial begin
        if ($value$plusargs("seed=%d", seed)) ;
        seed0 = seed;
        if ($value$plusargs("n=%d", n_rand)) ;
        if ($value$plusargs("timeout=%d", timeout_ns)) ;

        clear_model;
        #12 rst_n = 1'b1;
        check_all;                                    // Values after reset

        // x0 is always 0
        cycle(1'b1, 5'd0, 32'hDEAD_BEEF, 5'd0, 5'd0);
        cycle(1'b0, 5'd0, 32'h0, 5'd0, 5'd0);

        // Write a different pattern to each register, then read it back
        for (i = 1; i < 32; i = i + 1)
            cycle(1'b1, i, {i[7:0], ~i[7:0], i[7:0], 8'hA5}, i - 1, i);
        check_all;

        // With we = 0 nothing is written
        for (i = 1; i < 32; i = i + 1)
            cycle(1'b0, i, 32'hFFFF_FFFF, i, 5'd0);
        check_all;

        // Back-to-back writes to the same register, read in the same cycle
        cycle(1'b1, 5'd7, 32'h1111_1111, 5'd7, 5'd7);
        cycle(1'b1, 5'd7, 32'h2222_2222, 5'd7, 5'd7);
        cycle(1'b0, 5'd7, 32'h0, 5'd7, 5'd7);

        // Random reads and writes
        for (i = 0; i < n_rand; i = i + 1)
            cycle($random(seed), $random(seed), $random(seed), $random(seed), $random(seed));
        check_all;

        // Asynchronous reset in the middle of a cycle
        @(negedge clk);
        #2 rst_n = 1'b0;
        #0.5;
        clear_model;
        check_all;
        @(posedge clk);
        #2 rst_n = 1'b1;
        for (i = 0; i < 1000; i = i + 1)
            cycle($random(seed), $random(seed), $random(seed), $random(seed), $random(seed));
        check_all;

        if (errors == 0)
            $display("PASS: tb_rv32_regfile (%0d checks, seed %0d)", checks, seed0);
        else
            $display("FAIL: tb_rv32_regfile (%0d errors / %0d checks, seed %0d)", errors, checks, seed0);
        $finish;
    end

    initial begin
        #1;
        #(timeout_ns);
        $display("FAIL: tb_rv32_regfile timeout after %0d ns", timeout_ns);
        $finish;
    end

endmodule

`default_nettype wire
