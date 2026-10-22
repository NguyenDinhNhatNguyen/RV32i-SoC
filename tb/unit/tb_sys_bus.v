`timescale 1ns/1ps
`default_nettype none
// tb_sys_bus - kiểm tra sys_bus (RTL-03) với N_MASTER = 1 hoặc 2.
//   - Mỗi master phát yêu cầu ngẫu nhiên tới IMEM, DMEM, vùng APB (0x2, 0x3, 0x4)
//     và địa chỉ không ánh xạ, theo đúng luật của master: giữ yêu cầu khi
//     ready = 0, tối đa 1 yêu cầu đang chờ, được phát mới ngay trong chu kỳ có phản hồi.
//   - Slave là mô hình bộ nhớ có wait state (ready = 0) và phản hồi trễ ngẫu nhiên.
//     Mô hình APB trả err ở offset 0xFC.
//   - So dữ liệu đọc và err với tham chiếu cập nhật lúc yêu cầu được nhận, nên
//     bắt được sai slave, sai địa chỉ, sai be, sai master nhận phản hồi.
//   - Phía slave: yêu cầu giữ nguyên khi ready = 0 (luật 1), không có yêu cầu
//     mới khi còn phản hồi chờ, cả bus tối đa 1 yêu cầu chờ, địa chỉ không ánh
//     xạ không tới slave nào và nhận err ở chu kỳ ngay sau.
//   - N_MASTER = 2: cả hai master đều được phục vụ (round-robin).
// Plusarg: +seed=<n> +n=<số yêu cầu mỗi master> +stall=<% ready = 0> +delay=<trễ tối đa>

