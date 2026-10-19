// tb_accel_apb.v - kiểm tra accelerator qua giao diện APB3.
// Chạy: make sim-accel-apb. In "PASS" khi đúng.
`timescale 1ns/1ps
module tb_accel_apb;
    localparam N = 4;
    reg         clk = 1'b0, rst_n = 1'b0;
    reg         psel = 1'b0, penable = 1'b0, pwrite = 1'b0;
    reg  [11:0] paddr = 12'd0;
    reg  [31:0] pwdata = 32'd0;
    wire [31:0] prdata;
    wire        pready, pslverr, irq;

    always #10 clk = ~clk;

    accel_apb #(.N(N)) dut (
        .pclk(clk), .presetn(rst_n), .psel(psel), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pwdata(pwdata), .prdata(prdata), .pready(pready),
        .pslverr(pslverr), .irq(irq)
    );

    integer errors = 0;
    reg err_seen;

    // Giao dịch APB chuẩn: pha setup 1 chu kỳ, pha access tới khi pready
    task apb(input w, input [11:0] a, input [31:0] d, output [31:0] r);
    begin
        @(negedge clk); psel = 1; penable = 0; pwrite = w; paddr = a; pwdata = d;
        @(negedge clk); penable = 1;
        #1 r = prdata; err_seen = pslverr;
        while (!pready) begin @(negedge clk); #1 r = prdata; err_seen = pslverr; end
        @(posedge clk); #1;
        psel = 0; penable = 0;
    end
    endtask

    reg signed [7:0]  A [0:N*N-1];
    reg signed [7:0]  B [0:N*N-1];
    reg signed [31:0] G [0:N*N-1];
    reg [31:0] r;
    integer t, i, j, k, w, seed, guard;

    initial begin
        seed = 777;
        repeat (3) @(posedge clk); rst_n = 1;

        for (t = 0; t < 10; t = t + 1) begin
            for (i = 0; i < N*N; i = i + 1) begin A[i] = $random(seed); B[i] = $random(seed); end
            for (i = 0; i < N; i = i + 1) for (j = 0; j < N; j = j + 1) begin
                G[i*N+j] = 0;
                for (k = 0; k < N; k = k + 1) G[i*N+j] = G[i*N+j] + A[i*N+k]*B[k*N+j];
            end
            for (w = 0; w < N*N/4; w = w + 1) begin
                apb(1, 12'h100 + 4*w, {A[4*w+3], A[4*w+2], A[4*w+1], A[4*w]}, r);
                apb(1, 12'h200 + 4*w, {B[4*w+3], B[4*w+2], B[4*w+1], B[4*w]}, r);
            end
            apb(1, 12'h000, 32'h3, r);                 // START + IRQ_EN
            guard = 0;
            while (!irq) begin @(posedge clk); guard = guard + 1;
                if (guard > 100) begin $display("ERROR: timeout"); $finish; end end
            for (i = 0; i < N*N; i = i + 1) begin
                apb(0, 12'h300 + 4*i, 0, r);
                if (r !== G[i]) begin errors = errors + 1;
                    $display("ERROR test %0d C[%0d] = %0d, mong doi %0d", t, i, $signed(r), G[i]); end
            end
            apb(1, 12'h004, 32'h2, r);                 // xoá DONE
        end

        // Truy cập vùng không định nghĩa phải trả PSLVERR
        apb(0, 12'h400, 0, r); if (!err_seen) begin errors = errors + 1; $display("ERROR: 0x400 khong bao loi"); end
        apb(0, 12'h00C, 0, r); if (!err_seen) begin errors = errors + 1; $display("ERROR: 0x00C khong bao loi"); end
        apb(1, 12'h300, 1, r); if (!err_seen) begin errors = errors + 1; $display("ERROR: ghi C_BUF khong bao loi"); end
        apb(0, 12'h008, 0, r); if (err_seen)  begin errors = errors + 1; $display("ERROR: INFO bao loi sai"); end

        if (errors == 0) $display("PASS: APB3 - 10 phep nhan va 4 kiem tra PSLVERR dung");
        else             $display("FAIL: %0d loi", errors);
        $finish;
    end
endmodule
