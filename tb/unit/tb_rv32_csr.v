`timescale 1ns/1ps
`default_nettype none
// tb_rv32_csr - self-checking testbench for the check port and reset values of
// rv32_csr. Read/write behavior, traps, interrupts and counters are checked on the full core
// (fw/tests/asm/trap.S, irq.S, wfi.S and riscv-tests rv32mi).
// Checks:
//   - Sweep all 4096 addresses x {read, write}: illegal when the address is not in the
//     spec CSR table (section 4.7, rewritten with numbers here, not the RTL macros)
//     or on a write to the read-only space addr[11:10] = 11,
//   - The value of each CSR after reset, unknown addresses read 0,
//   - mip follows the interrupt pins, irq_pending/irq_take/irq_cause follow mie and mstatus.
// Runs with ENABLE_M=0 and 1 (misa).
// Plusargs: +seed=<n> (no randomness, accepted to match the other tbs)

module tb_rv32_csr;

    parameter ENABLE_M = 0;

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg  [11:0] chk_addr = 12'hfff;   // Differs from the first sweep value so always @(*) runs
    reg         chk_we = 1'b0;
    wire        chk_illegal;
    reg  [11:0] addr = 12'h0;
    reg  [1:0]  op = 2'b01;
    reg  [31:0] wdata = 32'h0;
    reg         wr_en = 1'b0;
    wire [31:0] rdata;
    reg         msi = 1'b0, mti = 1'b0, mei = 1'b0;
    reg  [63:0] mtime = 64'h1234_5678_9abc_def0;
    wire [31:0] mtvec, mepc;
    wire        irq_pending, irq_take;
    wire [4:0]  irq_cause;

    rv32_csr #(.ENABLE_M(ENABLE_M)) dut (
        .clk(clk), .rst_n(rst_n),
        .chk_addr_i(chk_addr), .chk_we_i(chk_we), .chk_illegal_o(chk_illegal),
        .addr_i(addr), .op_i(op), .wdata_i(wdata), .wr_en_i(wr_en), .rdata_o(rdata),
        .trap_i(1'b0), .trap_pc_i(30'h0), .trap_int_i(1'b0), .trap_cause_i(5'd0),
        .trap_tval_i(32'h0), .mret_i(1'b0), .instret_i(1'b0),
        .mtvec_o(mtvec), .mepc_o(mepc),
        .irq_software_i(msi), .irq_timer_i(mti), .irq_external_i(mei), .mtime_i(mtime),
        .irq_pending_o(irq_pending), .irq_take_o(irq_take), .irq_cause_o(irq_cause)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;
    integer seed   = 1;
    integer a, w, n_exist;

    // CSR table from spec section 4.7
    function exists(input [11:0] x);
        begin
            case (x)
                12'h300, 12'h301, 12'h304, 12'h305, 12'h340, 12'h341, 12'h342,
                12'h343, 12'h344, 12'hB00, 12'hB02, 12'hB80, 12'hB82, 12'hC00,
                12'hC01, 12'hC02, 12'hC80, 12'hC81, 12'hC82, 12'hF11, 12'hF12,
                12'hF13, 12'hF14: exists = 1'b1;
                default:          exists = 1'b0;
            endcase
        end
    endfunction

    task check_eq(input [31:0] got, input [31:0] exp, input [8*40-1:0] what);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("FAIL: %0s got=%h exp=%h", what, got, exp);
            end
        end
    endtask

    task read_csr(input [11:0] x, input [31:0] exp);
        reg [8*40-1:0] what;
        begin
            addr = x;
            #1;
            $sformat(what, "read csr %03h", x);
            check_eq(rdata, exp, what);
        end
    endtask

    initial begin
        if ($value$plusargs("seed=%d", seed)) ;
        #12 rst_n = 1'b1;

        // ---- Check port ---------------------------------------------------------
        n_exist = 0;
        for (a = 0; a < 4096; a = a + 1) begin
            for (w = 0; w < 2; w = w + 1) begin
                chk_addr = a;
                chk_we   = w;
                #1;
                check_eq(chk_illegal, !exists(a) || (w && a[11:10] == 2'b11), "chk_illegal");
            end
            if (exists(a))
                n_exist = n_exist + 1;
        end
        check_eq(n_exist, 23, "number of CSRs in table");

        // ---- Values after reset -------------------------------------------------
        read_csr(12'h300, 32'h0000_1800);
        read_csr(12'h301, 32'h4000_0100 | (ENABLE_M ? 32'h1000 : 32'h0));
        read_csr(12'h304, 32'h0);
        read_csr(12'h305, 32'h0);
        read_csr(12'h340, 32'h0);
        read_csr(12'h341, 32'h0);
        read_csr(12'h342, 32'h0);
        read_csr(12'h343, 32'h0);
        read_csr(12'h344, 32'h0);
        read_csr(12'hB80, 32'h0);
        read_csr(12'hB82, 32'h0);
        read_csr(12'hB02, 32'h0);
        read_csr(12'hC02, 32'h0);
        read_csr(12'hC01, 32'h9abc_def0);
        read_csr(12'hC81, 32'h1234_5678);
        read_csr(12'hF11, 32'h0);
        read_csr(12'hF12, 32'h0);
        read_csr(12'hF13, 32'h0);
        read_csr(12'hF14, 32'h0);
        read_csr(12'h7C0, 32'h0);
        read_csr(12'h3A0, 32'h0);

        // ---- mip, pending interrupts, priority ------------------------------------------
        msi = 1'b1; mti = 1'b1; mei = 1'b1;
        read_csr(12'h344, 32'h888);
        check_eq(irq_pending, 0, "pending with mie = 0");
        @(negedge clk);
        addr = 12'h304; wdata = 32'h80; op = 2'b01; wr_en = 1'b1;   // mie.MTIE
        @(negedge clk);
        wr_en = 1'b0;
        check_eq(irq_pending, 1, "pending MTI");
        check_eq(irq_take, 0, "take with mstatus.MIE = 0");
        check_eq(irq_cause, 7, "cause MTI");
        addr = 12'h304; wdata = 32'h888; wr_en = 1'b1;
        @(negedge clk);
        addr = 12'h300; wdata = 32'h8; wr_en = 1'b1;                 // mstatus.MIE
        @(negedge clk);
        wr_en = 1'b0;
        check_eq(irq_take, 1, "take with MIE = 1");
        check_eq(irq_cause, 11, "MEI first");
        mei = 1'b0;
        #1 check_eq(irq_cause, 3, "then MSI");
        msi = 1'b0;
        #1 check_eq(irq_cause, 7, "then MTI");
        mti = 1'b0;
        #1 check_eq(irq_pending, 0, "no pending");

        if (errors == 0)
            $display("PASS: tb_rv32_csr ENABLE_M=%0d (%0d checks, seed %0d)", ENABLE_M, checks, seed);
        else
            $display("FAIL: tb_rv32_csr %0d errors in %0d checks", errors, checks);
        $finish;
    end

endmodule

`default_nettype wire
