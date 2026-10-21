// smoke.S - mọi lệnh RV32I (trừ SYSTEM / FENCE.I mà P3 chưa thực thi) với
// toán hạng biên, giá trị kỳ vọng tính sẵn.
// Test 2..516: ALU thanh ghi/immediate, dịch, LUI, nhánh (nhảy / không nhảy,
// biên có dấu và không dấu), load (mọi kích thước, mở rộng dấu/0, offset âm),
// store (kiểm tra làn trên cả word).
// Test 600..: x0, AUIPC, địa chỉ trả về và đích JAL/JALR, FENCE, truy cập dữ
// liệu vào IMEM, vòng lặp nhánh lùi.
#include "test_macros.h"

TEST_CODE_BEGIN
    nop                         // word đầu = 0x00000013, đọc lại ở test 640

    TEST_RR(2, add, 0x00000000, 0x00000000, 0x00000000)
    TEST_RR(3, add, 0x00000002, 0x00000001, 0x00000001)
    TEST_RR(4, add, 0x0000000a, 0x00000003, 0x00000007)
    TEST_RR(5, add, 0x0000000a, 0x00000007, 0x00000003)
    TEST_RR(6, add, 0x80000000, 0x7fffffff, 0x00000001)
    TEST_RR(7, add, 0x7fffffff, 0x80000000, 0xffffffff)
    TEST_RR(8, add, 0x00000000, 0xffffffff, 0x00000001)
    TEST_RR(9, add, 0x21436587, 0x12345678, 0x0f0f0f0f)
    TEST_RR(10, add, 0xffffffff, 0x80000000, 0x7fffffff)
    TEST_RR(11, add, 0xffffffff, 0xffff8000, 0x00007fff)
    TEST_RR(12, add, 0xa9acaefc, 0xdeadbeef, 0xcafef00d)
    TEST_RR(13, sub, 0x00000000, 0x00000000, 0x00000000)
    TEST_RR(14, sub, 0x00000000, 0x00000001, 0x00000001)
    TEST_RR(15, sub, 0xfffffffc, 0x00000003, 0x00000007)
    TEST_RR(16, sub, 0x00000004, 0x00000007, 0x00000003)
    TEST_RR(17, sub, 0x7ffffffe, 0x7fffffff, 0x00000001)
    TEST_RR(18, sub, 0x80000001, 0x80000000, 0xffffffff)
    TEST_RR(19, sub, 0xfffffffe, 0xffffffff, 0x00000001)
    TEST_RR(20, sub, 0x03254769, 0x12345678, 0x0f0f0f0f)
    TEST_RR(21, sub, 0x00000001, 0x80000000, 0x7fffffff)
    TEST_RR(22, sub, 0xffff0001, 0xffff8000, 0x00007fff)
    TEST_RR(23, sub, 0x13aecee2, 0xdeadbeef, 0xcafef00d)
    TEST_RR(24, sll, 0x80000001, 0x80000001, 0x00000000)
    TEST_RR(25, sll, 0x00000002, 0x80000001, 0x00000001)
    TEST_RR(26, sll, 0x00000080, 0x80000001, 0x00000007)
    TEST_RR(27, sll, 0x80000000, 0x80000001, 0x0000001f)
    TEST_RR(28, sll, 0xd159c000, 0x81234567, 0x0000000e)
    TEST_RR(29, sll, 0x02468ace, 0x81234567, 0xffffffe1)
    TEST_RR(30, sll, 0x80000000, 0x7fffffff, 0x0000001f)
    TEST_RR(31, sll, 0x80000000, 0x00000001, 0xffffffff)
    TEST_RR(32, srl, 0x80000001, 0x80000001, 0x00000000)
    TEST_RR(33, srl, 0x40000000, 0x80000001, 0x00000001)
    TEST_RR(34, srl, 0x01000000, 0x80000001, 0x00000007)
    TEST_RR(35, srl, 0x00000001, 0x80000001, 0x0000001f)
    TEST_RR(36, srl, 0x0002048d, 0x81234567, 0x0000000e)
    TEST_RR(37, srl, 0x4091a2b3, 0x81234567, 0xffffffe1)
    TEST_RR(38, srl, 0x00000000, 0x7fffffff, 0x0000001f)
    TEST_RR(39, srl, 0x00000000, 0x00000001, 0xffffffff)
    TEST_RR(40, sra, 0x80000001, 0x80000001, 0x00000000)
    TEST_RR(41, sra, 0xc0000000, 0x80000001, 0x00000001)
    TEST_RR(42, sra, 0xff000000, 0x80000001, 0x00000007)
    TEST_RR(43, sra, 0xffffffff, 0x80000001, 0x0000001f)
    TEST_RR(44, sra, 0xfffe048d, 0x81234567, 0x0000000e)
    TEST_RR(45, sra, 0xc091a2b3, 0x81234567, 0xffffffe1)
    TEST_RR(46, sra, 0x00000000, 0x7fffffff, 0x0000001f)
    TEST_RR(47, sra, 0x00000000, 0x00000001, 0xffffffff)
    TEST_RR(48, slt, 0x00000000, 0x00000000, 0x00000000)
    TEST_RR(49, slt, 0x00000000, 0x00000001, 0x00000001)
    TEST_RR(50, slt, 0x00000001, 0x00000003, 0x00000007)
    TEST_RR(51, slt, 0x00000000, 0x00000007, 0x00000003)
    TEST_RR(52, slt, 0x00000000, 0x7fffffff, 0x00000001)
    TEST_RR(53, slt, 0x00000001, 0x80000000, 0xffffffff)
    TEST_RR(54, slt, 0x00000001, 0xffffffff, 0x00000001)
    TEST_RR(55, slt, 0x00000000, 0x12345678, 0x0f0f0f0f)
    TEST_RR(56, slt, 0x00000001, 0x80000000, 0x7fffffff)
    TEST_RR(57, slt, 0x00000001, 0xffff8000, 0x00007fff)
    TEST_RR(58, slt, 0x00000000, 0xdeadbeef, 0xcafef00d)
    TEST_RR(59, sltu, 0x00000000, 0x00000000, 0x00000000)
    TEST_RR(60, sltu, 0x00000000, 0x00000001, 0x00000001)
    TEST_RR(61, sltu, 0x00000001, 0x00000003, 0x00000007)
    TEST_RR(62, sltu, 0x00000000, 0x00000007, 0x00000003)
    TEST_RR(63, sltu, 0x00000000, 0x7fffffff, 0x00000001)
    TEST_RR(64, sltu, 0x00000001, 0x80000000, 0xffffffff)
    TEST_RR(65, sltu, 0x00000000, 0xffffffff, 0x00000001)
    TEST_RR(66, sltu, 0x00000000, 0x12345678, 0x0f0f0f0f)
    TEST_RR(67, sltu, 0x00000000, 0x80000000, 0x7fffffff)
    TEST_RR(68, sltu, 0x00000000, 0xffff8000, 0x00007fff)
    TEST_RR(69, sltu, 0x00000000, 0xdeadbeef, 0xcafef00d)
    TEST_RR(70, xor, 0x00000000, 0x00000000, 0x00000000)
    TEST_RR(71, xor, 0x00000000, 0x00000001, 0x00000001)
    TEST_RR(72, xor, 0x00000004, 0x00000003, 0x00000007)
    TEST_RR(73, xor, 0x00000004, 0x00000007, 0x00000003)
    TEST_RR(74, xor, 0x7ffffffe, 0x7fffffff, 0x00000001)
    TEST_RR(75, xor, 0x7fffffff, 0x80000000, 0xffffffff)
    TEST_RR(76, xor, 0xfffffffe, 0xffffffff, 0x00000001)
    TEST_RR(77, xor, 0x1d3b5977, 0x12345678, 0x0f0f0f0f)
    TEST_RR(78, xor, 0xffffffff, 0x80000000, 0x7fffffff)
    TEST_RR(79, xor, 0xffffffff, 0xffff8000, 0x00007fff)
    TEST_RR(80, xor, 0x14534ee2, 0xdeadbeef, 0xcafef00d)
    TEST_RR(81, or, 0x00000000, 0x00000000, 0x00000000)
    TEST_RR(82, or, 0x00000001, 0x00000001, 0x00000001)
    TEST_RR(83, or, 0x00000007, 0x00000003, 0x00000007)
    TEST_RR(84, or, 0x00000007, 0x00000007, 0x00000003)
    TEST_RR(85, or, 0x7fffffff, 0x7fffffff, 0x00000001)
    TEST_RR(86, or, 0xffffffff, 0x80000000, 0xffffffff)
    TEST_RR(87, or, 0xffffffff, 0xffffffff, 0x00000001)
    TEST_RR(88, or, 0x1f3f5f7f, 0x12345678, 0x0f0f0f0f)
    TEST_RR(89, or, 0xffffffff, 0x80000000, 0x7fffffff)
    TEST_RR(90, or, 0xffffffff, 0xffff8000, 0x00007fff)
    TEST_RR(91, or, 0xdefffeef, 0xdeadbeef, 0xcafef00d)
    TEST_RR(92, and, 0x00000000, 0x00000000, 0x00000000)
    TEST_RR(93, and, 0x00000001, 0x00000001, 0x00000001)
    TEST_RR(94, and, 0x00000003, 0x00000003, 0x00000007)
    TEST_RR(95, and, 0x00000003, 0x00000007, 0x00000003)
    TEST_RR(96, and, 0x00000001, 0x7fffffff, 0x00000001)
    TEST_RR(97, and, 0x80000000, 0x80000000, 0xffffffff)
    TEST_RR(98, and, 0x00000001, 0xffffffff, 0x00000001)
    TEST_RR(99, and, 0x02040608, 0x12345678, 0x0f0f0f0f)
    TEST_RR(100, and, 0x00000000, 0x80000000, 0x7fffffff)
    TEST_RR(101, and, 0x00000000, 0xffff8000, 0x00007fff)
    TEST_RR(102, and, 0xcaacb00d, 0xdeadbeef, 0xcafef00d)
    TEST_RI(103, addi, 0x00000000, 0x00000000, 0)
    TEST_RI(104, addi, 0x00000001, 0x00000000, 1)
    TEST_RI(105, addi, 0xffffffff, 0x00000000, -1)
    TEST_RI(106, addi, 0x000007ff, 0x00000000, 2047)
    TEST_RI(107, addi, 0xfffff800, 0x00000000, -2048)
    TEST_RI(108, addi, 0x00000555, 0x00000000, 1365)
    TEST_RI(109, addi, 0xfffffaaa, 0x00000000, -1366)
    TEST_RI(110, addi, 0x00000001, 0x00000001, 0)
    TEST_RI(111, addi, 0x00000002, 0x00000001, 1)
    TEST_RI(112, addi, 0x00000000, 0x00000001, -1)
    TEST_RI(113, addi, 0x00000800, 0x00000001, 2047)
    TEST_RI(114, addi, 0xfffff801, 0x00000001, -2048)
    TEST_RI(115, addi, 0x00000556, 0x00000001, 1365)
    TEST_RI(116, addi, 0xfffffaab, 0x00000001, -1366)
    TEST_RI(117, addi, 0xffffffff, 0xffffffff, 0)
    TEST_RI(118, addi, 0x00000000, 0xffffffff, 1)
    TEST_RI(119, addi, 0xfffffffe, 0xffffffff, -1)
    TEST_RI(120, addi, 0x000007fe, 0xffffffff, 2047)
    TEST_RI(121, addi, 0xfffff7ff, 0xffffffff, -2048)
    TEST_RI(122, addi, 0x00000554, 0xffffffff, 1365)
    TEST_RI(123, addi, 0xfffffaa9, 0xffffffff, -1366)
    TEST_RI(124, addi, 0x7fffffff, 0x7fffffff, 0)
    TEST_RI(125, addi, 0x80000000, 0x7fffffff, 1)
    TEST_RI(126, addi, 0x7ffffffe, 0x7fffffff, -1)
    TEST_RI(127, addi, 0x800007fe, 0x7fffffff, 2047)
    TEST_RI(128, addi, 0x7ffff7ff, 0x7fffffff, -2048)
    TEST_RI(129, addi, 0x80000554, 0x7fffffff, 1365)
    TEST_RI(130, addi, 0x7ffffaa9, 0x7fffffff, -1366)
    TEST_RI(131, addi, 0x80000000, 0x80000000, 0)
    TEST_RI(132, addi, 0x80000001, 0x80000000, 1)
    TEST_RI(133, addi, 0x7fffffff, 0x80000000, -1)
    TEST_RI(134, addi, 0x800007ff, 0x80000000, 2047)
    TEST_RI(135, addi, 0x7ffff800, 0x80000000, -2048)
    TEST_RI(136, addi, 0x80000555, 0x80000000, 1365)
    TEST_RI(137, addi, 0x7ffffaaa, 0x80000000, -1366)
    TEST_RI(138, addi, 0x12345678, 0x12345678, 0)
    TEST_RI(139, addi, 0x12345679, 0x12345678, 1)
    TEST_RI(140, addi, 0x12345677, 0x12345678, -1)
    TEST_RI(141, addi, 0x12345e77, 0x12345678, 2047)
    TEST_RI(142, addi, 0x12344e78, 0x12345678, -2048)
    TEST_RI(143, addi, 0x12345bcd, 0x12345678, 1365)
    TEST_RI(144, addi, 0x12345122, 0x12345678, -1366)
    TEST_RI(145, slti, 0x00000000, 0x00000000, 0)
    TEST_RI(146, slti, 0x00000001, 0x00000000, 1)
    TEST_RI(147, slti, 0x00000000, 0x00000000, -1)
    TEST_RI(148, slti, 0x00000001, 0x00000000, 2047)
    TEST_RI(149, slti, 0x00000000, 0x00000000, -2048)
    TEST_RI(150, slti, 0x00000001, 0x00000000, 1365)
    TEST_RI(151, slti, 0x00000000, 0x00000000, -1366)
    TEST_RI(152, slti, 0x00000000, 0x00000001, 0)
    TEST_RI(153, slti, 0x00000000, 0x00000001, 1)
    TEST_RI(154, slti, 0x00000000, 0x00000001, -1)
    TEST_RI(155, slti, 0x00000001, 0x00000001, 2047)
    TEST_RI(156, slti, 0x00000000, 0x00000001, -2048)
    TEST_RI(157, slti, 0x00000001, 0x00000001, 1365)
    TEST_RI(158, slti, 0x00000000, 0x00000001, -1366)
    TEST_RI(159, slti, 0x00000001, 0xffffffff, 0)
    TEST_RI(160, slti, 0x00000001, 0xffffffff, 1)
    TEST_RI(161, slti, 0x00000000, 0xffffffff, -1)
    TEST_RI(162, slti, 0x00000001, 0xffffffff, 2047)
    TEST_RI(163, slti, 0x00000000, 0xffffffff, -2048)
    TEST_RI(164, slti, 0x00000001, 0xffffffff, 1365)
    TEST_RI(165, slti, 0x00000000, 0xffffffff, -1366)
    TEST_RI(166, slti, 0x00000000, 0x7fffffff, 0)
    TEST_RI(167, slti, 0x00000000, 0x7fffffff, 1)
    TEST_RI(168, slti, 0x00000000, 0x7fffffff, -1)
    TEST_RI(169, slti, 0x00000000, 0x7fffffff, 2047)
    TEST_RI(170, slti, 0x00000000, 0x7fffffff, -2048)
    TEST_RI(171, slti, 0x00000000, 0x7fffffff, 1365)
    TEST_RI(172, slti, 0x00000000, 0x7fffffff, -1366)
    TEST_RI(173, slti, 0x00000001, 0x80000000, 0)
    TEST_RI(174, slti, 0x00000001, 0x80000000, 1)
    TEST_RI(175, slti, 0x00000001, 0x80000000, -1)
    TEST_RI(176, slti, 0x00000001, 0x80000000, 2047)
    TEST_RI(177, slti, 0x00000001, 0x80000000, -2048)
    TEST_RI(178, slti, 0x00000001, 0x80000000, 1365)
    TEST_RI(179, slti, 0x00000001, 0x80000000, -1366)
    TEST_RI(180, slti, 0x00000000, 0x12345678, 0)
    TEST_RI(181, slti, 0x00000000, 0x12345678, 1)
    TEST_RI(182, slti, 0x00000000, 0x12345678, -1)
    TEST_RI(183, slti, 0x00000000, 0x12345678, 2047)
    TEST_RI(184, slti, 0x00000000, 0x12345678, -2048)
    TEST_RI(185, slti, 0x00000000, 0x12345678, 1365)
    TEST_RI(186, slti, 0x00000000, 0x12345678, -1366)
    TEST_RI(187, sltiu, 0x00000000, 0x00000000, 0)
    TEST_RI(188, sltiu, 0x00000001, 0x00000000, 1)
    TEST_RI(189, sltiu, 0x00000001, 0x00000000, -1)
    TEST_RI(190, sltiu, 0x00000001, 0x00000000, 2047)
    TEST_RI(191, sltiu, 0x00000001, 0x00000000, -2048)
    TEST_RI(192, sltiu, 0x00000001, 0x00000000, 1365)
    TEST_RI(193, sltiu, 0x00000001, 0x00000000, -1366)
    TEST_RI(194, sltiu, 0x00000000, 0x00000001, 0)
    TEST_RI(195, sltiu, 0x00000000, 0x00000001, 1)
    TEST_RI(196, sltiu, 0x00000001, 0x00000001, -1)
    TEST_RI(197, sltiu, 0x00000001, 0x00000001, 2047)
    TEST_RI(198, sltiu, 0x00000001, 0x00000001, -2048)
    TEST_RI(199, sltiu, 0x00000001, 0x00000001, 1365)
    TEST_RI(200, sltiu, 0x00000001, 0x00000001, -1366)
    TEST_RI(201, sltiu, 0x00000000, 0xffffffff, 0)
    TEST_RI(202, sltiu, 0x00000000, 0xffffffff, 1)
    TEST_RI(203, sltiu, 0x00000000, 0xffffffff, -1)
    TEST_RI(204, sltiu, 0x00000000, 0xffffffff, 2047)
    TEST_RI(205, sltiu, 0x00000000, 0xffffffff, -2048)
    TEST_RI(206, sltiu, 0x00000000, 0xffffffff, 1365)
    TEST_RI(207, sltiu, 0x00000000, 0xffffffff, -1366)
    TEST_RI(208, sltiu, 0x00000000, 0x7fffffff, 0)
    TEST_RI(209, sltiu, 0x00000000, 0x7fffffff, 1)
    TEST_RI(210, sltiu, 0x00000001, 0x7fffffff, -1)
    TEST_RI(211, sltiu, 0x00000000, 0x7fffffff, 2047)
    TEST_RI(212, sltiu, 0x00000001, 0x7fffffff, -2048)
    TEST_RI(213, sltiu, 0x00000000, 0x7fffffff, 1365)
    TEST_RI(214, sltiu, 0x00000001, 0x7fffffff, -1366)
    TEST_RI(215, sltiu, 0x00000000, 0x80000000, 0)
    TEST_RI(216, sltiu, 0x00000000, 0x80000000, 1)
    TEST_RI(217, sltiu, 0x00000001, 0x80000000, -1)
    TEST_RI(218, sltiu, 0x00000000, 0x80000000, 2047)
    TEST_RI(219, sltiu, 0x00000001, 0x80000000, -2048)
    TEST_RI(220, sltiu, 0x00000000, 0x80000000, 1365)
    TEST_RI(221, sltiu, 0x00000001, 0x80000000, -1366)
    TEST_RI(222, sltiu, 0x00000000, 0x12345678, 0)
    TEST_RI(223, sltiu, 0x00000000, 0x12345678, 1)
    TEST_RI(224, sltiu, 0x00000001, 0x12345678, -1)
    TEST_RI(225, sltiu, 0x00000000, 0x12345678, 2047)
    TEST_RI(226, sltiu, 0x00000001, 0x12345678, -2048)
    TEST_RI(227, sltiu, 0x00000000, 0x12345678, 1365)
    TEST_RI(228, sltiu, 0x00000001, 0x12345678, -1366)
    TEST_RI(229, xori, 0x00000000, 0x00000000, 0)
    TEST_RI(230, xori, 0x00000001, 0x00000000, 1)
    TEST_RI(231, xori, 0xffffffff, 0x00000000, -1)
    TEST_RI(232, xori, 0x000007ff, 0x00000000, 2047)
    TEST_RI(233, xori, 0xfffff800, 0x00000000, -2048)
    TEST_RI(234, xori, 0x00000555, 0x00000000, 1365)
    TEST_RI(235, xori, 0xfffffaaa, 0x00000000, -1366)
    TEST_RI(236, xori, 0x00000001, 0x00000001, 0)
    TEST_RI(237, xori, 0x00000000, 0x00000001, 1)
    TEST_RI(238, xori, 0xfffffffe, 0x00000001, -1)
    TEST_RI(239, xori, 0x000007fe, 0x00000001, 2047)
    TEST_RI(240, xori, 0xfffff801, 0x00000001, -2048)
    TEST_RI(241, xori, 0x00000554, 0x00000001, 1365)
    TEST_RI(242, xori, 0xfffffaab, 0x00000001, -1366)
    TEST_RI(243, xori, 0xffffffff, 0xffffffff, 0)
    TEST_RI(244, xori, 0xfffffffe, 0xffffffff, 1)
    TEST_RI(245, xori, 0x00000000, 0xffffffff, -1)
    TEST_RI(246, xori, 0xfffff800, 0xffffffff, 2047)
    TEST_RI(247, xori, 0x000007ff, 0xffffffff, -2048)
    TEST_RI(248, xori, 0xfffffaaa, 0xffffffff, 1365)
    TEST_RI(249, xori, 0x00000555, 0xffffffff, -1366)
    TEST_RI(250, xori, 0x7fffffff, 0x7fffffff, 0)
    TEST_RI(251, xori, 0x7ffffffe, 0x7fffffff, 1)
    TEST_RI(252, xori, 0x80000000, 0x7fffffff, -1)
    TEST_RI(253, xori, 0x7ffff800, 0x7fffffff, 2047)
    TEST_RI(254, xori, 0x800007ff, 0x7fffffff, -2048)
    TEST_RI(255, xori, 0x7ffffaaa, 0x7fffffff, 1365)
    TEST_RI(256, xori, 0x80000555, 0x7fffffff, -1366)
    TEST_RI(257, xori, 0x80000000, 0x80000000, 0)
    TEST_RI(258, xori, 0x80000001, 0x80000000, 1)
    TEST_RI(259, xori, 0x7fffffff, 0x80000000, -1)
    TEST_RI(260, xori, 0x800007ff, 0x80000000, 2047)
    TEST_RI(261, xori, 0x7ffff800, 0x80000000, -2048)
    TEST_RI(262, xori, 0x80000555, 0x80000000, 1365)
    TEST_RI(263, xori, 0x7ffffaaa, 0x80000000, -1366)
    TEST_RI(264, xori, 0x12345678, 0x12345678, 0)
    TEST_RI(265, xori, 0x12345679, 0x12345678, 1)
    TEST_RI(266, xori, 0xedcba987, 0x12345678, -1)
    TEST_RI(267, xori, 0x12345187, 0x12345678, 2047)
    TEST_RI(268, xori, 0xedcbae78, 0x12345678, -2048)
    TEST_RI(269, xori, 0x1234532d, 0x12345678, 1365)
    TEST_RI(270, xori, 0xedcbacd2, 0x12345678, -1366)
    TEST_RI(271, ori, 0x00000000, 0x00000000, 0)
    TEST_RI(272, ori, 0x00000001, 0x00000000, 1)
    TEST_RI(273, ori, 0xffffffff, 0x00000000, -1)
    TEST_RI(274, ori, 0x000007ff, 0x00000000, 2047)
    TEST_RI(275, ori, 0xfffff800, 0x00000000, -2048)
    TEST_RI(276, ori, 0x00000555, 0x00000000, 1365)
    TEST_RI(277, ori, 0xfffffaaa, 0x00000000, -1366)
    TEST_RI(278, ori, 0x00000001, 0x00000001, 0)
    TEST_RI(279, ori, 0x00000001, 0x00000001, 1)
    TEST_RI(280, ori, 0xffffffff, 0x00000001, -1)
    TEST_RI(281, ori, 0x000007ff, 0x00000001, 2047)
    TEST_RI(282, ori, 0xfffff801, 0x00000001, -2048)
    TEST_RI(283, ori, 0x00000555, 0x00000001, 1365)
    TEST_RI(284, ori, 0xfffffaab, 0x00000001, -1366)
    TEST_RI(285, ori, 0xffffffff, 0xffffffff, 0)
    TEST_RI(286, ori, 0xffffffff, 0xffffffff, 1)
    TEST_RI(287, ori, 0xffffffff, 0xffffffff, -1)
    TEST_RI(288, ori, 0xffffffff, 0xffffffff, 2047)
    TEST_RI(289, ori, 0xffffffff, 0xffffffff, -2048)
    TEST_RI(290, ori, 0xffffffff, 0xffffffff, 1365)
    TEST_RI(291, ori, 0xffffffff, 0xffffffff, -1366)
    TEST_RI(292, ori, 0x7fffffff, 0x7fffffff, 0)
    TEST_RI(293, ori, 0x7fffffff, 0x7fffffff, 1)
    TEST_RI(294, ori, 0xffffffff, 0x7fffffff, -1)
    TEST_RI(295, ori, 0x7fffffff, 0x7fffffff, 2047)
    TEST_RI(296, ori, 0xffffffff, 0x7fffffff, -2048)
    TEST_RI(297, ori, 0x7fffffff, 0x7fffffff, 1365)
    TEST_RI(298, ori, 0xffffffff, 0x7fffffff, -1366)
    TEST_RI(299, ori, 0x80000000, 0x80000000, 0)
    TEST_RI(300, ori, 0x80000001, 0x80000000, 1)
    TEST_RI(301, ori, 0xffffffff, 0x80000000, -1)
    TEST_RI(302, ori, 0x800007ff, 0x80000000, 2047)
    TEST_RI(303, ori, 0xfffff800, 0x80000000, -2048)
    TEST_RI(304, ori, 0x80000555, 0x80000000, 1365)
    TEST_RI(305, ori, 0xfffffaaa, 0x80000000, -1366)
    TEST_RI(306, ori, 0x12345678, 0x12345678, 0)
    TEST_RI(307, ori, 0x12345679, 0x12345678, 1)
    TEST_RI(308, ori, 0xffffffff, 0x12345678, -1)
    TEST_RI(309, ori, 0x123457ff, 0x12345678, 2047)
    TEST_RI(310, ori, 0xfffffe78, 0x12345678, -2048)
    TEST_RI(311, ori, 0x1234577d, 0x12345678, 1365)
    TEST_RI(312, ori, 0xfffffefa, 0x12345678, -1366)
    TEST_RI(313, andi, 0x00000000, 0x00000000, 0)
    TEST_RI(314, andi, 0x00000000, 0x00000000, 1)
    TEST_RI(315, andi, 0x00000000, 0x00000000, -1)
    TEST_RI(316, andi, 0x00000000, 0x00000000, 2047)
    TEST_RI(317, andi, 0x00000000, 0x00000000, -2048)
    TEST_RI(318, andi, 0x00000000, 0x00000000, 1365)
    TEST_RI(319, andi, 0x00000000, 0x00000000, -1366)
    TEST_RI(320, andi, 0x00000000, 0x00000001, 0)
    TEST_RI(321, andi, 0x00000001, 0x00000001, 1)
    TEST_RI(322, andi, 0x00000001, 0x00000001, -1)
    TEST_RI(323, andi, 0x00000001, 0x00000001, 2047)
    TEST_RI(324, andi, 0x00000000, 0x00000001, -2048)
    TEST_RI(325, andi, 0x00000001, 0x00000001, 1365)
    TEST_RI(326, andi, 0x00000000, 0x00000001, -1366)
    TEST_RI(327, andi, 0x00000000, 0xffffffff, 0)
    TEST_RI(328, andi, 0x00000001, 0xffffffff, 1)
    TEST_RI(329, andi, 0xffffffff, 0xffffffff, -1)
    TEST_RI(330, andi, 0x000007ff, 0xffffffff, 2047)
    TEST_RI(331, andi, 0xfffff800, 0xffffffff, -2048)
    TEST_RI(332, andi, 0x00000555, 0xffffffff, 1365)
    TEST_RI(333, andi, 0xfffffaaa, 0xffffffff, -1366)
    TEST_RI(334, andi, 0x00000000, 0x7fffffff, 0)
    TEST_RI(335, andi, 0x00000001, 0x7fffffff, 1)
    TEST_RI(336, andi, 0x7fffffff, 0x7fffffff, -1)
    TEST_RI(337, andi, 0x000007ff, 0x7fffffff, 2047)
    TEST_RI(338, andi, 0x7ffff800, 0x7fffffff, -2048)
    TEST_RI(339, andi, 0x00000555, 0x7fffffff, 1365)
    TEST_RI(340, andi, 0x7ffffaaa, 0x7fffffff, -1366)
    TEST_RI(341, andi, 0x00000000, 0x80000000, 0)
    TEST_RI(342, andi, 0x00000000, 0x80000000, 1)
    TEST_RI(343, andi, 0x80000000, 0x80000000, -1)
    TEST_RI(344, andi, 0x00000000, 0x80000000, 2047)
    TEST_RI(345, andi, 0x80000000, 0x80000000, -2048)
    TEST_RI(346, andi, 0x00000000, 0x80000000, 1365)
    TEST_RI(347, andi, 0x80000000, 0x80000000, -1366)
    TEST_RI(348, andi, 0x00000000, 0x12345678, 0)
    TEST_RI(349, andi, 0x00000000, 0x12345678, 1)
    TEST_RI(350, andi, 0x12345678, 0x12345678, -1)
    TEST_RI(351, andi, 0x00000678, 0x12345678, 2047)
    TEST_RI(352, andi, 0x12345000, 0x12345678, -2048)
    TEST_RI(353, andi, 0x00000450, 0x12345678, 1365)
    TEST_RI(354, andi, 0x12345228, 0x12345678, -1366)
    TEST_RI(355, slli, 0x80000001, 0x80000001, 0)
    TEST_RI(356, slli, 0x00000002, 0x80000001, 1)
    TEST_RI(357, slli, 0x00000080, 0x80000001, 7)
    TEST_RI(358, slli, 0x00020000, 0x80000001, 17)
    TEST_RI(359, slli, 0x80000000, 0x80000001, 31)
    TEST_RI(360, slli, 0x81234567, 0x81234567, 0)
    TEST_RI(361, slli, 0x02468ace, 0x81234567, 1)
    TEST_RI(362, slli, 0x91a2b380, 0x81234567, 7)
    TEST_RI(363, slli, 0x8ace0000, 0x81234567, 17)
    TEST_RI(364, slli, 0x80000000, 0x81234567, 31)
    TEST_RI(365, slli, 0x7fffffff, 0x7fffffff, 0)
    TEST_RI(366, slli, 0xfffffffe, 0x7fffffff, 1)
    TEST_RI(367, slli, 0xffffff80, 0x7fffffff, 7)
    TEST_RI(368, slli, 0xfffe0000, 0x7fffffff, 17)
    TEST_RI(369, slli, 0x80000000, 0x7fffffff, 31)
    TEST_RI(370, srli, 0x80000001, 0x80000001, 0)
    TEST_RI(371, srli, 0x40000000, 0x80000001, 1)
    TEST_RI(372, srli, 0x01000000, 0x80000001, 7)
    TEST_RI(373, srli, 0x00004000, 0x80000001, 17)
    TEST_RI(374, srli, 0x00000001, 0x80000001, 31)
    TEST_RI(375, srli, 0x81234567, 0x81234567, 0)
    TEST_RI(376, srli, 0x4091a2b3, 0x81234567, 1)
    TEST_RI(377, srli, 0x0102468a, 0x81234567, 7)
    TEST_RI(378, srli, 0x00004091, 0x81234567, 17)
    TEST_RI(379, srli, 0x00000001, 0x81234567, 31)
    TEST_RI(380, srli, 0x7fffffff, 0x7fffffff, 0)
    TEST_RI(381, srli, 0x3fffffff, 0x7fffffff, 1)
    TEST_RI(382, srli, 0x00ffffff, 0x7fffffff, 7)
    TEST_RI(383, srli, 0x00003fff, 0x7fffffff, 17)
    TEST_RI(384, srli, 0x00000000, 0x7fffffff, 31)
    TEST_RI(385, srai, 0x80000001, 0x80000001, 0)
    TEST_RI(386, srai, 0xc0000000, 0x80000001, 1)
    TEST_RI(387, srai, 0xff000000, 0x80000001, 7)
    TEST_RI(388, srai, 0xffffc000, 0x80000001, 17)
    TEST_RI(389, srai, 0xffffffff, 0x80000001, 31)
    TEST_RI(390, srai, 0x81234567, 0x81234567, 0)
    TEST_RI(391, srai, 0xc091a2b3, 0x81234567, 1)
    TEST_RI(392, srai, 0xff02468a, 0x81234567, 7)
    TEST_RI(393, srai, 0xffffc091, 0x81234567, 17)
    TEST_RI(394, srai, 0xffffffff, 0x81234567, 31)
    TEST_RI(395, srai, 0x7fffffff, 0x7fffffff, 0)
    TEST_RI(396, srai, 0x3fffffff, 0x7fffffff, 1)
    TEST_RI(397, srai, 0x00ffffff, 0x7fffffff, 7)
    TEST_RI(398, srai, 0x00003fff, 0x7fffffff, 17)
    TEST_RI(399, srai, 0x00000000, 0x7fffffff, 31)
    TEST_U(400, lui, 0x00000000, 0x0)
    TEST_U(401, lui, 0x00001000, 0x1)
    TEST_U(402, lui, 0x80000000, 0x80000)
    TEST_U(403, lui, 0xfffff000, 0xfffff)
    TEST_U(404, lui, 0x12345000, 0x12345)
    TEST_BR_TAKEN(405, beq, 0x00000001, 0x00000001)
    TEST_BR_NOT_TAKEN(406, beq, 0x00000001, 0x00000002)
    TEST_BR_NOT_TAKEN(407, beq, 0x00000002, 0x00000001)
    TEST_BR_NOT_TAKEN(408, beq, 0xffffffff, 0x00000001)
    TEST_BR_NOT_TAKEN(409, beq, 0x00000001, 0xffffffff)
    TEST_BR_NOT_TAKEN(410, beq, 0x80000000, 0x7fffffff)
    TEST_BR_NOT_TAKEN(411, beq, 0x7fffffff, 0x80000000)
    TEST_BR_NOT_TAKEN(412, beq, 0x00000000, 0xffffffff)
    TEST_BR_NOT_TAKEN(413, bne, 0x00000001, 0x00000001)
    TEST_BR_TAKEN(414, bne, 0x00000001, 0x00000002)
    TEST_BR_TAKEN(415, bne, 0x00000002, 0x00000001)
    TEST_BR_TAKEN(416, bne, 0xffffffff, 0x00000001)
    TEST_BR_TAKEN(417, bne, 0x00000001, 0xffffffff)
    TEST_BR_TAKEN(418, bne, 0x80000000, 0x7fffffff)
    TEST_BR_TAKEN(419, bne, 0x7fffffff, 0x80000000)
    TEST_BR_TAKEN(420, bne, 0x00000000, 0xffffffff)
    TEST_BR_NOT_TAKEN(421, blt, 0x00000001, 0x00000001)
    TEST_BR_TAKEN(422, blt, 0x00000001, 0x00000002)
    TEST_BR_NOT_TAKEN(423, blt, 0x00000002, 0x00000001)
    TEST_BR_TAKEN(424, blt, 0xffffffff, 0x00000001)
    TEST_BR_NOT_TAKEN(425, blt, 0x00000001, 0xffffffff)
    TEST_BR_TAKEN(426, blt, 0x80000000, 0x7fffffff)
    TEST_BR_NOT_TAKEN(427, blt, 0x7fffffff, 0x80000000)
    TEST_BR_NOT_TAKEN(428, blt, 0x00000000, 0xffffffff)
    TEST_BR_TAKEN(429, bge, 0x00000001, 0x00000001)
    TEST_BR_NOT_TAKEN(430, bge, 0x00000001, 0x00000002)
    TEST_BR_TAKEN(431, bge, 0x00000002, 0x00000001)
    TEST_BR_NOT_TAKEN(432, bge, 0xffffffff, 0x00000001)
    TEST_BR_TAKEN(433, bge, 0x00000001, 0xffffffff)
    TEST_BR_NOT_TAKEN(434, bge, 0x80000000, 0x7fffffff)
    TEST_BR_TAKEN(435, bge, 0x7fffffff, 0x80000000)
    TEST_BR_TAKEN(436, bge, 0x00000000, 0xffffffff)
    TEST_BR_NOT_TAKEN(437, bltu, 0x00000001, 0x00000001)
    TEST_BR_TAKEN(438, bltu, 0x00000001, 0x00000002)
    TEST_BR_NOT_TAKEN(439, bltu, 0x00000002, 0x00000001)
    TEST_BR_NOT_TAKEN(440, bltu, 0xffffffff, 0x00000001)
    TEST_BR_TAKEN(441, bltu, 0x00000001, 0xffffffff)
    TEST_BR_NOT_TAKEN(442, bltu, 0x80000000, 0x7fffffff)
    TEST_BR_TAKEN(443, bltu, 0x7fffffff, 0x80000000)
    TEST_BR_TAKEN(444, bltu, 0x00000000, 0xffffffff)
    TEST_BR_TAKEN(445, bgeu, 0x00000001, 0x00000001)
    TEST_BR_NOT_TAKEN(446, bgeu, 0x00000001, 0x00000002)
    TEST_BR_TAKEN(447, bgeu, 0x00000002, 0x00000001)
    TEST_BR_TAKEN(448, bgeu, 0xffffffff, 0x00000001)
    TEST_BR_NOT_TAKEN(449, bgeu, 0x00000001, 0xffffffff)
    TEST_BR_TAKEN(450, bgeu, 0x80000000, 0x7fffffff)
    TEST_BR_NOT_TAKEN(451, bgeu, 0x7fffffff, 0x80000000)
    TEST_BR_NOT_TAKEN(452, bgeu, 0x00000000, 0xffffffff)
    TEST_LD(453, lb, 0xffffffff, 0, tdat)
    TEST_LD(454, lb, 0x00000000, 1, tdat)
    TEST_LD(455, lb, 0xffffffff, 2, tdat)
    TEST_LD(456, lb, 0x00000000, 3, tdat)
    TEST_LD(457, lb, 0x00000000, 4, tdat)
    TEST_LD(458, lb, 0xffffffff, 5, tdat)
    TEST_LD(459, lb, 0x00000000, 6, tdat)
    TEST_LD(460, lb, 0xffffffff, 7, tdat)
    TEST_LD(461, lb, 0xfffffff0, 8, tdat)
    TEST_LD(462, lb, 0x0000000f, 9, tdat)
    TEST_LD(463, lb, 0xfffffff0, 10, tdat)
    TEST_LD(464, lb, 0x0000000f, 11, tdat)
    TEST_LD(465, lb, 0x0000000f, 12, tdat)
    TEST_LD(466, lb, 0xfffffff0, 13, tdat)
    TEST_LD(467, lb, 0x0000000f, 14, tdat)
    TEST_LD(468, lb, 0xfffffff0, 15, tdat)
    TEST_LD(469, lb, 0x0000000f, -4, tdat_end)
    TEST_LD(470, lbu, 0x000000ff, 0, tdat)
    TEST_LD(471, lbu, 0x00000000, 1, tdat)
    TEST_LD(472, lbu, 0x000000ff, 2, tdat)
    TEST_LD(473, lbu, 0x00000000, 3, tdat)
    TEST_LD(474, lbu, 0x00000000, 4, tdat)
    TEST_LD(475, lbu, 0x000000ff, 5, tdat)
    TEST_LD(476, lbu, 0x00000000, 6, tdat)
    TEST_LD(477, lbu, 0x000000ff, 7, tdat)
    TEST_LD(478, lbu, 0x000000f0, 8, tdat)
    TEST_LD(479, lbu, 0x0000000f, 9, tdat)
    TEST_LD(480, lbu, 0x000000f0, 10, tdat)
    TEST_LD(481, lbu, 0x0000000f, 11, tdat)
    TEST_LD(482, lbu, 0x0000000f, 12, tdat)
    TEST_LD(483, lbu, 0x000000f0, 13, tdat)
    TEST_LD(484, lbu, 0x0000000f, 14, tdat)
    TEST_LD(485, lbu, 0x000000f0, 15, tdat)
    TEST_LD(486, lbu, 0x0000000f, -4, tdat_end)
    TEST_LD(487, lh, 0x000000ff, 0, tdat)
    TEST_LD(488, lh, 0x000000ff, 2, tdat)
    TEST_LD(489, lh, 0xffffff00, 4, tdat)
    TEST_LD(490, lh, 0xffffff00, 6, tdat)
    TEST_LD(491, lh, 0x00000ff0, 8, tdat)
    TEST_LD(492, lh, 0x00000ff0, 10, tdat)
    TEST_LD(493, lh, 0xfffff00f, 12, tdat)
    TEST_LD(494, lh, 0xfffff00f, 14, tdat)
    TEST_LD(495, lh, 0xfffff00f, -4, tdat_end)
    TEST_LD(496, lhu, 0x000000ff, 0, tdat)
    TEST_LD(497, lhu, 0x000000ff, 2, tdat)
    TEST_LD(498, lhu, 0x0000ff00, 4, tdat)
    TEST_LD(499, lhu, 0x0000ff00, 6, tdat)
    TEST_LD(500, lhu, 0x00000ff0, 8, tdat)
    TEST_LD(501, lhu, 0x00000ff0, 10, tdat)
    TEST_LD(502, lhu, 0x0000f00f, 12, tdat)
    TEST_LD(503, lhu, 0x0000f00f, 14, tdat)
    TEST_LD(504, lhu, 0x0000f00f, -4, tdat_end)
    TEST_LD(505, lw, 0x00ff00ff, 0, tdat)
    TEST_LD(506, lw, 0xff00ff00, 4, tdat)
    TEST_LD(507, lw, 0x0ff00ff0, 8, tdat)
    TEST_LD(508, lw, 0xf00ff00f, 12, tdat)
    TEST_LD(509, lw, 0xf00ff00f, -4, tdat_end)
    TEST_ST(510, sb, 0xdeadbeef, 0x9abcde5a, 0, sdat, 0xdeadbe5a)
    TEST_ST(511, sb, 0xdeadbeef, 0x9abcde5a, 1, sdat, 0xdead5aef)
    TEST_ST(512, sb, 0xdeadbeef, 0x9abcde5a, 2, sdat, 0xde5abeef)
    TEST_ST(513, sb, 0xdeadbeef, 0x9abcde5a, 3, sdat, 0x5aadbeef)
    TEST_ST(514, sh, 0xdeadbeef, 0x9abcde5a, 0, sdat, 0xdeadde5a)
    TEST_ST(515, sh, 0xdeadbeef, 0x9abcde5a, 2, sdat, 0xde5abeef)
    TEST_ST(516, sw, 0xdeadbeef, 0x9abcde5a, 0, sdat, 0x9abcde5a)

    // ---- x0 luôn bằng 0 -------------------------------------------
    li   TESTNUM, 600
    li   x1, 0x55
    addi x0, x1, 1
    bnez x0, fail
    add  x14, x0, x0
    bnez x14, fail
    li   TESTNUM, 601
    la   x1, tdat
    lw   x0, 4(x1)
    bnez x0, fail
    li   TESTNUM, 602
    lui  x0, 0x12345
    jal  x0, 1f                 // địa chỉ trả về ghi vào x0 bị bỏ
