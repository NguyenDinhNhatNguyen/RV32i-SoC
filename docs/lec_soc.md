# LEC của `soc_top`: Conformal, RTL ↔ netlist Genus

Tài liệu này mô tả flow kiểm tra tương đương logic (LEC) cho `soc_top` bằng Cadence Conformal 24.1, cách chạy, cách đọc kết quả và kết quả của lần chạy thử đầu tiên (LEC-01). Flow chạy trên server trường (asiclab), nơi có Conformal. Môi trường Docker ở nhà không có Cadence.

| File | Vai trò |
| --- | --- |
| `lec/soc_rtl2gate.do.in` | Mẫu dofile. Sửa ở đây, không sửa file sinh ra |
| `lec/run_lec_soc.sh` | Kiểm tra đầu vào, sinh `lec/soc_rtl2gate.do`, chạy `lec`, in dòng kết quả |
| `lec/soc_rtl2gate.do` | Dofile đã sinh, Conformal đọc file này |
| `appendix/lec_soc/` | Report văn bản của các lần chạy |

## 1. Flow hoạt động thế nào

`run_lec_soc.sh` làm lần lượt:

1. Kiểm tra có mẫu dofile, có netlist `syn/out_soc/soc_top_netlist.v`, có lệnh `lec`. In commit hiện tại, kích thước và giờ ghi của netlist, và cảnh báo nếu có file RTL mới hơn netlist (nghĩa là RTL đã đổi sau lần tổng hợp).
2. Chép netlist sang `LEC_DIR` (mặc định `syn/out_soc_lec`), để lần tổng hợp mới của người khác không đổi netlist khi LEC đang chạy.
3. Lập danh sách file RTL golden bằng `ls`. Danh sách giống `syn/scripts/synth_soc.tcl`: `rtl/core/rv32_*.v`, `rtl/bus`, `rtl/mem`, `rtl/periph`, và bốn file `rtl/accel` (`pe.v`, `accelerator_top.v`, `accel_wrapper.v`, `accel_apb.v`).
4. Điền mẫu `lec/soc_rtl2gate.do.in` thành `lec/soc_rtl2gate.do`.
5. Chạy `lec -nogui -dofile lec/soc_rtl2gate.do < /dev/null`, ghi log vào `LEC_DIR/lec.txt`, các report vào `LEC_DIR/reports/`.

Hai phía dùng cùng top `soc_top` với tham số mặc định, vì Genus tổng hợp `soc_top` trực tiếp, không có wrapper như `rv32_core`.

### Dofile

Phần lớn lệnh lấy từ `lec/core_rtl2gate.do` (đã chạy trên server, D-042) và `lec/accel_rtl2gate.do`:

- `set dofile abort off`: lệnh lỗi (ví dụ thiếu license) không làm dừng dofile. Vì vậy sau khi chạy phải đọc log tìm `// Error`.
- `read library -both ~/PDK_GPDK45/lib/slow_vdd1v0_basiccells.v`: thư viện cell chuẩn.
- `add search path rtl/core|bus|mem -design -golden`: Conformal 24.1 không nhận `-incdir` trong `read design`, dùng `add search path` cho `include` (`rv32_defs.vh`, `boot_rom_init.vh`).
- `set flatten model -seq_constant`, `-seq_constant_x_to 0`, `-nodff_to_dlat_zero`, `-nodff_to_dlat_feedback`, `-hier_seq_merge`, và `-gated_clock` (netlist có cell clock gating dạng latch và AND, Conformal mô hình chúng thành enable của flop).
- `set compare effort high`, `add compared points -all`, `compare`.
- Sau `compare`: `report compare data -class nonequivalent -verbose`, `report compare data -class abort`, `report verification`, `report unmapped points`.

Không có `analyze datapath` vì cần license Conformal_Ultra mà trường không có.

### Macro SRAM

`sram_2k_macro` (8 instance, 1024x32) được coi là hộp đen ở cả hai phía. Phải khai báo **trước** `read design`:

- `add black box` đặt sau `read design` không dùng được: lỗi `referenced but not defined` đã xảy ra trước đó, và `Golden does not exist`.
- `read library` của macro (không có `-append`) báo `Library for golden design already exists`.
- Cách đang dùng (`MACRO_MODE=undef`): `set undefined cell black_box -noascend -both`. Cả hai lệnh `read design` thành công.

Cách này coi **mọi** module thiếu là hộp đen, nên dofile có `report black box -both` ngay sau khi đọc design. Danh sách phải chỉ có `sram_2k_macro`. Lần chạy 14/11 cho thấy đúng như vậy (chi tiết ở mục 4).

## 2. Cách chạy

Yêu cầu: chạy trên server trường, tại thư mục repo, có `syn/out_soc/soc_top_netlist.v`, lệnh `lec` có trong `PATH`. Gọi `lec` trực tiếp, không bọc qua `scripts/eda.sh` (chạy trong Docker ở nhà).

Kiểm tra RTL không đổi so với lần tổng hợp. Ví dụ netlist 12/11 được tổng hợp từ commit `eced27a`:

