`timescale 1ns/1ps
`default_nettype none
// tb_imem_port - tests imem_port (RTL-08): the fetch port shares IMEM with the data bus.
//   - Random fetches from IMEM, the boot ROM and addresses with no memory, while the
//     bus reads and writes IMEM (word, half, byte) at random.
//   - if_gnt = 0 when fetching from IMEM while the bus uses IMEM, 1 for the boot ROM and
//     error addresses.
//   - The cycle after each accepted fetch: the instruction matches the reference memory (IMEM
//     including bus writes), boot ROM words match boot_rom_init.vh, and error addresses
//     give if_err = 1.
//   - Bus responses arrive in the right cycle with the right data.
// Plusargs: +seed=<n> +n=<fetches> +timeout=<cycles>
`include "soc_map.vh"

module tb_imem_port;

    parameter BANK_W = 2;
    localparam AW    = 10 + BANK_W;
    localparam WORDS = 1 << AW;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg         if_req    = 1'b0;
    reg  [31:0] if_addr   = 32'h0;
    wire        if_gnt, if_err;
    wire [31:0] if_rdata;
    reg         req_valid = 1'b0;
    wire        req_ready;
    reg  [31:0] req_addr  = 32'h0;
    reg         req_we    = 1'b0;
    reg  [3:0]  req_be    = 4'h0;
    reg  [31:0] req_wdata = 32'h0;
    wire        rsp_valid;
    wire [31:0] rsp_rdata;

    imem_port #(.BANK_W(BANK_W)) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .if_req    (if_req),
        .if_addr   (if_addr),
        .if_gnt    (if_gnt),
        .if_rdata  (if_rdata),
        .if_err    (if_err),
        .req_valid (req_valid),
        .req_ready (req_ready),
        .req_addr  (req_addr),
        .req_we    (req_we),
        .req_be    (req_be),
        .req_wdata (req_wdata),
        .rsp_valid (rsp_valid),
        .rsp_rdata (rsp_rdata)
    );

    reg [31:0] ref_mem [0:WORDS-1];
    integer i;
    initial for (i = 0; i < WORDS; i = i + 1) ref_mem[i] = 32'h0;

    integer seed = 1, seed0, n_fetch = 3000, timeout = 100000;
    integer errors = 0, cycle = 0;
    integer n_imem = 0, n_rom = 0, n_err = 0, n_blocked = 0, n_bus = 0;

    task fail(input [8*80-1:0] msg);
        begin
            errors = errors + 1;
            if (errors <= 10)
                $display("FAIL: %0s (cycle %0d)", msg, cycle);
        end
    endtask

    function [31:0] merge(input [31:0] old, input [31:0] nw, input [3:0] be);
        begin
            merge[ 7: 0] = be[0] ? nw[ 7: 0] : old[ 7: 0];
            merge[15: 8] = be[1] ? nw[15: 8] : old[15: 8];
            merge[23:16] = be[2] ? nw[23:16] : old[23:16];
            merge[31:24] = be[3] ? nw[31:24] : old[31:24];
        end
    endfunction

    // Expected boot ROM word, from the same file as boot_rom.v
    function [31:0] boot_word(input [7:0] addr);
        reg [31:0] word;
        begin
            case (addr)
`include "boot_rom_init.vh"
                default: word = 32'h0;
            endcase
            boot_word = word;
        end
    endfunction

    localparam [31:0] BOOT = `SOC_BOOT_BASE;
    wire hit_imem = (if_addr < (32'd4 << AW));
    wire hit_boot = (if_addr >= BOOT) && (if_addr < BOOT + `SOC_BOOT_SIZE);
    wire part     = req_we & (req_be != 4'hF);

    // ---------------------------------------------------------- checks on the rising edge
    reg         f_exp_q = 1'b0, f_exp_err_q = 1'b0;
    reg  [31:0] f_exp_q_data = 32'h0;
    reg         b_exp_q = 1'b0, b_exp_rd_q = 1'b0;
    reg  [31:0] b_exp_data_q = 32'h0;

    always @(posedge clk) begin
        if (rst_n) begin
            cycle = cycle + 1;
            if (f_exp_q) begin
                if (if_err !== f_exp_err_q)
                    fail("wrong if_err");
                if (if_rdata !== f_exp_q_data) begin
                    $display("      instruction %h, expected %h", if_rdata, f_exp_q_data);
                    fail("wrong instruction");
                end
            end else if (if_err !== 1'b0)
                fail("if_err = 1 without a fetch");
            if (rsp_valid !== b_exp_q)
                fail("rsp_valid in the wrong cycle");
            if (b_exp_q && b_exp_rd_q && rsp_rdata !== b_exp_data_q)
                fail("wrong bus read of IMEM");
            if (if_gnt !== ((hit_imem && req_valid) ? 1'b0 : 1'b1))
                fail("wrong if_gnt");
            if (if_req && hit_imem && req_valid)
                n_blocked = n_blocked + 1;

            // The bus is accepted first, so a fetch after a write sees the new value
            b_exp_q    <= req_valid & req_ready;
            b_exp_rd_q <= ~req_we;
            if (req_valid && req_ready) begin
                n_bus = n_bus + 1;
                if (req_we)
                    ref_mem[req_addr[AW+1:2]] = merge(ref_mem[req_addr[AW+1:2]], req_wdata, req_be);
                else
                    b_exp_data_q <= ref_mem[req_addr[AW+1:2]];
            end
            f_exp_q <= if_req & if_gnt;
            if (if_req && if_gnt) begin
                f_exp_err_q  <= ~hit_imem & ~hit_boot;
                f_exp_q_data <= hit_imem ? ref_mem[if_addr[AW+1:2]] :
                                hit_boot ? boot_word(if_addr[9:2]) : 32'h0;
                if (hit_imem) n_imem = n_imem + 1;
                else if (hit_boot) n_rom = n_rom + 1;
                else n_err = n_err + 1;
            end
        end
    end

    // ---------------------------------------------------------- stimulus on the falling edge
    reg req_ready_q = 1'b0;
    always @(posedge clk) req_ready_q <= req_ready;

    integer fetched = 0;
    reg     fetch_ok_q = 1'b0;
    always @(posedge clk) fetch_ok_q <= if_req & if_gnt;

    always @(negedge clk) begin
        if (rst_n) begin
            if (fetch_ok_q) fetched = fetched + 1;
            // Fetch: 60% IMEM (8 hot words or random), 25% boot ROM, 15% error addresses
            if_req = (fetched < n_fetch) && (($unsigned($random(seed)) % 5) != 0);
            case ($unsigned($random(seed)) % 20)
                0, 1, 2, 3, 4, 5:
                    if_addr = ((($unsigned($random(seed)) % 8) * (WORDS / 8)) << 2);
                6, 7, 8, 9, 10, 11:
                    if_addr = {{(30-AW){1'b0}}, $random(seed), 2'b00} & ((32'd4 << AW) - 1);
                12, 13, 14:
                    if_addr = BOOT;
                15, 16:
                    if_addr = BOOT + (($unsigned($random(seed)) % 256) << 2);
                17:
                    if_addr = 32'd4 << AW;                      // ngay sau IMEM
                18:
                    if_addr = BOOT + `SOC_BOOT_SIZE;            // ngay sau boot ROM
                default:
                    if_addr = {$random(seed)} | 32'h2000_0000;  // Peripheral region
            endcase
            // Data bus into IMEM, hold the request until accepted
            if (!(req_valid && !req_ready_q)) begin
                if (($unsigned($random(seed)) % 3) == 0) begin
                    req_valid = 1'b1;
                    req_we    = ($unsigned($random(seed)) % 2);
                    req_addr  = ((($unsigned($random(seed)) % 8) * (WORDS / 8)) << 2);
                    req_wdata = $random(seed);
                    case ($unsigned($random(seed)) % 4)
                        0: req_be = 4'b0001;
                        1: req_be = 4'b1100;
                        default: req_be = 4'b1111;
                    endcase
                end else begin
                    req_valid = 1'b0;
                end
            end
        end
    end

    initial begin
        if ($value$plusargs("seed=%d", seed)) ;
        if ($value$plusargs("n=%d", n_fetch)) ;
        if ($value$plusargs("timeout=%d", timeout)) ;
        seed0 = seed;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        while (fetched < n_fetch && cycle < timeout)
            @(posedge clk);
        @(negedge clk) req_valid = 1'b0;
        repeat (3) @(posedge clk);
        if (cycle >= timeout) fail("qua thoi gian");
        if (n_imem == 0 || n_rom == 0 || n_err == 0 || n_blocked == 0 || n_bus == 0)
            fail("missing transaction type");
        if (errors == 0)
            $display("PASS: tb_imem_port BANK_W=%0d: fetched %0d IMEM, %0d boot ROM, %0d error addresses, %0d blocked by the bus, %0d bus requests (seed %0d)",
                     BANK_W, n_imem, n_rom, n_err, n_blocked, n_bus, seed0);
        else
            $display("FAIL: tb_imem_port BANK_W=%0d: %0d loi (seed %0d)", BANK_W, errors, seed0);
        $finish;
    end

endmodule

`default_nettype wire
