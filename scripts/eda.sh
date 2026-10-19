#!/usr/bin/env bash
# eda.sh - điều khiển container IIC-OSIC-TOOLS từ Ubuntu (WSL), dùng chung cho cả nhóm.
#
#   scripts/eda.sh start          bật container (VNC ở http://localhost:8080, mật khẩu abc123)
#   scripts/eda.sh stop           tắt container
#   scripts/eda.sh status         xem container có đang chạy không
#   scripts/eda.sh check          lint + 2 bài mô phỏng accelerator (phải ra 2 dòng PASS)
#   scripts/eda.sh run <lệnh>     chạy một lệnh bất kỳ trong container, tại thư mục repo
#   scripts/eda.sh shell          mở shell trong container
#   scripts/eda.sh wave           make wave-accel rồi mở GTKWave (preset accel.gtkw) trên desktop VNC
#
# Biến có thể đổi: IIC_DIR (mặc định ~/eda/IIC-OSIC-TOOLS), DESIGNS (~/eda/designs),
# DOCKER_TAG (2026.10), WEBSERVER_PORT (8080).
set -euo pipefail

IIC_DIR=${IIC_DIR:-$HOME/eda/IIC-OSIC-TOOLS}
DESIGNS=${DESIGNS:-$HOME/eda/designs}
export DOCKER_TAG=${DOCKER_TAG:-2026.10}
export WEBSERVER_PORT=${WEBSERVER_PORT:-8080}
CONTAINER=iic-osic-tools_xvnc_uid_$(id -u)

repo_workdir() {
    local repo rel
    repo=$(cd "$(dirname "$0")/.." && pwd)
    rel=${repo#"$DESIGNS"/}
    if [ "$rel" = "$repo" ]; then
        echo "LOI: repo phai nam trong $DESIGNS (hien tai: $repo)" >&2
        echo "     Clone lai: git clone https://github.com/NguyenDinhNhatNguyen/rv32i-soc.git $DESIGNS/rv32i-soc" >&2
        exit 1
    fi
    echo "/foss/designs/$rel"
}

running() { [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" = "true" ]; }

need_running() {
    if ! running; then
        echo "Container chua chay. Chay truoc: scripts/eda.sh start" >&2
        exit 1
    fi
    WORKDIR=$(repo_workdir)
}

case "${1:-}" in
    start)
        [ -x "$IIC_DIR/start_vnc.sh" ] || { echo "Khong thay $IIC_DIR/start_vnc.sh (xem docs/setup_home.md muc 3)" >&2; exit 1; }
        (cd "$IIC_DIR" && ./start_vnc.sh)
        echo "Mo trinh duyet: http://localhost:$WEBSERVER_PORT  (mat khau abc123)"
        ;;
    stop)
        docker stop "$CONTAINER"
        ;;
    status)
        if running; then echo "Dang chay: $CONTAINER (http://localhost:$WEBSERVER_PORT)"; else echo "Khong chay"; fi
        ;;
    check)
        need_running
        docker exec -w "$WORKDIR" "$CONTAINER" bash -lc "make lint-accel && make sim-accel && make sim-accel-apb"
        ;;
    run)
        need_running
        shift
        [ $# -gt 0 ] || { echo "Cach dung: scripts/eda.sh run <lenh>" >&2; exit 1; }
        docker exec -w "$WORKDIR" "$CONTAINER" bash -lc "$*"
        ;;
    shell)
        need_running
        docker exec -it -w "$WORKDIR" "$CONTAINER" bash -l
        ;;
    wave)
        need_running
        docker exec -w "$WORKDIR" "$CONTAINER" bash -lc "make wave-accel" | tail -1
        # DISPLAY=:1 là desktop VNC; -d để GTKWave chạy nền, không giữ cửa sổ Ubuntu
        docker exec -d -e DISPLAY=:1 -w "$WORKDIR" "$CONTAINER" bash -lc "gtkwave tb/unit/out/accel.vcd tb/unit/accel.gtkw"
        echo "GTKWave đã mở trên desktop VNC: http://localhost:$WEBSERVER_PORT"
        ;;
    *)
        sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