```bash
git diff --stat eced27a HEAD -- rtl
```

Không in gì nghĩa là RTL không đổi. Script cũng cảnh báo nếu có file RTL mới hơn netlist.

**Bước 1. Sinh dofile, chưa gọi Conformal:**

```bash
DRY_RUN=1 bash lec/run_lec_soc.sh
```

Không được có dòng `ERROR` hay `STOP`. Dòng `Dofile written` ghi số file RTL golden và `MACRO_MODE` đang dùng. Mỗi file RTL một dòng, nối bằng `\`, và dòng `set undefined cell` nằm trước `read design -golden`.

**Bước 2. Kiểm tra ngắn, chỉ đọc design (vài giây).** Cắt dofile trước `set system mode lec`:

```bash
sed '/^set system mode lec/,$d' lec/soc_rtl2gate.do > ~/lec_soc_check.do
echo "exit -force" >> ~/lec_soc_check.do
lec -nogui -dofile ~/lec_soc_check.do < /dev/null > ~/lec_soc_check.log 2>&1
grep -n '// Error' ~/lec_soc_check.log | head -20
grep -n -A12 'report black box' ~/lec_soc_check.log
```

Đạt khi không có `// Error`, cả golden và revised đọc thành công, và `report black box -both` chỉ liệt kê `sram_2k_macro`.

**Bước 3. Chạy đầy đủ, ở nền:**

```bash
nohup bash lec/run_lec_soc.sh > ~/lec_soc_run.txt 2>&1 &
tail -n 20 ~/lec_soc_run.txt
tail -n 20 syn/out_soc_lec/lec.txt
```

Với `nohup`, đóng terminal không làm dừng lệnh. Server dùng chung nên không `kill` tiến trình của người khác. Thời gian tham khảo: LEC của lõi khoảng 53 phút (`docs/genus_core.md`), accelerator khoảng 9 phút, `soc_top` 106 phút (lần chạy 13/11).

### Biến môi trường (đều tùy chọn)

| Biến | Mặc định | Ý nghĩa |
| --- | --- | --- |
| `SRC_DIR` | `syn/out_soc` | Thư mục chứa netlist `soc_top_netlist.v` |
| `LEC_DIR` | `syn/out_soc_lec` | Bản chép netlist và kết quả. Đặt khác (ví dụ `syn/out_soc_lec2`) để không ghi đè lần chạy trước |
| `MACRO_MODE` | `undef` | `undef`: `set undefined cell black_box`. `lib` và `verilog`: `read library -both -append -liberty` hoặc `-verilog` cho macro, chưa thử |
| `THREADS` | tắt | Thêm `set parallel option -threads N` trước `compare`. Cú pháp lấy từ `help`, chưa biết có cần license và có nhanh hơn không |
| `ONE_LINE` | `0` | `1`: viết `read design -golden` trên một dòng dài như `core_rtl2gate.do` |
| `DRY_RUN` | `0` | `1`: chỉ sinh dofile, không chạy `lec` |

Ví dụ: `LEC_DIR=syn/out_soc_lec2 THREADS=4 nohup bash lec/run_lec_soc.sh > ~/lec_soc_run2.txt 2>&1 &`

### File kết quả (trong `LEC_DIR/reports/` và `LEC_DIR/`)

| File | Nội dung |
| --- | --- |
| `lec.txt` | Log đầy đủ của Conformal |
| `lec_verification.rpt` | Tổng hợp: kết quả so sánh và các mục cảnh báo |
| `lec_noneq.rpt` | Từng điểm Non-equivalent, kèm điểm gây lệch (`-verbose`) |
| `lec_abort.rpt` | Từng điểm Abort |
| `lec_unmapped.rpt` | Điểm không ghép cặp được và lý do |

Chỉ chép report văn bản vào `appendix/lec_soc/`. Không đưa netlist, SDF, SPEF, GDS, `.lib`, `.lef` lên repo (`.gitignore` chặn các loại này, và không dùng `git add -f`). Thư mục `syn/out_soc_lec*/` chứa bản chép netlist nên không add. Không chạy `make synth-soc` hay `make synth-soc-sweep` để làm LEC, vì chúng ghi đè `syn/out_soc`.

## 3. Cách đọc kết quả

- **Equivalent**: hai phía tương đương.
- **Non-equivalent**: hàm đầu vào D của điểm so sánh khác nhau giữa RTL và netlist. Report `-verbose` ghi điểm ở hai phía và điểm gây lệch (`Due to these Non-equivalent points`).
- **Abort**: Conformal dừng vì hết effort, chưa kết luận tương đương hay không.
- **Unmapped**: điểm chỉ có ở một phía hoặc không ghép được. Mỗi điểm có lý do, ví dụ `unreachable: all paths to outputs are blocked` (không có đường nào ra output) hoặc `Gated-clock deglitching latch` (latch của cell clock gating).
- `report verification` có mục `Black box due to undefined cells: yes` khi có hộp đen. Với `soc_top` điều này là đúng vì có `sram_2k_macro`.

