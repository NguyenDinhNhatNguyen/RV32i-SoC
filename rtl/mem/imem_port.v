`timescale 1ns/1ps
`default_nettype none
// imem_port - IMEM (SRAM macro array) shared by the core fetch port and the data bus,
// plus the boot ROM (RTL-08).
//
// Fetch port (docs/spec/core.md sections 4.3, 4.10): the address is accepted when
// if_req && if_gnt, instruction and error arrive one cycle later.
//   IMEM      0x0000_0000, 4 KB << BANK_W   if_gnt = 0 while the bus uses IMEM
//   Boot ROM  0x0001_0000, 1 KB             if_gnt = 1 always (not shared with the bus)
//   other                                   if_gnt = 1, if_err = 1 one cycle later
//
// Data port (sys_bus slave): reads and writes IMEM to load programs and for FENCE.I.
// The bus has priority, so IF loses 1 cycle each time the bus uses IMEM (2 cycles
// for byte/half writes because of read-modify-write). Same as the IMEM model in tb_core.
`include "soc_map.vh"

module imem_port #(
    parameter BANK_W = `SOC_IMEM_BANK_W,    // Must equal IMEM_BANK_W of sys_bus
    parameter AW     = 10 + BANK_W          // Word address width, do not override
) (
    input  wire        clk,
    input  wire        rst_n,

    // Core fetch port
    input  wire        if_req,
    input  wire [31:0] if_addr,
    output wire        if_gnt,
    output wire [31:0] if_rdata,
    output wire        if_err,

    // Data port (sys_bus)
    input  wire        req_valid,
    output wire        req_ready,
    input  wire [31:0] req_addr,
    input  wire        req_we,
    input  wire [3:0]  req_be,
    input  wire [31:0] req_wdata,
    output wire        rsp_valid,
    output wire [31:0] rsp_rdata
);

    localparam [31:0] BOOT_BASE = `SOC_BOOT_BASE;

    // Fetch address decode
    wire f_imem = (if_addr[31:AW+2] == {(30-AW){1'b0}});
    wire f_boot = (if_addr[31:10] == BOOT_BASE[31:10]);

    wire        sram_f_gnt;
    wire [31:0] sram_q;
    wire [31:0] rom_q;

    assign if_gnt = f_imem ? sram_f_gnt : 1'b1;
    wire   f_acc  = if_req & if_gnt;

    sram_wrap #(.BANK_W(BANK_W)) u_sram (
        .clk       (clk),
        .rst_n     (rst_n),
        .req_valid (req_valid),
        .req_ready (req_ready),
        .req_addr  (req_addr),
        .req_we    (req_we),
        .req_be    (req_be),
        .req_wdata (req_wdata),
        .rsp_valid (rsp_valid),
        .rsp_rdata (rsp_rdata),
        .f_req     (if_req & f_imem),
        .f_gnt     (sram_f_gnt),
        .f_addr    (if_addr[AW+1:2]),
        .f_rdata   (sram_q)
    );

    boot_rom u_rom (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (f_acc & f_boot),
        .addr  (if_addr[9:2]),
        .q     (rom_q)
    );

    // Source of the instruction in the next cycle
    reg rom_sel_q;
    reg err_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rom_sel_q <= 1'b0;
            err_q     <= 1'b0;
        end else begin
            rom_sel_q <= f_acc & f_boot;
            err_q     <= f_acc & ~f_imem & ~f_boot;
        end
    end

    assign if_err   = err_q;
    assign if_rdata = rom_sel_q ? rom_q :
                      err_q     ? 32'h0 : sram_q;

    // Fetch address bits 1:0: the core already traps on misaligned jumps
    wire unused_if = &{1'b0, if_addr[1:0]};

endmodule

`default_nettype wire
