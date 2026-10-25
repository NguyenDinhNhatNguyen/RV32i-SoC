# Làm việc với Git

Quy trình chung của nhóm khi sửa code và đẩy lên GitHub.

## Quy tắc

- Được đẩy thẳng lên `main`, làm đúng các bước ở mục "Mỗi lần làm việc". Việc lớn (core, bus, soc_top) nên làm trên nhánh riêng `feat/<tên>-<việc>` rồi mở pull request để người khác xem trước. Merge xong thì xoá nhánh.
- Commit message tiếng Anh, dòng đầu ngắn, câu mệnh lệnh ("Add ...", "Fix ...").
- Sửa RTL hoặc testbench thì phải chạy test trước khi commit (`scripts/eda.sh check` và các target của khối đã sửa).
- **Không commit file của GPDK45, SRAM macro, Cadence, slide hay PDF của môn.** Repo công khai.

## Cài một lần

Trên mỗi máy, kể cả trên server:

```sh
git config --global pull.rebase true        # pull không tạo commit "Merge branch" thừa
git config --global rebase.autoStash true   # pull được cả khi đang sửa dở
```

## Mỗi lần làm việc

```sh
git pull                    # 1. lấy bản mới trước khi sửa
# ... sửa code ...
git status --short          # 2. chỉ thấy file mình định sửa, không có .lib .lef .gds .spef .sdf
scripts/eda.sh check        # 3. nếu sửa RTL hoặc testbench (ở trường: make sim-accel ...)
git add <tên file>          # 4. add từng file, không dùng "git add ."
git commit -m "Add ..."     # 5. tiếng Anh, câu mệnh lệnh
git pull                    # 6. lấy thay đổi của người khác, commit của mình nằm trên cùng
git push                    # 7. đẩy lên
```

## Khi gặp sự cố

| Tình huống | Làm gì |
| --- | --- |
| `git push` báo `rejected` hoặc `fetch first` | Có người vừa đẩy trước. Chạy `git pull` rồi `git push` lại |
| `git pull` báo `CONFLICT` | Mở file bị xung đột, sửa phần giữa `<<<<<<<` và `>>>>>>>`, rồi `git add <file>` và `git rebase --continue`. Rối quá thì `git rebase --abort` để quay về như trước khi pull |
| Lỡ `git add` nhầm file | `git restore --staged <file>` |
| Commit nhầm, chưa push | `git reset --soft HEAD~1` (bỏ commit, giữ nguyên thay đổi) |
| Commit nhầm, đã push | `git revert <mã commit>` rồi `git push`. Không xoá lịch sử của người khác |
| Muốn bỏ hết thay đổi chưa commit của một file | `git restore <file>` (mất luôn, không lấy lại được) |
| Thiếu thư mục `fw/riscv-tests` hay submodule khác | `git submodule update --init --recursive` |
| GitHub báo `This repository moved` | `git remote set-url origin https://github.com/NguyenDinhNhatNguyen/RV32i-SoC.git` |

Không bao giờ dùng `git push --force` lên `main`: lệnh này xoá commit của người khác trên GitHub.
