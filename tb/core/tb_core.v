`timescale 1ns/1ps
`default_nettype none
// tb_core - rv32_core chạy riêng với IMEM/DMEM (sram_1rw_model) và một bus
// dữ liệu hành vi. Tự kết luận (docs/spec/core.md mục 10.2):
//   - ghi vào tohost: 1 = PASS, giá trị lẻ khác = FAIL, mã lỗi = giá trị >> 1
//   - trap khi mtvec vẫn bằng 0 (giá trị reset, chương trình chưa cài trình
//     xử lý trap): FAIL. Test có trình xử lý thì trap là hợp lệ.
//   - sai giao thức bus, X trên bus hoặc rd, core làm việc khi đang ngủ,
//     quá thời gian: FAIL
// Giải mã bus dữ liệu: IMEM (dùng chung với cổng lệnh, dữ liệu được ưu tiên
// giống imem_port), DMEM, UART DATA (in ký tự ngay), khối điều khiển của tb
// (CORE_TB_CTRL_BASE), còn lại trả err.
//
// Khối điều khiển của tb (chỉ có trong tb_core, offset theo byte):
//   0x0 IRQ   ghi: bit 3/7/11 = mức irq_software/timer/external mong muốn,
//             bit 31:16 = số chu kỳ chờ trước khi áp dụng. Đọc: mức hiện tại.
//   0x4 SLEEP đọc: tổng số chu kỳ core_sleep_o = 1 từ lúc reset.
//   0x8 CFG   đọc: bit 0 = ENABLE_M, bit 1 = ENABLE_WFI_SLEEP.
// mtime_i tăng 1 mỗi chu kỳ.
//
// Plusarg:
//   +imem=<hex> +dmem=<hex>   ảnh bộ nhớ (sram_1rw_model đọc)
//   +tohost=<hex>             địa chỉ tohost (elf2hex.py in ra)
//   +test=<tên>               tên in ở dòng PASS/FAIL
//   +timeout=<chu kỳ>         mặc định 200000
//   +seed=<n>                 seed ngẫu nhiên cho việc chèn stall
//   +if_stall=<pct>           % chu kỳ cổng lệnh không được cấp quyền
//   +d_stall=<pct>            % chu kỳ d_req_ready = 0 (wait state)
//   +rsp_delay=<max>          phản hồi trễ thêm ngẫu nhiên 0..max chu kỳ
//   +strict_timing            kiểm tra đúng số bubble (chỉ khi không stall)
//   +trace                    in vết gần định dạng commit log của Spike
//   +signature=<file>         khi PASS, ghi vùng [+sig_begin, +sig_end) (hex) ra file,
//                             mỗi dòng một word, theo định dạng signature của riscv-arch-test
`include "core_tb_map.vh"
`include "rv32_defs.vh"

