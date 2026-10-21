// rv32_defs.vh - hằng số ISA và core (RV32I + Zicsr + Zicntr + Zifencei + M).
// Dùng macro thay vì localparam để module chỉ dùng một phần không bị
// cảnh báo UNUSEDPARAM khi lint. Mọi tên có tiền tố RV_.
`ifndef RV32_DEFS_VH
`define RV32_DEFS_VH

// ---------------------------------------------------------------------------
// Opcode chính, instr[6:0]
// ---------------------------------------------------------------------------
`define RV_OPC_LOAD       7'b0000011
`define RV_OPC_MISC_MEM   7'b0001111
`define RV_OPC_OP_IMM     7'b0010011
`define RV_OPC_AUIPC      7'b0010111
`define RV_OPC_STORE      7'b0100011
`define RV_OPC_OP         7'b0110011
`define RV_OPC_LUI        7'b0110111
`define RV_OPC_BRANCH     7'b1100011
`define RV_OPC_JALR       7'b1100111
`define RV_OPC_JAL        7'b1101111
`define RV_OPC_SYSTEM     7'b1110011

// ---------------------------------------------------------------------------
// funct3
// ---------------------------------------------------------------------------
// BRANCH
`define RV_F3_BEQ         3'b000
`define RV_F3_BNE         3'b001
`define RV_F3_BLT         3'b100
`define RV_F3_BGE         3'b101
`define RV_F3_BLTU        3'b110
`define RV_F3_BGEU        3'b111
// LOAD / STORE (bit 2 = load không dấu, bit 1:0 = kích thước)
`define RV_F3_LB          3'b000
`define RV_F3_LH          3'b001
`define RV_F3_LW          3'b010
`define RV_F3_LBU         3'b100
`define RV_F3_LHU         3'b101
`define RV_F3_SB          3'b000
`define RV_F3_SH          3'b001
`define RV_F3_SW          3'b010
// OP / OP-IMM
`define RV_F3_ADD_SUB     3'b000
`define RV_F3_SLL         3'b001
`define RV_F3_SLT         3'b010
`define RV_F3_SLTU        3'b011
`define RV_F3_XOR         3'b100
`define RV_F3_SRL_SRA     3'b101
`define RV_F3_OR          3'b110
`define RV_F3_AND         3'b111
// MISC-MEM
`define RV_F3_FENCE       3'b000
`define RV_F3_FENCE_I     3'b001
// SYSTEM
`define RV_F3_PRIV        3'b000
`define RV_F3_CSRRW       3'b001
`define RV_F3_CSRRS       3'b010
`define RV_F3_CSRRC       3'b011
`define RV_F3_CSRRWI      3'b101
`define RV_F3_CSRRSI      3'b110
`define RV_F3_CSRRCI      3'b111
// OP có funct7 = MULDIV
`define RV_F3_MUL         3'b000
`define RV_F3_MULH        3'b001
`define RV_F3_MULHSU      3'b010
`define RV_F3_MULHU       3'b011
`define RV_F3_DIV         3'b100
`define RV_F3_DIVU        3'b101
`define RV_F3_REM         3'b110
`define RV_F3_REMU        3'b111

// ---------------------------------------------------------------------------
// funct7, instr[31:25]
// ---------------------------------------------------------------------------
`define RV_F7_BASE        7'b0000000
`define RV_F7_ALT         7'b0100000   // SUB, SRA, SRAI
`define RV_F7_MULDIV      7'b0000001

// ---------------------------------------------------------------------------
// Mã lệnh cố định cả word
// ---------------------------------------------------------------------------
`define RV_INSTR_NOP      32'h0000_0013   // addi x0, x0, 0
`define RV_INSTR_ECALL    32'h0000_0073
`define RV_INSTR_EBREAK   32'h0010_0073
`define RV_INSTR_MRET     32'h3020_0073
`define RV_INSTR_WFI      32'h1050_0073

// ---------------------------------------------------------------------------
// Mã điều khiển từ decoder sang datapath
// ---------------------------------------------------------------------------
// Phép ALU = {bit alt (instr[30] cho SUB/SRA), funct3}
`define RV_ALU_ADD        4'b0000
`define RV_ALU_SUB        4'b1000
`define RV_ALU_SLL        4'b0001
`define RV_ALU_SLT        4'b0010
`define RV_ALU_SLTU       4'b0011
`define RV_ALU_XOR        4'b0100
`define RV_ALU_SRL        4'b0101
`define RV_ALU_SRA        4'b1101
`define RV_ALU_OR         4'b0110
`define RV_ALU_AND        4'b0111