Tiêu chí của nhóm (`docs/flow_notes.md`) là 0 Non-equivalent. Số liệu của lõi để tham chiếu (D-042): 2199 Equivalent, 0 Non-equivalent, 68 Abort ở bộ nhân và chia do thiếu license Conformal_Ultra, GLS của lõi 49/49 PASS.

## 4. Kết quả đã có

Netlist `syn/out_soc/soc_top_netlist.v` ngày 12/11 (3 323 276 byte), tổng hợp từ commit `eced27a`. Từ đó chỉ có một thay đổi trong `rtl/`: `rtl/accel/accel_apb.v`, chỉ là comment (commit `2cebbc6`). Lần chạy 13/11 mất 106 phút. Lần chạy 14/11 dùng dofile mới có các report liệt kê từng điểm và cho cùng số liệu.

| | Số điểm |
| --- | --- |
| Equivalent | 3966 (71 PO, 3887 DFF, 8 BBOX) |
| Non-equivalent | 11 (đều là DFF) |
| Abort | 112 (đều là DFF) |
| Unmapped | 206 phía revised, 69 phía golden |
| Kết quả `report verification` | `FAIL:NONEQ` |

`report black box -both` chỉ liệt kê `sram_2k_macro`. Log ghi `51 undriven pins in Revised` (cảnh báo `RTL2.13`), chưa rõ nguồn gốc.

### 11 điểm Non-equivalent

Ở cả 11 điểm, phía netlist có chân D nối vào hằng số (`ZERO` hoặc `ONE`), còn RTL có MUX.

| Điểm | D trong netlist | Quan sát ở RTL |
| --- | --- | --- |
| `u_uart/tx_sh_reg[8]` | `ONE` (netlist: `.D (1'b1)`) | `uart_apb.v`: cả hai nhánh nạp (`tx_start`, `tx_bound`) đều đưa `1'b1` vào bit 8 |
| `g_spi.u_spi/gen_spi.ctrl_div_reg[15:8]` (8 điểm) | `ZERO` | `spi_apb.v`: nạp `ctrl_div <= {8'd0, PWDATA[15:8]}`, reset về 0 |
| `g_i2c.u_i2c/gen_i2c.state_reg[3]` | `ZERO` | `i2c_apb.v`: các trạng thái chỉ có giá trị 0 đến 6, bit 3 không bao giờ là 1. Chưa tra D trong netlist bằng grep |
| `u_core/wb_cause_q_reg[4]` | `ZERO` | `rv32_core.v`: nguyên nhân chưa xác nhận, cần kiểm các mã cause (`rv32_defs.vh`, `rv32_csr.v`) |

Với 3 trường hợp đầu, điểm chung là flop có mạch giữ giá trị nhưng giá trị nạp vào luôn là hằng số. Genus thay chân D bằng hằng số, còn RTL giữ nguyên MUX nên hai hàm D khác nhau. Chưa có bản sửa nào được merge. Một hướng sửa đang được kiểm chứng (thu hẹp thanh ghi bỏ các bit hằng số). Hướng này đòi hỏi tổng hợp lại, vì RTL mới không còn khớp netlist 12/11.

### 112 điểm Abort

- 68 điểm trong `u_core/g_md.u_muldiv`: `p_hi_q_reg[47:15]` (33 bit) và `p_lo_q_reg[48:14]` (35 bit). Trùng với 68 Abort của lõi ở D-042.
- 44 điểm trong `u_apb`: `st_reg[0]`, `psel_reg[8:0]`, `rsp_err_reg`, `rsp_rdata_reg[31:0]`, `rsp_valid_reg`.

Chưa rõ nguyên nhân Abort của khối `u_apb`. Chưa thử tùy chọn nào để giảm Abort.

### 206 điểm Unmapped

- 69 DFF ở mỗi phía, cùng một tập: các flop rìa mảng PE của accelerator (`a_out_reg`, `b_out_reg`, `valid_out_reg` ở các `ROW[i].COL[j].u_pe`, và `done_reg`). Cả hai phía đều ghi `unreachable: all paths to outputs are blocked`.
- 137 DLAT chỉ có ở netlist: latch của cell clock gating (`RC_CG_HIER_INST*`, `RC_CG_DECLONE_HIER_INST*`). Khớp với số cell clock gating trong netlist.
- `report verification` ghi `Incomplete verification: 0`.

## 5. Giới hạn

- Không có `analyze datapath` (cần Conformal_Ultra), nên các khối nhân chia có thể Abort. GLS kiểm tra thêm về chức năng (`make gls-core` cho lõi).
- Macro SRAM là hộp đen: LEC không kiểm tra bên trong macro.
- `MACRO_MODE=undef` che mọi module thiếu. Luôn đối chiếu `report black box -both`.
- Kết quả chỉ đúng với netlist và RTL của lần chạy. RTL hoặc netlist đổi thì phải chạy lại.
- File shell sửa trên Windows có thể bị đổi ký tự xuống dòng. Nếu `bash` báo `$'\r': command not found` thì chạy `sed -i 's/\r$//' <file>`.
