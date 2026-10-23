// boot_rom_init.vh - nội dung boot ROM, include vào giữa câu lệnh case của boot_rom.v.
// Mỗi dòng: <chỉ số word 8 bit>: word = <mã lệnh>. Word không liệt kê đọc ra 0 (illegal).
// Bản base: nhảy về đầu IMEM. Bản bootloader UART (Nhân, P8) sẽ sinh lại file này
// bằng script, giữ nguyên định dạng.
//
// 0x0001_0000  jalr x0, 0(x0)     PC <- 0x0000_0000
8'h00: word = 32'h0000_0067;