1:  bnez x0, fail

    // ---- AUIPC ---------------------------------------------------------------
    li   TESTNUM, 610
    jal  x8, 1f                 // x8 = địa chỉ lệnh auipc bên dưới
1:  auipc x14, 0
    bne  x14, x8, fail
    li   TESTNUM, 611
    jal  x8, 1f
1:  auipc x14, 0x12345
    li   x7, 0x12345000
    add  x7, x7, x8
    bne  x14, x7, fail
    li   TESTNUM, 612
    jal  x8, 1f
1:  auipc x14, 0xfffff          // -4096
    addi x7, x8, -2048
    addi x7, x7, -2048
    bne  x14, x7, fail

    // ---- JAL -----------------------------------------------------------------
    li   TESTNUM, 620
    la   x7, 2f
    jal  x1, 3f
2:  j    fail
3:  bne  x1, x7, fail
    li   TESTNUM, 621           // JAL nhảy lùi
    j    5f
4:  j    6f
5:  jal  x1, 4b
    j    fail
6:  la   x7, 5b + 4
    bne  x1, x7, fail

    // ---- JALR ----------------------------------------------------------------
    li   TESTNUM, 630
    la   x2, 3f
    jalr x1, 0(x2)
2:  j    fail
3:  la   x7, 2b
    bne  x1, x7, fail
    li   TESTNUM, 631           // offset dương
    la   x2, 3f - 8
    jalr x1, 8(x2)
    j    fail
