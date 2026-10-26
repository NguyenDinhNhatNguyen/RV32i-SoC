`timescale 1ns/1ps
`default_nettype none
// rv32_btb - branch target buffer for rv32_core (ENABLE_BTB = 1, docs/btb_eval.md).
// Direct mapped, ENTRIES entries indexed by pc[IDX_W+1:2]. Each entry holds a valid bit, the
// full tag pc[31:IDX_W+2], the target [31:2] and a 2-bit saturating counter.
//   - Lookup (IF): combinational from the fetch PC. Predict taken when the entry hits and
//     counter bit 1 = 1.
//   - Update (EX): branches and JAL that leave EX. A hit moves the counter toward the outcome.
//     A miss that is taken allocates the entry (JAL counter 3, branch counter 2).
//     JALR is never stored, its target comes from a register.
//   - flush_i (FENCE.I in WB) clears every valid bit, so changed code is never predicted.
// The tag is the full PC, so a hit always means the same branch or JAL, whose target does
// not change. EX therefore only checks the direction.
// Every flop has an asynchronous reset to 0 so gate-level simulation has no X.

module rv32_btb #(
    parameter ENTRIES = 8               // Power of 2, at least 2
) (
    input  wire        clk,
    input  wire        rst_n,
    // Lookup
    input  wire [31:0] if_pc_i,
    output wire        pred_taken_o,
    output wire [31:0] pred_target_o,
    // Update
    input  wire        upd_i,           // A branch or JAL leaves EX
    input  wire [31:0] upd_pc_i,
    input  wire        upd_jal_i,
    input  wire        upd_taken_i,
    input  wire [31:0] upd_target_i,
    input  wire        flush_i
);

    localparam IDX_W = $clog2(ENTRIES);
    localparam TAG_W = 30 - IDX_W;

    wire             e_valid  [0:ENTRIES-1];
    wire [TAG_W-1:0] e_tag    [0:ENTRIES-1];
    wire [29:0]      e_target [0:ENTRIES-1];
    wire [1:0]       e_cnt    [0:ENTRIES-1];

    // ---- Update -------------------------------------------------------------------
    wire [IDX_W-1:0] u_idx = upd_pc_i[IDX_W+1:2];
    wire [TAG_W-1:0] u_tag = upd_pc_i[31:IDX_W+2];
    wire             u_hit = e_valid[u_idx] & (e_tag[u_idx] == u_tag);
    wire [1:0]       u_cnt = e_cnt[u_idx];
    wire             u_alloc = upd_i & ~u_hit & upd_taken_i;
    wire             u_train = upd_i & u_hit;

    reg  [1:0] u_cnt_next;
    always @(*) begin
        u_cnt_next = u_cnt;
        if (upd_taken_i && u_cnt != 2'b11)
            u_cnt_next = u_cnt + 2'b01;
        else if (!upd_taken_i && u_cnt != 2'b00)
            u_cnt_next = u_cnt - 2'b01;
    end

    genvar g;
    generate
        for (g = 0; g < ENTRIES; g = g + 1) begin : g_entry
            reg             valid_q;
            reg [TAG_W-1:0] tag_q;
            reg [29:0]      target_q;
            reg [1:0]       cnt_q;
            wire            sel = (u_idx == g);

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    valid_q <= 1'b0;
                else if (flush_i)
                    valid_q <= 1'b0;
                else if (u_alloc & sel)
                    valid_q <= 1'b1;
            end

            // Tag and target change only on allocation (one enable group each)
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    tag_q    <= {TAG_W{1'b0}};
                    target_q <= 30'h0;
                end else if (u_alloc & sel) begin
                    tag_q    <= u_tag;
                    target_q <= upd_target_i[31:2];
                end
            end

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    cnt_q <= 2'b00;
                else if (u_alloc & sel)
                    cnt_q <= {1'b1, upd_jal_i};
                else if (u_train & sel)
                    cnt_q <= u_cnt_next;
            end

            assign e_valid[g]  = valid_q;
            assign e_tag[g]    = tag_q;
            assign e_target[g] = target_q;
            assign e_cnt[g]    = cnt_q;
        end
    endgenerate

    // ---- Lookup -------------------------------------------------------------------
    wire [IDX_W-1:0] l_idx = if_pc_i[IDX_W+1:2];
    wire             l_hit = e_valid[l_idx] & (e_tag[l_idx] == if_pc_i[31:IDX_W+2]);

    assign pred_taken_o  = l_hit & e_cnt[l_idx][1];
    assign pred_target_o = {e_target[l_idx], 2'b00};

    // Bits 1:0 are always 0 (instructions are word aligned, a misaligned target traps)
    wire unused_ok = &{1'b0, if_pc_i[1:0], upd_pc_i[1:0], upd_target_i[1:0]};

endmodule

`default_nettype wire
