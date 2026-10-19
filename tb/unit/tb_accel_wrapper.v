// tb_accel_wrapper.v - kiểm tra wrapper accelerator qua bus MMIO.
// Chạy: make sim-accel. In "PASS" khi mọi phép nhân khớp mô hình vàng.
`timescale 1ns/1ps
module tb_accel_wrapper;
    localparam N = 4;
    localparam NTEST = 40;

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         s_valid = 1'b0, s_we = 1'b0;
    reg  [11:0] s_addr = 12'd0;
    reg  [31:0] s_wdata = 32'd0;
    reg  [3:0]  s_wstrb = 4'd0;
    wire        s_ready;
    wire [31:0] s_rdata;
    wire        irq;

    always #10 clk = ~clk;   // 50 MHz

    accel_wrapper #(.N(N)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_valid(s_valid), .s_we(s_we), .s_addr(s_addr), .s_wdata(s_wdata),
        .s_wstrb(s_wstrb), .s_ready(s_ready), .s_rdata(s_rdata), .irq(irq)
    );

    integer errors = 0;

    task bus_write(input [11:0] a, input [31:0] d, input [3:0] strb);
    begin
        @(negedge clk);
        s_valid = 1'b1; s_we = 1'b1; s_addr = a; s_wdata = d; s_wstrb = strb;
        @(posedge clk); #1;
        if (!s_ready) begin $display("ERROR: ready thap khi ghi"); errors = errors + 1; end
        s_valid = 1'b0; s_we = 1'b0; s_wstrb = 4'd0;
    end
    endtask

    task bus_read(input [11:0] a, output [31:0] d);
    begin
        @(negedge clk);
        s_valid = 1'b1; s_we = 1'b0; s_addr = a;
        #1 d = s_rdata;
        @(posedge clk); #1;
        s_valid = 1'b0;
    end
    endtask

    reg signed [7:0]  A [0:N*N-1];
    reg signed [7:0]  B [0:N*N-1];
    reg signed [31:0] G [0:N*N-1];
    reg [31:0] rd, word;
    integer t, i, j, k, w, cycles, seed;

`ifdef DUMP_VCD
    initial begin $dumpfile("accel.vcd"); $dumpvars(0, tb_accel_wrapper); end
`endif

    initial begin
        seed = 12345;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        bus_read(12'h008, rd);
        if (rd !== {8'd4, 8'd8, 8'd20, 8'd10}) begin
            $display("ERROR: INFO = %h", rd); errors = errors + 1;
        end

        for (t = 0; t < NTEST; t = t + 1) begin
            // tạo dữ liệu: 2 lần đầu là trường hợp biên
            for (i = 0; i < N*N; i = i + 1) begin
                if (t == 0)      begin A[i] = -8'sd128; B[i] = -8'sd128; end
                else if (t == 1) begin A[i] =  8'sd127; B[i] = -8'sd128; end
                else begin A[i] = $random(seed); B[i] = $random(seed); end
            end
            for (i = 0; i < N; i = i + 1)
                for (j = 0; j < N; j = j + 1) begin
                    G[i*N+j] = 0;
                    for (k = 0; k < N; k = k + 1)
                        G[i*N+j] = G[i*N+j] + A[i*N+k] * B[k*N+j];
                end

            // nạp A, B: 4 byte mỗi lần ghi
            for (w = 0; w < N*N/4; w = w + 1) begin
                bus_write(12'h100 + 4*w, {A[4*w+3], A[4*w+2], A[4*w+1], A[4*w]}, 4'hF);
                bus_write(12'h200 + 4*w, {B[4*w+3], B[4*w+2], B[4*w+1], B[4*w]}, 4'hF);
            end
            // kiểm tra đọc lại bộ đệm
            bus_read(12'h104, rd);
            if (rd !== {A[7], A[6], A[5], A[4]}) begin
                $display("ERROR: doc lai A_BUF sai %h", rd); errors = errors + 1;
            end

            // START, bật ngắt
            bus_write(12'h000, 32'h3, 4'h1);
            // ghi vào A khi đang bận phải bị bỏ qua
            bus_write(12'h100, 32'hDEADBEEF, 4'hF);
            cycles = 0;
            rd = 32'h1;
            while (rd[1] == 1'b0) begin
                bus_read(12'h004, rd);
                cycles = cycles + 1;
                if (cycles > 100) begin $display("ERROR: timeout"); $finish; end
            end
            if (!irq) begin $display("ERROR: irq khong len khi DONE"); errors = errors + 1; end
            if (rd[0]) begin $display("ERROR: van BUSY khi DONE"); errors = errors + 1; end

            for (i = 0; i < N*N; i = i + 1) begin
                bus_read(12'h300 + 4*i, rd);
                if (rd !== G[i]) begin
                    $display("ERROR test %0d C[%0d][%0d] = %0d, mong doi %0d",
                             t, i/N, i%N, $signed(rd), G[i]);
                    errors = errors + 1;
                end
            end
            bus_read(12'h100, rd);
            if (rd === 32'hDEADBEEF) begin
                $display("ERROR: A_BUF bi ghi de khi BUSY"); errors = errors + 1;
            end

            // xoá DONE (W1C), irq phải xuống
            bus_write(12'h004, 32'h2, 4'h1);
            #1 if (irq) begin $display("ERROR: irq chua xuong sau W1C"); errors = errors + 1; end
        end

        if (errors == 0) $display("PASS: %0d phep nhan ma tran %0dx%0d khop mo hinh vang", NTEST, N, N);
        else             $display("FAIL: %0d loi", errors);
        $finish;
    end
endmodule