module tb_sys_bus;

    parameter N_MASTER = 2;
    localparam NM = N_MASTER;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    // ---------------------------------------------------------- tín hiệu
    reg  [NM-1:0]    m_req_valid = 0;
    wire [NM-1:0]    m_req_ready;
    reg  [NM*32-1:0] m_addr  = 0;
    reg  [NM-1:0]    m_we    = 0;
    reg  [NM*4-1:0]  m_be    = 0;
    reg  [NM*32-1:0] m_wdata = 0;
    wire [NM-1:0]    m_rsp_valid, m_rsp_err;
    wire [31:0]      m_rsp_rdata;

    wire [31:0] s_addr, s_wdata;
    wire        s_we;
    wire [3:0]  s_be;
    wire [2:0]  sv;                 // valid của IMEM, DMEM, APB
    wire [2:0]  sr;                 // ready
    wire [2:0]  srv;                // rsp_valid
    wire [31:0] srd0, srd1, srd2;
    wire        apb_err;

    sys_bus #(.N_MASTER(NM)) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .m_req_valid    (m_req_valid),
        .m_req_ready    (m_req_ready),
        .m_addr         (m_addr),
        .m_we           (m_we),
        .m_be           (m_be),
        .m_wdata        (m_wdata),
        .m_rsp_valid    (m_rsp_valid),
        .m_rsp_rdata    (m_rsp_rdata),
        .m_rsp_err      (m_rsp_err),
        .s_addr         (s_addr),
        .s_we           (s_we),
        .s_be           (s_be),
        .s_wdata        (s_wdata),
        .imem_req_valid (sv[0]),
        .imem_req_ready (sr[0]),
        .imem_rsp_valid (srv[0]),
        .imem_rsp_rdata (srd0),
        .dmem_req_valid (sv[1]),
        .dmem_req_ready (sr[1]),
        .dmem_rsp_valid (srv[1]),
        .dmem_rsp_rdata (srd1),
        .apb_req_valid  (sv[2]),
        .apb_req_ready  (sr[2]),
        .apb_rsp_valid  (srv[2]),
        .apb_rsp_rdata  (srd2),
        .apb_rsp_err    (apb_err)
    );

    integer seed = 1, seed0, n_req = 3000, stall_pct = 30, delay_max = 3;
    integer errors = 0, cycle = 0;
    integer i, m;

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

    // Vị trí trong bộ nhớ của mô hình slave
    function [10:0] key(input [31:0] a);
        key = {a[30:28], a[13:12], a[7:2]};
    endfunction

    // Địa chỉ có slave không (khớp bản đồ: IMEM 16 KB, DMEM 16 KB, vùng 0x2-0x4 qua APB)
    function [1:0] which(input [31:0] a);      // 0 IMEM, 1 DMEM, 2 APB, 3 lỗi
        begin
            if (a < 32'h0000_4000)                          which = 2'd0;
            else if (a >= 32'h1000_0000 && a < 32'h1000_4000) which = 2'd1;
            else if (a[31:28] >= 4'h2 && a[31:28] <= 4'h4)  which = 2'd2;
            else                                            which = 2'd3;
        end
    endfunction

    // ---------------------------------------------------------- mô hình slave
    reg  [31:0] smem   [0:3*2048-1];
    reg  [31:0] refm   [0:3*2048-1];
    initial for (i = 0; i < 3*2048; i = i + 1) begin smem[i] = 32'h0; refm[i] = 32'h0; end

    reg  [2:0]  ready_r = 3'b111;
    reg  [2:0]  pend    = 3'b000;
    reg  [2:0]  pend_n;
    integer     cnt [0:2];
    reg  [31:0] sdata [0:2];
    reg  [2:0]  serr  = 3'b000;
    initial for (i = 0; i < 3; i = i + 1) begin cnt[i] = 0; sdata[i] = 0; end

    assign sr      = ready_r;
    assign srv[0]  = pend[0] && cnt[0] == 0;
    assign srv[1]  = pend[1] && cnt[1] == 0;
    assign srv[2]  = pend[2] && cnt[2] == 0;
    assign srd0    = srv[0] ? sdata[0] : 32'hBAD0_0000;
    assign srd1    = srv[1] ? sdata[1] : 32'hBAD0_0001;
    assign srd2    = srv[2] ? sdata[2] : 32'hBAD0_0002;
    assign apb_err = srv[2] & serr[2];

    // Yêu cầu chưa được nhận ở chu kỳ trước, phía slave
    reg  [2:0]  sw_q = 3'b000;
    reg  [31:0] sw_addr_q, sw_wdata_q;
    reg         sw_we_q;
    reg  [3:0]  sw_be_q;
    integer     s, n_pend;
    reg  [10:0] kk;

    always @(posedge clk) begin
        if (rst_n) begin
            cycle = cycle + 1;
            if ((sv & (sv - 1'b1)) != 0) fail("nhieu slave cung co valid");
            for (s = 0; s < 3; s = s + 1) begin
                if (sw_q[s] && (!sv[s] || s_addr !== sw_addr_q || s_we !== sw_we_q ||
                                s_be !== sw_be_q || (s_we && s_wdata !== sw_wdata_q)))
                    fail("yeu cau phia slave doi khi ready = 0");
                if (sv[s] && pend[s] && !srv[s])
                    fail("slave nhan yeu cau moi khi con phan hoi cho");
                if (sv[s] && which(s_addr) != s)
                    fail("yeu cau toi sai slave");
            end
            // Phản hồi xong, rồi nhận yêu cầu mới. Trạng thái mô hình gán non-blocking
            // để DUT ở cùng cạnh lên vẫn thấy giá trị cũ.
            for (s = 0; s < 3; s = s + 1) begin
                pend_n[s] = pend[s];
                if (srv[s]) pend_n[s] = 1'b0;
                else if (pend[s]) cnt[s] <= cnt[s] - 1;
                if (sv[s] && sr[s]) begin
                    kk = key(s_addr);
                    pend_n[s] = 1'b1;
                    cnt[s]  <= $unsigned($random(seed)) % (delay_max + 1);
                    serr[s] <= (s == 2) && (s_addr[7:2] == 6'h3F);
                    if ((s == 2) && (s_addr[7:2] == 6'h3F))
                        sdata[s] <= 32'h0;
                    else if (s_we) begin
                        smem[s*2048 + kk] = merge(smem[s*2048 + kk], s_wdata, s_be);
                        sdata[s] <= 32'h0;
                    end else
                        sdata[s] <= smem[s*2048 + kk];
                end
            end
            pend <= pend_n;
            n_pend = pend_n[0] + pend_n[1] + pend_n[2];
            if (n_pend > 1) fail("hon 1 yeu cau dang cho tren bus");
            sw_q       <= sv & ~sr;
            sw_addr_q  <= s_addr;
            sw_wdata_q <= s_wdata;
            sw_we_q    <= s_we;
            sw_be_q    <= s_be;
        end
    end

    always @(negedge clk)
        for (s = 0; s < 3; s = s + 1)
            ready_r[s] = ($unsigned($random(seed)) % 100) >= stall_pct;

    // ---------------------------------------------------------- master
    reg  [NM-1:0] mp      = 0;      // master có yêu cầu đã nhận, chờ phản hồi
    reg  [NM-1:0] macc_q  = 0;      // yêu cầu của master được nhận ở cạnh lên vừa qua
    reg  [NM-1:0] exp_err = 0;
    reg  [NM-1:0] exp_rd  = 0;
    reg  [31:0]   exp_data [0:NM-1];
    reg  [NM-1:0] exp_unmapped = 0;
    integer       issued [0:NM-1];
    integer       accepted [0:NM-1];
    integer       n_err_unm = 0, n_err_apb = 0, n_rd = 0, n_wr = 0, n_b2b = 0;
    reg  [31:0]   a;
    reg  [1:0]    w;
    reg           unm_now;
    initial for (i = 0; i < NM; i = i + 1) begin issued[i] = 0; accepted[i] = 0; exp_data[i] = 0; end

    always @(posedge clk) begin
        if (rst_n) begin
            for (m = 0; m < NM; m = m + 1) begin
                if (m_rsp_err[m] && !m_rsp_valid[m]) fail("rsp_err khi khong co rsp_valid");
                if (m_rsp_valid[m]) begin
                    if (!mp[m]) fail("phan hoi khi master khong cho");
                    if (m_rsp_err[m] !== exp_err[m]) begin
                        $display("      master %0d: err %b, mong doi %b", m, m_rsp_err[m], exp_err[m]);
                        fail("err sai");
                    end
                    if (!exp_err[m] && exp_rd[m] && m_rsp_rdata !== exp_data[m]) begin
                        $display("      master %0d: doc %h, mong doi %h", m, m_rsp_rdata, exp_data[m]);
                        fail("du lieu doc sai");
                    end
                    if (exp_err[m] && m_rsp_rdata !== 32'h0) fail("err nhung rdata khac 0");
                    mp[m] = 1'b0;
                end
            end
            // Địa chỉ không ánh xạ phải có phản hồi ở chu kỳ ngay sau
            for (m = 0; m < NM; m = m + 1)
                if (macc_q[m] && exp_unmapped[m] && !m_rsp_valid[m])
                    fail("dia chi khong anh xa phai tra loi o chu ky sau");
            for (m = 0; m < NM; m = m + 1) begin
                macc_q[m] = m_req_valid[m] & m_req_ready[m];
                if (macc_q[m]) begin
                    if (mp[m]) fail("nhan yeu cau khi master con cho");
                    if (m_rsp_valid != 0) n_b2b = n_b2b + 1;
                    a = m_addr[m*32 +: 32];
                    w = which(a);
                    kk = key(a);
                    mp[m] = 1'b1;
                    accepted[m] = accepted[m] + 1;
                    exp_unmapped[m] = (w == 2'd3);
                    exp_err[m] = (w == 2'd3) || (w == 2'd2 && a[7:2] == 6'h3F);
                    exp_rd[m]  = ~m_we[m];
                    if (w == 2'd3) n_err_unm = n_err_unm + 1;
                    else if (exp_err[m]) n_err_apb = n_err_apb + 1;
                    else if (m_we[m]) begin
                        refm[w*2048 + kk] = merge(refm[w*2048 + kk], m_wdata[m*32 +: 32], m_be[m*4 +: 4]);
                        n_wr = n_wr + 1;
                    end else begin
                        exp_data[m] = refm[w*2048 + kk];
                        n_rd = n_rd + 1;
                    end
                end
            end
        end
    end

    // Phát yêu cầu ở cạnh xuống. m_rsp_valid lúc này là của chu kỳ hiện tại.
    always @(negedge clk) begin
        if (rst_n) begin
            for (m = 0; m < NM; m = m + 1) begin
                if (m_req_valid[m] && !macc_q[m]) begin
                    // giữ nguyên (luật 1)
                end else if (issued[m] < n_req && (!mp[m] || m_rsp_valid[m]) &&
                             ($unsigned($random(seed)) % 5) != 0) begin
                    case ($unsigned($random(seed)) % 12)
                        0, 1, 2:  a = 32'h0000_0000;
                        3, 4, 5:  a = 32'h1000_0000;
                        6, 7:     a = 32'h2000_0000 + (($unsigned($random(seed)) % 4) << 12);
                        8:        a = 32'h3000_0000;
                        9:        a = 32'h4000_0000;
                        default: begin
                            case ($unsigned($random(seed)) % 6)
                                0: a = 32'h0000_4000;
                                1: a = 32'h0001_0000;       // boot ROM: bus dữ liệu không đọc được
                                2: a = 32'h1000_4000;
                                3: a = 32'h5000_0000;
                                4: a = 32'hF000_0000;
                                default: a = 32'h0FFF_FF00;
                            endcase
                        end
                    endcase
                    a = a + (($unsigned($random(seed)) % 64) << 2);
                    m_req_valid[m]          = 1'b1;
                    m_addr[m*32 +: 32]      = a;
                    m_we[m]                 = $random(seed);
                    m_wdata[m*32 +: 32]     = $random(seed);
                    case ($unsigned($random(seed)) % 4)
                        0: m_be[m*4 +: 4] = 4'b0001 << ($unsigned($random(seed)) % 4);
                        1: m_be[m*4 +: 4] = 4'b1100;
                        default: m_be[m*4 +: 4] = 4'b1111;
                    endcase
                    issued[m] = issued[m] + 1;
                end else begin
                    m_req_valid[m]      = 1'b0;
                    m_addr[m*32 +: 32]  = 32'hxxxx_xxxx;
                    m_wdata[m*32 +: 32] = 32'hxxxx_xxxx;
                end
            end
        end
    end

    integer total, busy;
    initial begin
        if ($value$plusargs("seed=%d", seed)) ;
        if ($value$plusargs("n=%d", n_req)) ;
        if ($value$plusargs("stall=%d", stall_pct)) ;
        if ($value$plusargs("delay=%d", delay_max)) ;
        seed0 = seed;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        busy = 1;
        while (busy && cycle < 50 * n_req * NM) begin
            @(posedge clk);
            busy = (m_req_valid != 0) || (mp != 0);
            for (i = 0; i < NM; i = i + 1)
                if (issued[i] < n_req) busy = 1;
        end
        repeat (3) @(posedge clk);
        if (busy) fail("qua thoi gian");
        total = 0;
        for (i = 0; i < NM; i = i + 1) begin
            total = total + accepted[i];
            if (accepted[i] != n_req) fail("master khong duoc phuc vu du");
        end
        if (n_err_unm == 0 || n_err_apb == 0 || n_rd == 0 || n_wr == 0 || n_b2b == 0)
            fail("thieu loai giao dich");
        if (errors == 0)
            $display("PASS: tb_sys_bus N_MASTER=%0d: %0d yeu cau (%0d doc, %0d ghi, %0d err khong anh xa, %0d err APB), %0d yeu cau nhan trong chu ky phan hoi, %0d chu ky (seed %0d)",
                     NM, total, n_rd, n_wr, n_err_unm, n_err_apb, n_b2b, cycle, seed0);
        else
            $display("FAIL: tb_sys_bus N_MASTER=%0d: %0d loi (seed %0d)", NM, errors, seed0);
        $finish;
    end

endmodule

`default_nettype wire
