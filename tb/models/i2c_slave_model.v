`timescale 1ns/1ps
`default_nettype none
// i2c_slave_model - behavioral I2C slave for tb_i2c_apb and tb_soc (RTL-14). Simulation only.
//
// Sits on an open-drain bus: scl and sda are the wired lines (pull-ups in the tb). The model
// only pulls sda low through sda_pull and never stretches scl.
//   - START (sda falls while scl is high) and STOP (sda rises while scl is high) are counted.
//     A repeated START is a START that comes before a STOP.
//   - The first byte after a START is the address. The model ACKs only ADDR.
//   - Write (R/W = 0): the first data byte sets the pointer of a 16-byte memory, the next
//     bytes are stored at the pointer, which then counts up. Every byte gets an ACK.
//   - Read (R/W = 1): the model sends mem[ptr], mem[ptr + 1], ... until the master NACKs.
//   - Bits are sampled on the rising edge of scl and sda changes after its falling edge.
//   - n_err counts START or STOP in the middle of a byte. sda changing while scl is high
//     always looks like a START or STOP, so this also catches data that moves too late.
// The tb reads n_start, n_stop, n_err, n_bytes, last_ack (bit the master sent in the ACK
// clock of a read, 0 = ACK) and mem[] by hierarchical reference.
module i2c_slave_model #(
    parameter [6:0] ADDR = 7'h50
) (
    input  wire scl,
    input  wire sda,
    output wire sda_pull            // 1 = pull sda low
);

    reg  [7:0] mem [0:15];
    reg  [3:0] ptr       = 4'd0;
    reg        ptr_set   = 1'b0;    // The pointer byte of this write came in
    reg  [7:0] shift     = 8'd0;
    reg  [7:0] tx_byte   = 8'd0;
    integer    bitpos    = 0;       // scl rising edges in this byte, 8 = data done, 9 = ACK done
    reg        in_frame  = 1'b0;    // Between a START and a STOP
    reg        addr_next = 1'b0;    // The byte in progress is the address
    reg        addr_done = 1'b0;    // The byte that just ended was the address
    reg        selected  = 1'b0;    // Address matched
    reg        rd_mode   = 1'b0;    // Slave transmits
    reg        tx_on     = 1'b0;    // Slave is sending data bits
    reg        drive     = 1'b0;
    reg        last_ack  = 1'b1;
    integer    n_start = 0, n_stop = 0, n_err = 0, n_bytes = 0;
    integer    i;

    initial for (i = 0; i < 16; i = i + 1) mem[i] = 8'hA0 + i[7:0];

    assign sda_pull = drive;

    // A START or STOP raises scl first, so bitpos may already be 1 here. 2 to 8 is mid-byte.
    always @(negedge sda)
        if (scl === 1'b1) begin
            if (in_frame && bitpos >= 2 && bitpos <= 8) n_err = n_err + 1;
            n_start   = n_start + 1;
            in_frame  = 1'b1;
            addr_next = 1'b1;
            selected  = 1'b0;
            rd_mode   = 1'b0;
            tx_on     = 1'b0;
            ptr_set   = 1'b0;
            bitpos    = 0;
            drive     = 1'b0;
        end
    // Only inside a frame, so the x to 1 step of the lines at time 0 is not a STOP
    always @(posedge sda)
        if (scl === 1'b1 && in_frame) begin
            if (bitpos >= 2 && bitpos <= 8) n_err = n_err + 1;
            n_stop   = n_stop + 1;
            in_frame = 1'b0;
            selected = 1'b0;
            tx_on    = 1'b0;
            drive    = 1'b0;
        end

    always @(posedge scl)
        if (in_frame) begin
            if (bitpos == 9) bitpos = 0;
            if (bitpos < 8) begin
                shift  = {shift[6:0], sda};
                bitpos = bitpos + 1;
            end else begin
                if (tx_on) last_ack = sda;          // Master ACK or NACK
                bitpos = 9;
            end
        end

    always @(negedge scl)
        if (in_frame) begin
            if (bitpos >= 1 && bitpos <= 7) begin
                // Next data bit
                drive = tx_on & ~tx_byte[7 - bitpos];
            end else if (bitpos == 8) begin
                // Data done, the ACK clock comes next
                addr_done = addr_next;
                if (addr_next) begin
                    addr_next = 1'b0;
                    selected  = (shift[7:1] == ADDR);
                    rd_mode   = shift[0];
                    drive     = selected;
                    n_bytes   = n_bytes + 1;
                end else if (selected && !rd_mode) begin
                    if (!ptr_set) begin
                        ptr     = shift[3:0];
                        ptr_set = 1'b1;
                    end else begin
                        mem[ptr] = shift;
                        ptr      = ptr + 4'd1;
                    end
                    drive   = 1'b1;
                    n_bytes = n_bytes + 1;
                end else begin
                    drive = 1'b0;                   // Released for the master ACK
                end
            end else if (bitpos == 9) begin
                // ACK clock done: start or continue a read, or release sda
                if (selected && rd_mode && (addr_done || (tx_on && last_ack == 1'b0))) begin
                    tx_byte = mem[ptr];
                    ptr     = ptr + 4'd1;
                    tx_on   = 1'b1;
                    drive   = ~tx_byte[7];
                    n_bytes = n_bytes + 1;
                end else begin
                    tx_on = 1'b0;
                    drive = 1'b0;
                end
                addr_done = 1'b0;
            end
        end

endmodule

`default_nettype wire