module tb_core;

    parameter ENABLE_M         = 0;
    parameter ENABLE_WFI_SLEEP = 1;

    localparam IMEM_SIZE  = `CORE_TB_IMEM_SIZE;
    localparam DMEM_SIZE  = `CORE_TB_DMEM_SIZE;
    localparam IMEM_WORDS = IMEM_SIZE / 4;
    localparam DMEM_WORDS = DMEM_SIZE / 4;
    localparam IMEM_AW    = $clog2(IMEM_WORDS);
    localparam DMEM_AW    = $clog2(DMEM_WORDS);
    localparam [31:0] UART_DATA_ADDR = `CORE_TB_UART_DATA;
    localparam [31:0] CTRL_BASE      = `CORE_TB_CTRL_BASE;

    // Nguồn phản hồi của yêu cầu dữ liệu đang chờ
    localparam [2:0] SRC_IMEM = 3'd0, SRC_DMEM = 3'd1, SRC_UART = 3'd2, SRC_ERR = 3'd3,
                     SRC_CTRL = 3'd4;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    // ---------------------------------------------------------------- DUT
    wire        if_req, if_gnt, if_err;
    wire [31:0] if_addr, if_rdata;
    wire        d_req_valid, d_req_ready, d_we;
    wire [31:0] d_addr, d_wdata;
    wire [3:0]  d_be;
    wire        d_rsp_valid, d_rsp_err;
    wire [31:0] d_rsp_rdata;
    reg         irq_sw = 1'b0, irq_tim = 1'b0, irq_ext = 1'b0;
    reg  [63:0] mtime  = 64'h0;
    wire        core_sleep;

    rv32_core #(
        .ENABLE_M         (ENABLE_M),
        .ENABLE_WFI_SLEEP (ENABLE_WFI_SLEEP),
        .RESET_PC         (`CORE_TB_IMEM_BASE)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .if_req_o      (if_req),
        .if_addr_o     (if_addr),
        .if_gnt_i      (if_gnt),
        .if_rdata_i    (if_rdata),
        .if_err_i      (if_err),
        .d_req_valid_o (d_req_valid),
        .d_req_ready_i (d_req_ready),
        .d_addr_o      (d_addr),
        .d_we_o        (d_we),
        .d_be_o        (d_be),
        .d_wdata_o     (d_wdata),
        .d_rsp_valid_i (d_rsp_valid),
        .d_rsp_rdata_i (d_rsp_rdata),
        .d_rsp_err_i   (d_rsp_err),
        .irq_software_i(irq_sw),
        .irq_timer_i   (irq_tim),
        .irq_external_i(irq_ext),
        .mtime_i       (mtime),
        .core_sleep_o  (core_sleep)
    );

    // ------------------------------------------------------- cấu hình
    integer     sleep_cycles  = 0;      // số chu kỳ core_sleep_o = 1
    integer     seed          = 1;
    integer     seed0;
    integer     timeout       = 200000;
    integer     if_stall_pct  = 0;
    integer     d_stall_pct   = 0;
    integer     rsp_delay_max = 0;
    reg         strict_timing = 1'b0;
    reg         trace_en      = 1'b0;
    reg  [31:0] tohost        = 32'hFFFF_FFFF;
    reg  [8*64-1:0] test_name = "core";

    // Quyết định stall ngẫu nhiên, rút lại ở mỗi cạnh xuống
    reg     if_stall_now  = 1'b0;
    reg     d_stall_now   = 1'b0;
    integer rsp_delay_now = 0;

    always @(negedge clk) begin
        if_stall_now  <= ($unsigned($random(seed)) % 100) < if_stall_pct;
        d_stall_now   <= ($unsigned($random(seed)) % 100) < d_stall_pct;
        rsp_delay_now <= (rsp_delay_max > 0) ? ($unsigned($random(seed)) % (rsp_delay_max + 1)) : 0;
    end

    // ------------------------------------------------------- giải mã địa chỉ
    wire if_hit_imem = (if_addr - `CORE_TB_IMEM_BASE) < IMEM_SIZE;
    wire d_hit_imem  = (d_addr - `CORE_TB_IMEM_BASE) < IMEM_SIZE;
    wire d_hit_dmem  = (d_addr >= `CORE_TB_DMEM_BASE) && (d_addr < `CORE_TB_DMEM_BASE + DMEM_SIZE);
    wire d_hit_uart  = (d_addr[31:2] == UART_DATA_ADDR[31:2]);
    wire d_hit_ctrl  = (d_addr[31:4] == CTRL_BASE[31:4]) && (d_addr[3:2] != 2'b11);
    wire [2:0] d_src = d_hit_imem ? SRC_IMEM :
                       d_hit_dmem ? SRC_DMEM :
                       d_hit_uart ? SRC_UART :
                       d_hit_ctrl ? SRC_CTRL : SRC_ERR;

    assign d_req_ready = ~d_stall_now;
    wire d_acc      = d_req_valid & d_req_ready;
    wire d_acc_imem = d_acc & d_hit_imem;

    // IMEM dùng chung như imem_port: yêu cầu dữ liệu vào IMEM chặn lấy lệnh
    assign if_gnt   = ~(d_req_valid & d_hit_imem) & ~if_stall_now;
    wire   if_acc   = if_req & if_gnt;

    // ---------------------------------------------------------- bộ nhớ
    wire [31:0] imem_q, dmem_q;

    sram_1rw_model #(
        .DEPTH        (IMEM_WORDS),
        .INIT_PLUSARG ("imem")
    ) u_imem (
        .clk     (clk),
        .ce_i    (d_acc_imem | (if_acc & if_hit_imem)),
        .we_i    (d_acc_imem & d_we),
        .be_i    (d_be),
        .addr_i  (d_acc_imem ? d_addr[IMEM_AW+1:2] : if_addr[IMEM_AW+1:2]),
        .wdata_i (d_wdata),
        .rdata_o (imem_q)
    );

    sram_1rw_model #(
        .DEPTH        (DMEM_WORDS),
        .INIT_PLUSARG ("dmem")
    ) u_dmem (
        .clk     (clk),
        .ce_i    (d_acc & d_hit_dmem),
        .we_i    (d_we),
        .be_i    (d_be),
        .addr_i  (d_addr[DMEM_AW+1:2]),
        .wdata_i (d_wdata),
        .rdata_o (dmem_q)
    );

    // ------------------------------------------------------- phản hồi lấy lệnh
    reg if_err_q = 1'b0;
    always @(posedge clk)
        if_err_q <= if_acc & ~if_hit_imem;

    assign if_err   = if_err_q;
    assign if_rdata = if_err_q ? 32'h0 : imem_q;

    // ------------------------------------------------------- khối điều khiển
    reg         irq_arm_q    = 1'b0;
    reg  [15:0] irq_cnt_q    = 16'd0;
    reg  [2:0]  irq_next_q   = 3'b000;   // {ext, timer, sw}
    reg  [31:0] ctrl_rdata_q = 32'h0;    // dữ liệu đọc, chốt khi nhận yêu cầu

    wire [31:0] irq_now = {20'h0, irq_ext, 3'b000, irq_tim, 3'b000, irq_sw, 3'b000};

    always @(posedge clk) begin
        if (rst_n) begin
            mtime <= mtime + 64'd1;
            if (core_sleep)
                sleep_cycles <= sleep_cycles + 1;
        end
        if (irq_arm_q) begin
            if (irq_cnt_q == 16'd0) begin
                {irq_ext, irq_tim, irq_sw} <= irq_next_q;
                irq_arm_q <= 1'b0;
            end else
                irq_cnt_q <= irq_cnt_q - 16'd1;
        end
        if (rst_n && d_acc && d_hit_ctrl) begin
            case (d_addr[3:2])
                2'd0:    ctrl_rdata_q <= irq_now;
                2'd1:    ctrl_rdata_q <= sleep_cycles;
                default: ctrl_rdata_q <= {30'h0, (ENABLE_WFI_SLEEP != 0), (ENABLE_M != 0)};
            endcase
            if (d_we && d_addr[3:2] == 2'd0) begin
                irq_arm_q  <= 1'b1;
                irq_cnt_q  <= d_wdata[31:16];
                irq_next_q <= {d_wdata[11], d_wdata[7], d_wdata[3]};
            end
        end
    end

    // ------------------------------------------------------- phản hồi dữ liệu
    // Ngõ ra bộ nhớ chỉ đúng ở chu kỳ ngay sau khi nhận, nên được chép vào
    // pend_buf_q khi phản hồi bị trễ.
    reg         pend_q       = 1'b0;
    reg         pend_first_q = 1'b0;
    reg         pend_we_q    = 1'b0;
    reg  [2:0]  pend_src_q   = SRC_ERR;
    integer     pend_cnt_q   = 0;
    reg  [31:0] pend_buf_q   = 32'h0;

    wire [31:0] mem_now = (pend_src_q == SRC_IMEM) ? imem_q :
                          (pend_src_q == SRC_DMEM) ? dmem_q :
                          (pend_src_q == SRC_CTRL) ? ctrl_rdata_q : 32'h0;
    wire [31:0] rd_now  = pend_first_q ? mem_now : pend_buf_q;

    assign d_rsp_valid = pend_q && (pend_cnt_q == 0);
    assign d_rsp_err   = d_rsp_valid && (pend_src_q == SRC_ERR);
    assign d_rsp_rdata = (!d_rsp_valid || d_rsp_err || pend_we_q) ? 32'h0 : rd_now;

    always @(posedge clk) begin
        if (pend_q) begin
            if (pend_first_q) begin
                pend_buf_q   <= rd_now;
                pend_first_q <= 1'b0;
            end
            if (pend_cnt_q == 0)
                pend_q <= 1'b0;
            else
                pend_cnt_q <= pend_cnt_q - 1;
        end
        if (d_acc) begin
            pend_q       <= 1'b1;
            pend_first_q <= 1'b1;
            pend_we_q    <= d_we;
            pend_src_q   <= d_src;
            pend_cnt_q   <= rsp_delay_now;
        end
    end

    // ------------------------------------------------------- kết thúc test
    integer cycle   = 0;
    integer instret = 0;
    reg     done    = 1'b0;

    // Signature cho riscv-arch-test, đọc thẳng từ mô hình bộ nhớ
    reg  [8*512-1:0] sig_file;
    reg  [31:0]      sig_begin = 32'h0, sig_end = 32'h0;
    reg              sig_en    = 1'b0;

    task dump_signature;
        integer    fd;
        reg [31:0] a;
        begin
            fd = $fopen(sig_file, "w");
            for (a = sig_begin; a < sig_end; a = a + 32'd4) begin
                if ((a - `CORE_TB_IMEM_BASE) < IMEM_SIZE)
                    $fdisplay(fd, "%08x", u_imem.mem[(a - `CORE_TB_IMEM_BASE) >> 2]);
                else if (a >= `CORE_TB_DMEM_BASE && a < `CORE_TB_DMEM_BASE + DMEM_SIZE)
                    $fdisplay(fd, "%08x", u_dmem.mem[(a - `CORE_TB_DMEM_BASE) >> 2]);
                else
                    $fdisplay(fd, "xxxxxxxx");
            end
            $fclose(fd);
        end
    endtask

    task end_test(input pass, input [8*96-1:0] why);
        begin
            if (!done) begin
                done = 1'b1;
                if (pass && sig_en)
                    dump_signature;
                if (pass && sleep_cycles > 0)
                    $display("PASS: %0s (cycles %0d, instret %0d, CPI %0.3f, sleep %0d, seed %0d)",
                             test_name, cycle, instret,
                             (instret > 0) ? (1.0 * cycle / instret) : 0.0, sleep_cycles, seed0);
                else if (pass)
                    $display("PASS: %0s (cycles %0d, instret %0d, CPI %0.3f, seed %0d)",
                             test_name, cycle, instret,
                             (instret > 0) ? (1.0 * cycle / instret) : 0.0, seed0);
                else
                    $display("FAIL: %0s: %0s (cycle %0d, instret %0d, seed %0d)",
                             test_name, why, cycle, instret, seed0);
                $finish;
            end
        end
    endtask

    // Ký tự UART, giá trị tohost
    reg        tohost_seen = 1'b0;
    reg [31:0] tohost_val  = 32'h0;

    always @(posedge clk) begin
        if (rst_n && d_acc && d_we) begin
            if (d_hit_uart) begin
                $write("%c", d_wdata[7:0]);
                $fflush;
            end
            if (d_addr == tohost) begin
                tohost_seen <= 1'b1;
                tohost_val  <= d_wdata;
            end
        end
    end

    // ------------------------------------------------------- kiểm tra bus
    reg         req_wait_q = 1'b0;
    reg  [31:0] req_addr_q, req_wdata_q;
    reg         req_we_q;
    reg  [3:0]  req_be_q;
    reg  [8*96-1:0] msg;

    always @(posedge clk) begin
        if (rst_n) begin
            if ((^{if_req, d_req_valid}) === 1'bx)
                end_test(1'b0, "X on if_req_o / d_req_valid_o");
            if (d_req_valid && ((^{d_addr, d_we, d_be}) === 1'bx ||
                                (d_we && (^d_wdata) === 1'bx)))
                end_test(1'b0, "X on data request");
            // Luật 1: yêu cầu giữ nguyên trong wait state
            if (req_wait_q && (!d_req_valid || d_addr !== req_addr_q || d_we !== req_we_q ||
                               d_be !== req_be_q || d_wdata !== req_wdata_q))
                end_test(1'b0, "request changed/dropped while d_req_ready = 0");
            // Luật 3: tối đa một yêu cầu đang chờ
            if (d_acc && pend_q && !d_rsp_valid)
                end_test(1'b0, "new request while a response is pending");
            // Khi ngủ: không lấy lệnh, không truy cập dữ liệu, WB trống
            if (core_sleep && (if_req || d_req_valid || dut.wb_valid_q))
                end_test(1'b0, "core active while core_sleep_o = 1");
        end
        req_wait_q  <= d_req_valid & ~d_req_ready;
        req_addr_q  <= d_addr;
        req_we_q    <= d_we;
        req_be_q    <= d_be;
        req_wdata_q <= d_wdata;
    end

    // ------------------------------------------------------- theo dõi WB
    integer    prev_cycle     = 0;
    reg        have_prev      = 1'b0;
    reg        prev_imem_data = 1'b0;
    reg        prev_taken     = 1'b0;
    reg        prev_wb_redir  = 1'b0;
    integer    prev_sleep     = 0;
    reg        redirect_q     = 1'b0;   // lệnh đang ở WB đã chuyển hướng PC khi ở EX
    integer    gap, allowed;

    wire [4:0] wb_opcode_hi = dut.wb_instr_q[6:2];
    wire       wb_is_md     = (dut.wb_instr_q[6:0] == `RV_OPC_OP) &&
                              (dut.wb_instr_q[31:25] == `RV_F7_MULDIV) && (ENABLE_M != 0);

    // Lệnh nhảy rời EX với ex_redirect = 1 và luôn hoàn thành ở chu kỳ sau
    always @(posedge clk)
        redirect_q <= dut.ex_redirect;

    always @(posedge clk) begin
        if (rst_n) begin
            cycle = cycle + 1;
            if (cycle >= timeout)
                end_test(1'b0, "timeout");

            if (dut.wb_retire) begin
                if (dut.wb_trap && dut.csr_mtvec == 32'h0) begin
                    $sformat(msg, "trap cause %0s%0d at pc %08h (instr %08h, tval %08h) with no handler",
                             dut.wb_int_q ? "irq " : "", dut.wb_trap_cause, dut.wb_pc_q,
                             dut.wb_instr_q, dut.wb_trap_tval);
                    end_test(1'b0, msg);
                end
                // Lệnh nhận trap không được truy cập bus (trừ khi chính truy
                // cập đó bị lỗi bus), kể cả lệnh bị ngắt ở EX.
                if (dut.wb_trap && dut.wb_mem_q && !d_rsp_err) begin
                    $sformat(msg, "trapped instr at pc %08h accessed the bus", dut.wb_pc_q);
                    end_test(1'b0, msg);
                end
                if (dut.wb_mem_q && !d_rsp_valid) begin
                    $sformat(msg, "load/store at pc %08h retired without its bus response",
                             dut.wb_pc_q);
                    end_test(1'b0, msg);
                end
                if (dut.wb_rf_we && (^dut.wb_rd_data) === 1'bx) begin
                    $sformat(msg, "X written to x%0d at pc %08h", dut.wb_rd_q, dut.wb_pc_q);
                    end_test(1'b0, msg);
                end

                if (!dut.wb_trap)
                    instret = instret + 1;

                if (trace_en) begin
                    if (dut.wb_trap)
                        $display("core   0: trap %0s%0d, epc 0x%08h, tval 0x%08h",
                                 dut.wb_int_q ? "irq " : "", dut.wb_trap_cause,
                                 dut.wb_pc_q, dut.wb_trap_tval);
                    else if (dut.wb_rf_we)
                        $display("core   0: 3 0x%08h (0x%08h) x%0d%0s0x%08h",
                                 dut.wb_pc_q, dut.wb_instr_q, dut.wb_rd_q,
                                 (dut.wb_rd_q < 10) ? "  " : " ", dut.wb_rd_data);
                    else
                        $display("core   0: 3 0x%08h (0x%08h)", dut.wb_pc_q, dut.wb_instr_q);
                end

                // Số bubble giữa hai lệnh rời WB: đúng 1 sau lệnh nhảy
                // thật (lệnh sai đường bị huỷ, kể cả khi đích là pc+4), 1 sau
                // truy cập dữ liệu vào IMEM (cổng lệnh không được cấp quyền),
                // 2 sau chuyển hướng từ WB (trap, MRET, FENCE.I, WFI), cộng số
                // chu kỳ ngủ. Lệnh RV32M tự dừng EX trước khi tới WB: 1 chu kỳ
                // với MUL*, 33 với DIV/REM (mục 4.9), không xét lệnh M bị ngắt
                // giữa chừng. Còn lại bằng 0, nghĩa là không có stall load-use.
                if (strict_timing && have_prev && !(wb_is_md && dut.wb_trap)) begin
                    gap     = cycle - prev_cycle - 1;
                    allowed = (prev_taken ? 1 : 0) + (prev_imem_data ? 1 : 0) +
                              (prev_wb_redir ? 2 : 0) + (sleep_cycles - prev_sleep) +
                              (wb_is_md ? (dut.wb_instr_q[14] ? 33 : 1) : 0);
                    if (gap != allowed) begin
                        $sformat(msg, "timing: %0d bubble(s) before pc %08h, expected %0d",
                                 gap, dut.wb_pc_q, allowed);
                        end_test(1'b0, msg);
                    end
                end
                have_prev      <= 1'b1;
                prev_cycle     <= cycle;
                prev_taken     <= redirect_q;
                // Chuyển hướng từ WB suy ra từ mã lệnh, không lấy từ core
                prev_wb_redir  <= dut.wb_trap || dut.wb_instr_q == `RV_INSTR_MRET ||
                                  (dut.wb_instr_q[6:0] == `RV_OPC_MISC_MEM &&
                                   dut.wb_instr_q[14:12] == `RV_F3_FENCE_I) ||
                                  (dut.wb_instr_q == `RV_INSTR_WFI && ENABLE_WFI_SLEEP != 0);
                prev_sleep     <= sleep_cycles;
                prev_imem_data <= dut.wb_mem_q && ((dut.wb_result_q - `CORE_TB_IMEM_BASE) < IMEM_SIZE);

                // Test kết thúc khi lệnh ghi vào tohost hoàn thành
                if (dut.wb_mem_q && !dut.wb_trap && wb_opcode_hi == 5'b01000 &&
                    dut.wb_result_q == tohost) begin
                    if (tohost_val == 32'd1)
                        end_test(1'b1, "");
                    else begin
                        $sformat(msg, "tohost = 0x%08h (test %0d)", tohost_val, tohost_val >> 1);
                        end_test(1'b0, msg);
                    end
                end
            end
        end
    end

    // ------------------------------------------------------- khởi động
    initial begin
        if ($value$plusargs("seed=%d", seed)) ;
        seed0 = seed;
        if ($value$plusargs("timeout=%d", timeout)) ;
        if ($value$plusargs("if_stall=%d", if_stall_pct)) ;
        if ($value$plusargs("d_stall=%d", d_stall_pct)) ;
        if ($value$plusargs("rsp_delay=%d", rsp_delay_max)) ;
        if ($value$plusargs("tohost=%h", tohost)) ;
        if ($value$plusargs("test=%s", test_name)) ;
        strict_timing = $test$plusargs("strict_timing");
        trace_en      = $test$plusargs("trace");
        sig_en        = $value$plusargs("signature=%s", sig_file);
        if ($value$plusargs("sig_begin=%h", sig_begin)) ;
        if ($value$plusargs("sig_end=%h", sig_end)) ;
        if (tohost == 32'hFFFF_FFFF)
            $display("WARNING: no +tohost=, the test can only end by timeout");
        if (strict_timing && (if_stall_pct != 0 || d_stall_pct != 0 || rsp_delay_max != 0))
            $display("WARNING: +strict_timing ignores injected stalls, disabled");
        if (if_stall_pct != 0 || d_stall_pct != 0 || rsp_delay_max != 0)
            strict_timing = 1'b0;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
    end

endmodule

`default_nettype wire
