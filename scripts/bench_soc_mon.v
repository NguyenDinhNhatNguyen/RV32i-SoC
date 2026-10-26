`timescale 1ns/1ps
// bench_soc_mon.v - extra simulation root for make bench-soc, compiled next to tb/soc/tb_soc.v
// (iverilog -s tb_soc -s bench_soc_mon). It does not change tb_soc, it only reads soc_top
// signals by hierarchical reference.
//
// The measured region of a benchmark lies between two "csrr rd, minstret" (bench_start reads
// minstret first, bench_stop reads it last, and no other code reads it). Every two minstret
// reads close one region. When tb_soc calls $finish, the monitor prints one line per region:
//   BENCH soc region <k>: cycles C, data stall D (byte/half store S), fetch stall F, APB A
//   - data stall: cycles with d_req_valid = 1 and d_req_ready = 0 (SB/SH read-modify-write
//     wait state, APB bridge busy)
//   - byte/half store: SB/SH requests accepted (each costs 1 wait state in sram_wrap)
//   - fetch stall: cycles with if_req = 1 and if_gnt = 0
//   - APB: requests accepted by the APB bridge
// Cycles count from the WB of the first read to the WB of the second, so they are a few cycles
// more than the firmware mcycle difference. The lines are printed at the end so they do not
// cut a UART line in the log.
module bench_soc_mon;
    localparam MAX_REG = 8;

    reg     in_reg   = 1'b0;
    integer region   = 0;
    integer n_cyc    = 0;
    integer n_dstall = 0;
    integer n_sbsh   = 0;
    integer n_fstall = 0;
    integer n_apb    = 0;
    integer r_cyc    [0:MAX_REG-1];
    integer r_dstall [0:MAX_REG-1];
    integer r_sbsh   [0:MAX_REG-1];
    integer r_fstall [0:MAX_REG-1];
    integer r_apb    [0:MAX_REG-1];
    integer k;

    wire [31:0] wb_instr = tb_soc.dut.u_core.wb_instr_q;
    // csrr rd, minstret = csrrs rd, 0xB02, x0
    wire rd_minstret = tb_soc.dut.u_core.wb_retire && !tb_soc.dut.u_core.wb_trap &&
                       wb_instr[31:20] == 12'hB02 && wb_instr[19:15] == 5'd0 &&
                       wb_instr[14:12] == 3'b010 && wb_instr[6:0] == 7'b1110011;

    always @(posedge tb_soc.clk) begin
        if (in_reg) begin
            n_cyc = n_cyc + 1;
            if (tb_soc.dut.d_req_valid && !tb_soc.dut.d_req_ready)
                n_dstall = n_dstall + 1;
            if (tb_soc.dut.d_req_valid && tb_soc.dut.d_req_ready && tb_soc.dut.d_we &&
                tb_soc.dut.d_be != 4'b1111)
                n_sbsh = n_sbsh + 1;
            if (tb_soc.dut.if_req && !tb_soc.dut.if_gnt)
                n_fstall = n_fstall + 1;
            if (tb_soc.dut.apb_v && tb_soc.dut.apb_r)
                n_apb = n_apb + 1;
        end
        if (rd_minstret) begin
            if (in_reg && region < MAX_REG) begin
                r_cyc[region]    = n_cyc;
                r_dstall[region] = n_dstall;
                r_sbsh[region]   = n_sbsh;
                r_fstall[region] = n_fstall;
                r_apb[region]    = n_apb;
                region = region + 1;
            end
            in_reg   = !in_reg;
            n_cyc    = 0;
            n_dstall = 0;
            n_sbsh   = 0;
            n_fstall = 0;
            n_apb    = 0;
        end
    end

    final begin
        for (k = 0; k < region; k = k + 1)
            $display({"BENCH soc region %0d: cycles %0d, data stall %0d ",
                      "(byte/half store %0d), fetch stall %0d, APB %0d"},
                     k + 1, r_cyc[k], r_dstall[k], r_sbsh[k], r_fstall[k], r_apb[k]);
    end
endmodule
