// model_test.h - macro RVMODEL_* của riscv-arch-test cho rv32_core trên tb_core.
// Kết thúc: ghi 1 vào tohost, tb_core báo PASS và ghi signature
// (vùng begin_signature..end_signature) ra file theo +signature=.
#ifndef _COMPLIANCE_MODEL_H
#define _COMPLIANCE_MODEL_H

#define ALIGNMENT 2

// Core ghi mtval = 0 khi ebreak (docs/spec/core.md), nên bỏ bit breakpoint khỏi
// mặt nạ relocate tval như arch_test.h hướng dẫn. Nếu không, trap handler coi
// tval = 0 là địa chỉ ngoài vùng code và bỏ dở test.
#define SET_REL_TVAL_MSK ((1<<CAUSE_MISALIGNED_FETCH | 1<<CAUSE_FETCH_ACCESS                             | \
                           1<<CAUSE_MISALIGNED_LOAD  | 1<<CAUSE_LOAD_ACCESS  | 1<<CAUSE_MISALIGNED_STORE | 1<<CAUSE_STORE_ACCESS | \
                           1<<CAUSE_FETCH_PAGE_FAULT | 1<<CAUSE_LOAD_PAGE_FAULT                          | 1<<CAUSE_STORE_PAGE_FAULT) \
                        & 0xFFFFFFFF)

#define RVMODEL_DATA_SECTION \
        .pushsection .tohost,"aw",@progbits;            \
        .align 6; .global tohost; tohost: .word 0;      \
        .align 6;                                       \
        .popsection;

#define RVMODEL_HALT            \
        li   x1, 1;             \
        la   t2, tohost;        \
        sw   x1, 0(t2);         \
1:      j    1b;

#define RVMODEL_BOOT

#define RVMODEL_DATA_BEGIN      \
        RVMODEL_DATA_SECTION    \
        .align ALIGNMENT;       \
        .global begin_signature; begin_signature:

#define RVMODEL_DATA_END        \
        .global end_signature; end_signature:

#define RVMODEL_IO_INIT
#define RVMODEL_IO_WRITE_STR(_R, _STR)
#define RVMODEL_IO_CHECK()
#define RVMODEL_IO_ASSERT_GPR_EQ(_S, _R, _I)
#define RVMODEL_IO_ASSERT_SFPR_EQ(_F, _R, _I)
#define RVMODEL_IO_ASSERT_DFPR_EQ(_D, _R, _I)

// Bộ test I, M, Zifencei, privilege không dùng ngắt
#define RVMODEL_SET_MSW_INT
#define RVMODEL_CLEAR_MSW_INT
#define RVMODEL_CLEAR_MTIMER_INT
#define RVMODEL_CLEAR_MEXT_INT

#endif // _COMPLIANCE_MODEL_H
