// model_test.h - riscv-arch-test RVMODEL_* macros for rv32_core on tb_core.
// End of test: write 1 to tohost, tb_core reports PASS and writes the signature
// (begin_signature..end_signature) to the file given by +signature=.
#ifndef _COMPLIANCE_MODEL_H
#define _COMPLIANCE_MODEL_H

#define ALIGNMENT 2

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

// The I, M, Zifencei and privilege tests do not use interrupts
#define RVMODEL_SET_MSW_INT
#define RVMODEL_CLEAR_MSW_INT
#define RVMODEL_CLEAR_MTIMER_INT
#define RVMODEL_CLEAR_MEXT_INT

#endif // _COMPLIANCE_MODEL_H