3:  li   TESTNUM, 632           // offset âm
    la   x2, 3f + 12
    jalr x1, -12(x2)
    j    fail
3:  li   TESTNUM, 633           // bit 0 của đích bị xoá
    la   x2, 3f
    addi x2, x2, 1
    jalr x1, 0(x2)
    j    fail
3:  li   TESTNUM, 634           // rd == rs1: đích dùng giá trị cũ
    la   x2, 3f
    jalr x2, 0(x2)
2:  j    fail
3:  la   x7, 2b
    bne  x2, x7, fail
    li   TESTNUM, 635           // rd = x0
    la   x2, 3f
    jalr x0, 0(x2)
    j    fail
3:

    // ---- FENCE là NOP --------------------------------------------------------
    li   TESTNUM, 636
    li   x14, 7
    fence
    fence rw, rw
    addi x14, x14, 1
    li   x7, 8
    bne  x14, x7, fail

    // ---- Truy cập dữ liệu vào IMEM (cổng dùng chung) -------------------------------------
    li   TESTNUM, 640
    la   x1, _start
    lw   x14, 0(x1)
    li   x7, 0x00000013
    bne  x14, x7, fail
    li   TESTNUM, 641
    lbu  x14, 0(x1)
    li   x7, 0x13
    bne  x14, x7, fail
    li   TESTNUM, 642
    la   x1, imem_scratch
    li   x2, 0xa5a5f00d
    sw   x2, 0(x1)
    lw   x14, 0(x1)
    bne  x14, x2, fail
    li   TESTNUM, 643
    li   x2, 0x77
    sb   x2, 3(x1)
    lw   x14, 0(x1)
    li   x7, 0x77a5f00d
    bne  x14, x7, fail

    // ---- Vòng lặp nhánh lùi: tổng 1..10 -------------------------------------
    li   TESTNUM, 650
    li   x14, 0
    li   x1, 10
1:  add  x14, x14, x1
    addi x1, x1, -1
    bnez x1, 1b
    li   x7, 55
    bne  x14, x7, fail

    TEST_PASS
    TEST_FAIL

    // Không bao giờ thực thi: dữ liệu do test 642 ghi qua bus
    .align 2
imem_scratch:
    .word 0

TEST_DATA_BEGIN
    .align 4
tdat:
    .word 0x00ff00ff, 0xff00ff00, 0x0ff00ff0, 0xf00ff00f
tdat_end:
sdat:
    .word 0
