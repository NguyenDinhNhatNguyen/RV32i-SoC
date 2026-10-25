// boot_rom_init.vh - boot ROM contents, included inside the case statement of boot_rom.v.
// Each line: <8-bit word index>: word = <instruction>. Unlisted words read 0 (illegal).
// Base version: jump to the start of IMEM. The UART bootloader version (Nhan, P8) will
// regenerate this file with a script and keep the same format.
//
// 0x0001_0000  jalr x0, 0(x0)     PC <- 0x0000_0000
8'h00: word = 32'h0000_0067;
