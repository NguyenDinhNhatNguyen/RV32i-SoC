# Timing diagram bus hệ thống

Theo `docs/spec/core.md` mục 5.1 luật 7. Mỗi cột là một chu kỳ clock. Tín hiệu đổi ngay sau cạnh lên, được lấy mẫu ở cạnh lên cuối chu kỳ. Ô trống là "không quan tâm".

Yêu cầu được nhận ở chu kỳ có `req_valid = 1` và `req_ready = 1` (đánh dấu **nhận**).

## 1. Đọc SRAM liên tiếp (load mỗi chu kỳ)

| Chu kỳ | t0 | t1 | t2 | t3 |
| --- | --- | --- | --- | --- |
| req_valid | 1 | 1 | 0 | 0 |
| addr | A0 | A1 | | |
| we | 0 | 0 | | |
| req_ready | 1 (**nhận**) | 1 (**nhận**) | 1 | 1 |
| CEN của macro | 0 | 0 | 1 | 1 |
| rsp_valid | 0 | 1 | 1 | 0 |
| rdata | | M[A0] | M[A1] | |

- Macro đọc đồng bộ nên dữ liệu có ở chu kỳ ngay sau, khớp luật "rsp_valid sớm nhất ở chu kỳ sau".
- Ở t1, yêu cầu A1 được nhận trong cùng chu kỳ có phản hồi của A0 (luật 3). Không mất chu kỳ nào.

## 2. Ghi SRAM đủ word (SW)

| Chu kỳ | t0 | t1 |
| --- | --- | --- |
| req_valid | 1 | 0 |
| we, be | 1, 1111 | |
| req_ready | 1 (**nhận**) | 1 |
| CEN, WEN | 0, 0 | 1, 1 |
| rsp_valid | 0 | 1 |
| rdata | | 0 |

## 3. Ghi byte/half vào SRAM (SB, SH): đọc, sửa, ghi

| Chu kỳ | t0 | t1 | t2 |
| --- | --- | --- | --- |
| req_valid | 1 | 1 (giữ nguyên) | 0 |
| we, be | 1, 0010 | 1, 0010 | |
| req_ready | 0 (wait) | 1 (**nhận**) | 1 |
| CEN, WEN | 0, 1 (đọc word cũ) | 0, 0 (ghi word đã ghép) | 1, 1 |
| D của macro | | {Q[31:16], wdata[15:8], Q[7:0]} | |
| rsp_valid | 0 | 0 | 1 |

- Macro không có chân ghi theo byte (spec SoC mục 7.3). Chu kỳ t0 đọc word cũ với `req_ready = 0`.
- Master giữ nguyên yêu cầu trong wait state (luật 1), nên t1 vẫn có đủ `addr`, `be`, `wdata` để ghép với Q.
- Store byte/half mất thêm đúng 1 chu kỳ. Đọc và SW không đổi.

## 4. Đọc ngoại vi qua cầu APB có wait state

| Chu kỳ | t0 | t1 | t2 | t3 | t4 |
| --- | --- | --- | --- | --- | --- |
| req_valid | 1 | 0 | 0 | 0 | 0 |
| req_ready | 1 (**nhận**) | 0 | 0 | 0 | 1 |
| PSEL | 0 | 1 | 1 | 1 | 0 |
| PENABLE | 0 | 0 (SETUP) | 1 (ACCESS) | 1 | 0 |
| PREADY | | | 0 (wait) | 1 | |
| PRDATA | | | | D | |
| rsp_valid | 0 | 0 | 0 | 0 | 1 |
| rdata | | | | | D |

- Không có wait state ở slave thì phản hồi ở t3, tức một truy cập APB mất 3 chu kỳ.
- `req_ready` của cầu bằng 1 khi rảnh, kể cả ở chu kỳ có `rsp_valid` (t4), nên master phát được yêu cầu kế tiếp ngay.
- PSEL, PENABLE, PADDR, PWDATA và phản hồi đều lấy từ flop.

## 5. Lỗi: địa chỉ không ánh xạ hoặc truy cập APB không đủ word

| Chu kỳ | t0 | t1 |
| --- | --- | --- |
| req_valid | 1 | 0 |
| addr | 0x5000_0000 | |
| req_ready | 1 (**nhận**) | 1 |
| valid tới slave thật | 0 | 0 |
| rsp_valid | 0 | 1 |
| err | 0 | 1 |
| rdata | | 0 |

- Slave lỗi trong `sys_bus` (địa chỉ không ánh xạ) hoặc trong `apb_bridge` (khe tắt, `be != 1111`) trả lời ở chu kỳ ngay sau, không tạo giao dịch nào ở slave thật.
- `err` chỉ bằng 1 cùng `rsp_valid`. Core biến nó thành load/store access fault (mcause 5 hoặc 7, mtval = địa chỉ).

## 6. Lấy lệnh khi bus dữ liệu dùng IMEM

| Chu kỳ | t0 | t1 | t2 |
| --- | --- | --- | --- |
| if_req, if_addr | 1, P | 1, P | 1, P+4 |
| req_valid vào IMEM | 1 (load từ IMEM) | 0 | 0 |
| if_gnt | 0 | 1 | 1 |
| Macro IMEM đọc | địa chỉ của load | P | P+4 |
| if_rdata | | | M[P] |

- Bus được ưu tiên. IF mất 1 chu kỳ (2 chu kỳ với SB/SH vào IMEM). Core phát lại cùng địa chỉ khi `if_gnt = 0`.
- Lấy lệnh ở boot ROM hoặc ở địa chỉ lỗi không bị bus chặn (`if_gnt = 1`).