// Chọn toán hạng A của ALU
`define RV_ALU_A_RS1      2'd0
`define RV_ALU_A_PC       2'd1
`define RV_ALU_A_ZERO     2'd2
// Chọn toán hạng B của ALU
`define RV_ALU_B_RS2      1'b0
`define RV_ALU_B_IMM      1'b1

// Dạng immediate
`define RV_IMM_I          3'd0
`define RV_IMM_S          3'd1
`define RV_IMM_B          3'd2
`define RV_IMM_U          3'd3
`define RV_IMM_J          3'd4
`define RV_IMM_Z          3'd5   // uimm của CSR = trường rs1 mở rộng 0

// Nguồn giá trị ghi rd
`define RV_WB_ALU         2'd0   // kết quả ALU (hoặc M-unit) từ EX
`define RV_WB_PC4         2'd1   // địa chỉ trả về của JAL/JALR
`define RV_WB_LOAD        2'd2   // dữ liệu load đã căn chỉnh
`define RV_WB_CSR         2'd3   // giá trị CSR cũ

// Kích thước truy cập bộ nhớ = funct3[1:0]
`define RV_MEM_B          2'b00
`define RV_MEM_H          2'b01
`define RV_MEM_W          2'b10

// Phép CSR = funct3[1:0]
`define RV_CSR_RW         2'b01
`define RV_CSR_RS         2'b10
`define RV_CSR_RC         2'b11

// ---------------------------------------------------------------------------
// Địa chỉ CSR
// ---------------------------------------------------------------------------
`define RV_CSR_MSTATUS    12'h300
`define RV_CSR_MISA       12'h301
`define RV_CSR_MIE        12'h304
`define RV_CSR_MTVEC      12'h305
`define RV_CSR_MSCRATCH   12'h340
`define RV_CSR_MEPC       12'h341
`define RV_CSR_MCAUSE     12'h342
`define RV_CSR_MTVAL      12'h343
`define RV_CSR_MIP        12'h344
`define RV_CSR_MCYCLE     12'hB00
`define RV_CSR_MINSTRET   12'hB02
`define RV_CSR_MCYCLEH    12'hB80
`define RV_CSR_MINSTRETH  12'hB82
`define RV_CSR_CYCLE      12'hC00
`define RV_CSR_TIME       12'hC01
`define RV_CSR_INSTRET    12'hC02
`define RV_CSR_CYCLEH     12'hC80
`define RV_CSR_TIMEH      12'hC81
`define RV_CSR_INSTRETH   12'hC82
`define RV_CSR_MVENDORID  12'hF11
`define RV_CSR_MARCHID    12'hF12
`define RV_CSR_MIMPID     12'hF13
`define RV_CSR_MHARTID    12'hF14

// Vị trí bit trong CSR
`define RV_MSTATUS_MIE    3
`define RV_MSTATUS_MPIE   7
`define RV_MSTATUS_MPP_LO 11
`define RV_MSTATUS_MPP_HI 12
`define RV_MI_MSI         3      // vị trí bit trong mie/mip
`define RV_MI_MTI         7
`define RV_MI_MEI         11

// misa: MXL=1 (32 bit), extension I, thêm M khi ENABLE_M
`define RV_MISA_BASE      32'h4000_0100
`define RV_MISA_M         32'h0000_1000

// ---------------------------------------------------------------------------
// mcause
// ---------------------------------------------------------------------------
`define RV_MCAUSE_INT_BIT          31
`define RV_EXC_INSTR_MISALIGNED    5'd0
`define RV_EXC_INSTR_ACCESS        5'd1
`define RV_EXC_ILLEGAL             5'd2
`define RV_EXC_BREAKPOINT          5'd3
`define RV_EXC_LOAD_MISALIGNED     5'd4
`define RV_EXC_LOAD_ACCESS         5'd5
`define RV_EXC_STORE_MISALIGNED    5'd6
`define RV_EXC_STORE_ACCESS        5'd7
`define RV_EXC_ECALL_M             5'd11
`define RV_INT_MSI                 5'd3
`define RV_INT_MTI                 5'd7
`define RV_INT_MEI                 5'd11

// ---------------------------------------------------------------------------
// Giá trị mặc định của core
// ---------------------------------------------------------------------------
`define RV_RESET_PC_DEFAULT        32'h0001_0000   // boot ROM

`endif // RV32_DEFS_VH
