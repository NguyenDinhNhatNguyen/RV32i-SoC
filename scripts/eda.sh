#!/usr/bin/env bash
# eda.sh - controls the IIC-OSIC-TOOLS container from Ubuntu (WSL), shared by the whole team.
#
#   scripts/eda.sh start          start the container (VNC at http://localhost:8080, password abc123)
#   scripts/eda.sh stop           stop the container
#   scripts/eda.sh status         show whether the container is running
#   scripts/eda.sh check          lint + 2 accelerator simulations (must print 2 PASS lines)
#   scripts/eda.sh run <command>  run any command in the container, from the repo folder
#   scripts/eda.sh shell          open a shell in the container
#   scripts/eda.sh wave           make wave-accel, then open GTKWave (accel.gtkw preset) on the VNC desktop
#
# Variables you can override: IIC_DIR (default ~/eda/IIC-OSIC-TOOLS), DESIGNS (~/eda/designs),
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
        echo "ERROR: the repo must be inside $DESIGNS (now: $repo)" >&2
        echo "     Clone again: git clone https://github.com/NguyenDinhNhatNguyen/rv32i-soc.git $DESIGNS/rv32i-soc" >&2
        exit 1
    fi
    echo "/foss/designs/$rel"
}

running() { [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" = "true" ]; }

need_running() {
    if ! running; then
        echo "Container is not running. Run first: scripts/eda.sh start" >&2
        exit 1
    fi
    WORKDIR=$(repo_workdir)
}

case "${1:-}" in
    start)
        [ -x "$IIC_DIR/start_vnc.sh" ] || { echo "Cannot find $IIC_DIR/start_vnc.sh (see docs/setup_home.md section 3)" >&2; exit 1; }
        (cd "$IIC_DIR" && ./start_vnc.sh)
        echo "Open a browser at: http://localhost:$WEBSERVER_PORT  (password abc123)"
        ;;
    stop)
        docker stop "$CONTAINER"
        ;;
    status)
        if running; then echo "Running: $CONTAINER (http://localhost:$WEBSERVER_PORT)"; else echo "Not running"; fi
        ;;
    check)
        need_running
        docker exec -w "$WORKDIR" "$CONTAINER" bash -lc "make lint-accel && make sim-accel && make sim-accel-apb"
        ;;
    run)
        need_running
        shift
        [ $# -gt 0 ] || { echo "Usage: scripts/eda.sh run <command>" >&2; exit 1; }
        docker exec -w "$WORKDIR" "$CONTAINER" bash -lc "$*"
        ;;
    shell)
        need_running
        docker exec -it -w "$WORKDIR" "$CONTAINER" bash -l
        ;;
    wave)
        need_running
        docker exec -w "$WORKDIR" "$CONTAINER" bash -lc "make wave-accel" | tail -1
        # DISPLAY=:1 is the VNC desktop, and -d runs GTKWave in the background so it does not hold the Ubuntu window
        docker exec -d -e DISPLAY=:1 -w "$WORKDIR" "$CONTAINER" bash -lc "gtkwave tb/unit/out/accel.vcd tb/unit/accel.gtkw"
        echo "GTKWave is open on the VNC desktop: http://localhost:$WEBSERVER_PORT"
        ;;
    *)
        sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
