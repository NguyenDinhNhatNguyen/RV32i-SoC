# Điểm vào chung. Các target Cadence chỉ chạy trên server trường.
IVERILOG ?= iverilog
VVP      ?= vvp

ACCEL_RTL = rtl/accel/sa_core_model.v rtl/accel/accel_wrapper.v
ACCEL_TB  = tb/unit/tb_accel_wrapper.v

.PHONY: help sim-accel sim-accel-apb wave-accel lint-accel synth-accel lec-accel gls-accel pnr-accel check-server clean

help:
	@echo "make sim-accel     - mô phỏng wrapper accelerator (Icarus, chạy ở nhà)"
	@echo "make sim-accel-apb - mô phỏng accelerator qua giao diện APB3"
	@echo "make wave-accel    - mô phỏng và ghi sóng tb/unit/out/accel.vcd (xem bằng GTKWave)"
	@echo "make lint-accel    - lint wrapper bằng Verilator nếu có"
	@echo "make check-server  - kiểm tra thư viện/tool trên server trường"
	@echo "make synth-accel   - Genus tổng hợp accelerator (server), CG=0 để chạy baseline"
	@echo "make lec-accel     - Conformal so RTL với netlist sau make synth-accel (server)"
	@echo "make gls-accel     - Xcelium mô phỏng netlist sau tổng hợp bằng testbench 40 phép nhân (server)"
	@echo "make pnr-accel     - Innovus chạy thử accelerator (server)"
	@echo "make lint-core     - lint core RV32I bằng Verilator, 0 warning"
	@echo "make unit-core     - unit test các khối của core (ALU, regfile, decoder, imm_gen, lsu_align)"
	@echo "make fw-core       - test assembly trên tb_core (T=tên để chạy một bài)"
	@echo "make isa-core      - riscv-tests (rv32ui/rv32mi/rv32um, env p) trên tb_core (T=rv32ui-p-add)"
	@echo "make bench-core    - Dhrystone và CoreMark trên tb_core (ENABLE_M=0 và 1), in CPI (T=coremark)"
	@echo "make clean-core    - xoá kết quả mô phỏng của core"

sim-accel:
	@mkdir -p tb/unit/out
	$(IVERILOG) -g2005 -Wall -o tb/unit/out/accel.vvp $(ACCEL_RTL) $(ACCEL_TB)
	$(VVP) -n tb/unit/out/accel.vvp

sim-accel-apb:
	@mkdir -p tb/unit/out
	$(IVERILOG) -g2005 -Wall -o tb/unit/out/accel_apb.vvp $(ACCEL_RTL) rtl/accel/accel_apb.v tb/unit/tb_accel_apb.v
	$(VVP) -n tb/unit/out/accel_apb.vvp

wave-accel:
	@mkdir -p tb/unit/out
	$(IVERILOG) -g2005 -Wall -DDUMP_VCD -o tb/unit/out/accel_wave.vvp $(ACCEL_RTL) $(ACCEL_TB)
	cd tb/unit/out && $(VVP) -n accel_wave.vvp
	@echo "Mo song: gtkwave tb/unit/out/accel.vcd tb/unit/accel.gtkw &"

lint-accel:
	verilator --lint-only -Wall $(ACCEL_RTL) rtl/accel/accel_apb.v --top-module accel_apb

check-server:
	bash scripts/check_server.sh

synth-accel:
	rm -f syn/out_accel/accel_wrapper_netlist.v
	cd syn && mkdir -p run_accel && cd run_accel && rm -f genus.log* genus.cmd* && genus -batch -files ../scripts/synth_accel.tcl -log genus.log
	@test -f syn/out_accel/accel_wrapper_netlist.v || { echo "LOI: Genus khong tao duoc netlist, xem syn/run_accel/genus.log"; exit 1; }

# < /dev/null để Conformal tự thoát nếu dofile dừng giữa chừng.
lec-accel:
	@test -f syn/out_accel/accel_wrapper_netlist.v || { echo "LOI: chua co netlist, chay make synth-accel truoc"; exit 1; }
	mkdir -p syn/out_accel/reports
	lec -nogui -dofile lec/accel_rtl2gate.do < /dev/null > syn/out_accel/lec.txt 2>&1 || true
	@grep -E 'Compare Results|Non-equivalent|Equivalent|Abort|// Error' syn/out_accel/lec.txt | tail -12

# Mô phỏng mức cổng, không delay (-nospecify): kiểm chức năng netlist, bù cho điểm LEC bị Abort.
# Thư viện cell .v đọc từ PDK trên server, không copy về máy cá nhân.
GLS_LIB ?= $(or $(PDK_DIR),$(HOME)/PDK_GPDK45)/lib/slow_vdd1v0_basiccells.v
gls-accel:
	@test -f syn/out_accel/accel_wrapper_netlist.v || { echo "LOI: chua co netlist, chay make synth-accel truoc"; exit 1; }
	mkdir -p syn/out_accel/gls
	cd syn/out_accel/gls && xrun -64bit -define GLS -timescale 1ns/1ps -nospecify -notimingchecks \
	  $(CURDIR)/tb/unit/tb_accel_wrapper.v ../accel_wrapper_netlist.v $(GLS_LIB) -l xrun.log > /dev/null 2>&1 || true
	@grep -E 'PASS|FAIL|ERROR|\*E,|\*F,' syn/out_accel/gls/xrun.log | head -15

pnr-accel:
	rm -f pnr/out_accel/accel_wrapper_pnr.v
	cd pnr && mkdir -p run_accel && cd run_accel && rm -f innovus.log* innovus.cmd* && innovus -batch -files ../scripts/run_all.tcl -log innovus.log
	@test -f pnr/out_accel/accel_wrapper_pnr.v || { echo "LOI: Innovus dung giua chung, xem pnr/run_accel/innovus.log"; exit 1; }

clean:
	rm -rf tb/unit/out syn/run* pnr/run*

# ---------------------------------------------------------------------------
# Core RV32I (Nhân). Đặc tả: docs/spec/core.md, quyết định: docs/core_decisions.md
# Chạy ở nhà (Icarus, Verilator, riscv gcc). Kết quả ở tb/unit/out/core và tb/core/out (bị ignore).
#   make lint-core                 Verilator -Wall từng module trong rtl/core, 0 warning
#   make unit-core                 mọi tb/unit/tb_rv32_*.v (TB=tb_rv32_alu để chạy một bài)
#   make fw-core                   test assembly fw/tests/asm trên tb_core (T=hazard để chạy một bài)
#   make unit-core PLUSARGS="+seed=7 +n=1000"     thêm plusarg cho mô phỏng
#   make fw-core T=hazard PLUSARGS=+trace         in vết từng lệnh
# ---------------------------------------------------------------------------
VERILATOR ?= verilator
PYTHON    ?= python3
PLUSARGS  ?=
TB        ?=
T         ?=

CORE_OUT      := tb/core/out
CORE_UNIT_OUT := tb/unit/out/core
CORE_INC      := rtl/core tb/core
CORE_RTL      := $(wildcard rtl/core/*.v)
CORE_MODELS   := tb/models/sram_1rw_model.v
CORE_IVFLAGS  := -g2012 -Wall $(addprefix -I,$(CORE_INC))
CORE_VLFLAGS  := --lint-only -Wall -Irtl/core -y rtl/core

# Recipe của core dùng cú pháp bash và pipefail. Chỉ đặt cho target core để không đổi target có sẵn.
lint-core unit-core: SHELL := /bin/bash
lint-core unit-core: .SHELLFLAGS := -o pipefail -c

# Bộ tham số cho từng module / testbench: mỗi lần chạy cách nhau dấu cách,
# trong một lần chạy là danh sách NAME=VALUE cách nhau dấu phẩy. Không khai báo thì dùng mặc định.
CORE_LINT_CFG_rv32_decoder    := ENABLE_M=0 ENABLE_M=1
CORE_LINT_CFG_rv32_core       := ENABLE_M=0,ENABLE_WFI_SLEEP=0 ENABLE_M=0,ENABLE_WFI_SLEEP=1 \
                                 ENABLE_M=1,ENABLE_WFI_SLEEP=0 ENABLE_M=1,ENABLE_WFI_SLEEP=1
CORE_LINT_CFG_rv32_csr        := ENABLE_M=0 ENABLE_M=1
CORE_UNIT_CFG_tb_rv32_decoder := ENABLE_M=0 ENABLE_M=1
CORE_UNIT_CFG_tb_rv32_csr     := ENABLE_M=0 ENABLE_M=1
core_cfgs = $(or $(CORE_LINT_CFG_$(1)),$(CORE_UNIT_CFG_$(1)),default)

# Lint từng module làm top riêng, rv32_core kéo theo cả phân cấp qua -y.
CORE_LINT_RUNS := $(foreach m,$(basename $(notdir $(CORE_RTL))),$(foreach c,$(call core_cfgs,$(m)),$(m)@$(c)))

CORE_UNIT_TBS  := $(basename $(notdir $(wildcard tb/unit/tb_rv32_*.v)))
CORE_UNIT_RUNS := $(foreach t,$(CORE_UNIT_TBS),$(foreach c,$(call core_cfgs,$(t)),$(t)@$(c)))
ifneq ($(TB),)
CORE_UNIT_RUNS := $(filter $(TB)@%,$(CORE_UNIT_RUNS))
endif

.PHONY: lint-core unit-core fw-core clean-core

lint-core:
	@fail=0; \
	for run in $(CORE_LINT_RUNS); do \
	  m=$${run%%@*}; cfg=$${run#*@}; gflags=""; \
	  if [ "$$cfg" != default ]; then for kv in $${cfg//,/ }; do gflags="$$gflags -G$$kv"; done; fi; \
	  if $(VERILATOR) $(CORE_VLFLAGS) --top-module $$m $$gflags rtl/core/$$m.v; then \
	    echo "  [ OK ] lint $$m ($$cfg)"; \
	  else \
	    echo "  [FAIL] lint $$m ($$cfg)"; fail=1; \
	  fi; \
	done; \
	if [ $$fail = 0 ]; then echo "LINT-CORE PASS"; else echo "LINT-CORE FAIL"; exit 1; fi

# Testbench đạt khi log có dòng bắt đầu bằng PASS và không có dòng FAIL.
unit-core:
	@mkdir -p $(CORE_UNIT_OUT); pass=0; fail=0; \
	for run in $(CORE_UNIT_RUNS); do \
	  tb=$${run%%@*}; cfg=$${run#*@}; pflags=""; tag=$$tb; \
	  if [ "$$cfg" != default ]; then \
	    for kv in $${cfg//,/ }; do pflags="$$pflags -P$$tb.$$kv"; done; \
	    tag="$${tb}_$${cfg//[=,]/_}"; \
	  fi; \
	  log=$(CORE_UNIT_OUT)/$$tag.log; \
	  if $(IVERILOG) $(CORE_IVFLAGS) -s $$tb $$pflags -o $(CORE_UNIT_OUT)/$$tag.vvp \
	       $(CORE_RTL) tb/unit/$$tb.v > $$log 2>&1 && \
	     $(VVP) -n $(CORE_UNIT_OUT)/$$tag.vvp $(PLUSARGS) >> $$log 2>&1 && \
	     grep -q '^PASS' $$log && ! grep -q '^FAIL' $$log; then \
	    pass=$$((pass+1)); echo "  $$(grep '^PASS' $$log | tail -n 1)"; \
	  else \
	    fail=$$((fail+1)); echo "  [FAIL] $$tag (log: $$log)"; tail -n 20 $$log; \
	  fi; \
	done; \
	echo "UNIT-CORE: $$pass passed, $$fail failed"; [ $$fail = 0 ]

# Tự dò tiền tố toolchain (đổi bằng: make fw-core RV_PREFIX=...)
RV_PREFIX ?= $(firstword $(foreach p,riscv64-unknown-elf riscv-none-elf riscv32-unknown-elf,\
               $(if $(shell command -v $(p)-gcc 2>/dev/null),$(p))))
CORE_RV_LDFLAGS := -mabi=ilp32 -nostdlib -nostartfiles -static -T fw/common/link.ld
CORE_RV_ASFLAGS := -march=rv32i_zicsr_zifencei $(CORE_RV_LDFLAGS) -Ifw/tests/asm

# Cấu hình tb_core: M<ENABLE_M>W<ENABLE_WFI_SLEEP>
core_cfg_m = $(word 1,$(subst W, ,$(subst M,,$(1))))
core_cfg_w = $(word 2,$(subst W, ,$(subst M,,$(1))))

# Chế độ chạy: đúng timing pipeline khi không stall, rồi 3 bộ stall bus ngẫu nhiên
# (cổng lệnh không được cấp quyền, wait state, phản hồi trễ) với seed cố định.
CORE_MODES := nominal stall1 stall2 stall3
CORE_PLUS_nominal := +strict_timing
CORE_PLUS_stall1  := +seed=1 +if_stall=25 +d_stall=30 +rsp_delay=3
CORE_PLUS_stall2  := +seed=2 +if_stall=50 +d_stall=50 +rsp_delay=5
CORE_PLUS_stall3  := +seed=3 +if_stall=10 +d_stall=70 +rsp_delay=1

CORE_FW_OUT   := $(CORE_OUT)/fw
CORE_FW_TESTS := $(basename $(notdir $(wildcard fw/tests/asm/*.S)))
ifneq ($(T),)
CORE_FW_TESTS := $(filter $(T),$(CORE_FW_TESTS))
endif
CORE_FW_CFGS  := M0W0 M0W1 M1W0 M1W1
CORE_FW_RUNS  := $(foreach c,$(CORE_FW_CFGS),$(foreach t,$(CORE_FW_TESTS),$(foreach md,$(CORE_MODES),$(t)@$(c)@$(md))))

.PRECIOUS: $(CORE_FW_OUT)/%.elf
$(CORE_FW_OUT)/%.elf: fw/tests/asm/%.S fw/tests/asm/test_macros.h fw/common/link.ld
	@mkdir -p $(@D)
	@test -n "$(RV_PREFIX)" || { echo "LOI: khong tim thay riscv gcc"; exit 1; }
	$(RV_PREFIX)-gcc $(CORE_RV_ASFLAGS) -o $@ $<

# elf2hex in ra "tohost=<hex>", giữ lại làm plusarg khi chạy
$(CORE_OUT)/%.tohost: $(CORE_OUT)/%.elf scripts/elf2hex.py tb/core/core_tb_map.vh
	@$(PYTHON) scripts/elf2hex.py $< --imem $(CORE_OUT)/$*.imem.hex --dmem $(CORE_OUT)/$*.dmem.hex > $@

$(CORE_OUT)/tb_core_%.vvp: tb/core/tb_core.v tb/core/core_tb_map.vh $(CORE_RTL) $(CORE_MODELS) rtl/core/rv32_defs.vh
	@mkdir -p $(@D)
	$(IVERILOG) $(CORE_IVFLAGS) -s tb_core -Ptb_core.ENABLE_M=$(call core_cfg_m,$*) \
	  -Ptb_core.ENABLE_WFI_SLEEP=$(call core_cfg_w,$*) -o $@ $(CORE_RTL) $(CORE_MODELS) tb/core/tb_core.v

# Chạy danh sách "<thư mục>/<test>@<cấu hình>@<chế độ>" song song (CORE_JOBS tiến trình)
# bằng scripts/core_run.sh. Kết quả từng lần chạy ghi vào $(CORE_OUT)/<nhãn>.summary.
CORE_JOBS ?= $(shell nproc 2>/dev/null || echo 4)
export CORE_PLUS_nominal CORE_PLUS_stall1 CORE_PLUS_stall2 CORE_PLUS_stall3 PLUSARGS VVP
define core_run
	@printf '%s\n' $(2) | xargs -P $(CORE_JOBS) -n 1 bash scripts/core_run.sh $(CORE_OUT) \
	  > $(CORE_OUT)/$(1).summary; \
	cat $(CORE_OUT)/$(1).summary; \
	pass=$$(grep -c '^  PASS' $(CORE_OUT)/$(1).summary); \
	fail=$$(grep -c '^  \[FAIL\]' $(CORE_OUT)/$(1).summary); \
	echo "$(1): $$pass passed, $$fail failed"; [ $$fail = 0 ] && [ $$pass -gt 0 ]
endef

fw-core: $(foreach c,$(CORE_FW_CFGS),$(CORE_OUT)/tb_core_$(c).vvp) $(foreach t,$(CORE_FW_TESTS),$(CORE_FW_OUT)/$(t).tohost)
	$(call core_run,fw-core,$(addprefix $(CORE_FW_OUT)/,$(CORE_FW_RUNS)))

# ---------------------------------------------------------------------------
# riscv-tests (submodule fw/riscv-tests, env p) trên tb_core, docs/spec/core.md mục 10.3.
# Test bị loại có lý do trong docs/riscv-tests-status.md.
#   make isa-core                  mọi test với ENABLE_M=0 và 1
#   make isa-core T=rv32ui-p-add   chạy một test
# ---------------------------------------------------------------------------
CORE_ISA_DIR  := fw/riscv-tests/isa
CORE_ISA_ENV  := fw/riscv-tests/env/p
CORE_ISA_OUT  := $(CORE_OUT)/isa
core_isa_list = $(addprefix $(1)-p-,$(basename $(notdir $(wildcard $(CORE_ISA_DIR)/$(1)/*.S))))
CORE_ISA_SKIP := rv32ui-p-ma_data rv32mi-p-breakpoint rv32mi-p-pmpaddr
CORE_ISA_BASE := $(filter-out $(CORE_ISA_SKIP),$(call core_isa_list,rv32ui) $(call core_isa_list,rv32mi))
CORE_ISA_M    := $(filter-out $(CORE_ISA_SKIP),$(call core_isa_list,rv32um))
CORE_ISA_CFGS := M0W0 M1W1
ifneq ($(T),)
CORE_ISA_BASE := $(filter $(T),$(CORE_ISA_BASE))
CORE_ISA_M    := $(filter $(T),$(CORE_ISA_M))
endif
# Test RV32M chỉ chạy với ENABLE_M=1
core_isa_tests = $(CORE_ISA_BASE) $(if $(filter 1,$(call core_cfg_m,$(1))),$(CORE_ISA_M))
CORE_ISA_RUNS := $(foreach c,$(CORE_ISA_CFGS),$(foreach t,$(call core_isa_tests,$(c)),$(foreach md,$(CORE_MODES),$(t)@$(c)@$(md))))

CORE_ISA_FLAGS := -mabi=ilp32 -nostdlib -nostartfiles -static -T fw/common/link_isa.ld \
                  -I$(CORE_ISA_ENV) -I$(CORE_ISA_DIR)/macros/scalar

.PRECIOUS: $(CORE_ISA_OUT)/rv32ui-p-%.elf $(CORE_ISA_OUT)/rv32mi-p-%.elf $(CORE_ISA_OUT)/rv32um-p-%.elf
$(CORE_ISA_OUT)/rv32ui-p-%.elf: $(CORE_ISA_DIR)/rv32ui/%.S fw/common/link_isa.ld
	@mkdir -p $(@D)
	@$(RV_PREFIX)-gcc -march=rv32i_zicsr_zifencei $(CORE_ISA_FLAGS) -o $@ $<
$(CORE_ISA_OUT)/rv32mi-p-%.elf: $(CORE_ISA_DIR)/rv32mi/%.S fw/common/link_isa.ld
	@mkdir -p $(@D)
	@$(RV_PREFIX)-gcc -march=rv32i_zicsr_zifencei $(CORE_ISA_FLAGS) -o $@ $<
$(CORE_ISA_OUT)/rv32um-p-%.elf: $(CORE_ISA_DIR)/rv32um/%.S fw/common/link_isa.ld
	@mkdir -p $(@D)
	@$(RV_PREFIX)-gcc -march=rv32im_zicsr_zifencei $(CORE_ISA_FLAGS) -o $@ $<

isa-core: SHELL := /bin/bash
isa-core: .SHELLFLAGS := -o pipefail -c
fw-core: SHELL := /bin/bash
fw-core: .SHELLFLAGS := -o pipefail -c

isa-core: $(foreach c,$(CORE_ISA_CFGS),$(CORE_OUT)/tb_core_$(c).vvp) \
          $(foreach t,$(CORE_ISA_BASE) $(CORE_ISA_M),$(CORE_ISA_OUT)/$(t).tohost)
	@test -f $(CORE_ISA_ENV)/riscv_test.h || { echo "LOI: chua co submodule, chay: git submodule update --init --recursive fw/riscv-tests"; exit 1; }
	$(call core_run,isa-core,$(addprefix $(CORE_ISA_OUT)/,$(CORE_ISA_RUNS)))

.PHONY: isa-core

clean-core:
	rm -rf $(CORE_OUT) $(CORE_UNIT_OUT)

# ---------------------------------------------------------------------------
# Benchmark trên tb_core: Dhrystone (riscv-tests) và CoreMark (submodule fw/coremark).
# Bản rv32i chạy với ENABLE_M=0, bản rv32im với ENABLE_M=1. Không chèn stall, có
# +strict_timing. CPI đo trong vùng đo của benchmark (mcycle/minstret), dòng
# "BENCH ..." trong log. Kết quả: docs/bench_core.md.
#   make bench-core                         cả 4 lần chạy
#   make bench-core T=coremark              một benchmark
#   make bench-core CM_ITER=10              số vòng CoreMark (mặc định 3)
# ---------------------------------------------------------------------------
CM_ITER         ?= 3
CORE_BENCH_OUT  := $(CORE_OUT)/bench
CORE_BENCH_LIST := dhrystone coremark
ifneq ($(T),)
CORE_BENCH_LIST := $(filter $(T),$(CORE_BENCH_LIST))
endif
# <tên>_<march>@<cấu hình tb_core>@bench
CORE_BENCH_RUNS := $(foreach b,$(CORE_BENCH_LIST),$(b)_rv32i@M0W1@bench $(b)_rv32im@M1W1@bench)
CORE_PLUS_bench := +strict_timing +timeout=50000000
export CORE_PLUS_bench

BENCH_OPT     := -O2
BENCH_CFLAGS  := -mabi=ilp32 $(BENCH_OPT) -ffreestanding -fno-builtin -fno-tree-loop-distribute-patterns \
                 -Ifw/bench/common
BENCH_LDFLAGS := -mabi=ilp32 -nostdlib -nostartfiles -static -T fw/common/link.ld
BENCH_COMMON  := fw/bench/common/crt0.S fw/bench/common/bench.c
BENCH_DHRY    := fw/riscv-tests/benchmarks/dhrystone
BENCH_DHRY_C  := fw/bench/dhrystone/dhry_wrap.c $(BENCH_DHRY)/dhrystone.c
BENCH_CM_SRC  := $(addprefix fw/coremark/,core_list_join.c core_main.c core_matrix.c core_state.c core_util.c) \
                 fw/bench/coremark/core_portme.c
bench_march    = -march=$(1)_zicsr
# Kích thước vùng nhớ đọc từ tb/core/core_tb_map.vh
core_map       = $(shell awk '/CORE_TB_$(1) /{print $$3}' tb/core/core_tb_map.vh)

.PRECIOUS: $(CORE_BENCH_OUT)/dhrystone_%.elf $(CORE_BENCH_OUT)/coremark_%.elf

# Mã gốc Dhrystone viết kiểu K&R nên tắt cảnh báo (-w). dhrystone_main.c
# đổi main thành dhry_main, dhry_wrap.c gọi nó rồi tự kiểm kết quả.
$(CORE_BENCH_OUT)/dhrystone_%.elf: $(BENCH_COMMON) $(BENCH_DHRY_C) $(BENCH_DHRY)/dhrystone_main.c \
                                   $(wildcard fw/bench/dhrystone/*.h) fw/bench/common/bench.h fw/common/link.ld
	@mkdir -p $(@D)
	@test -f $(BENCH_DHRY)/dhrystone.h || { echo "LOI: chua co submodule, chay: git submodule update --init --recursive"; exit 1; }
	$(RV_PREFIX)-gcc $(call bench_march,$*) $(BENCH_CFLAGS) -Ifw/bench/dhrystone -I$(BENCH_DHRY) -w \
	  -Dmain=dhry_main -c -o $(@D)/dhrystone_main_$*.o $(BENCH_DHRY)/dhrystone_main.c
	$(RV_PREFIX)-gcc $(call bench_march,$*) $(BENCH_CFLAGS) -Ifw/bench/dhrystone -I$(BENCH_DHRY) -w \
	  $(BENCH_LDFLAGS) -o $@ $(BENCH_COMMON) $(BENCH_DHRY_C) $(@D)/dhrystone_main_$*.o -lgcc

$(CORE_BENCH_OUT)/coremark_%.elf: $(BENCH_COMMON) $(BENCH_CM_SRC) fw/bench/coremark/core_portme.h \
                                  fw/bench/common/bench.h fw/common/link.ld FORCE_CM_ITER
	@mkdir -p $(@D)
	@test -f fw/coremark/coremark.h || { echo "LOI: chua co submodule, chay: git submodule update --init --recursive"; exit 1; }
	$(RV_PREFIX)-gcc $(call bench_march,$*) $(BENCH_CFLAGS) -Ifw/bench/coremark -Ifw/coremark \
	  -DITERATIONS=$(CM_ITER) -DPERFORMANCE_RUN=1 '-DFLAGS_STR="$(BENCH_OPT)"' \
	  $(BENCH_LDFLAGS) -o $@ $(BENCH_COMMON) $(BENCH_CM_SRC) -lgcc

# CM_ITER không nằm trong tên file nên luôn dịch lại CoreMark
.PHONY: FORCE_CM_ITER bench-core
FORCE_CM_ITER:

bench-core: SHELL := /bin/bash
bench-core: .SHELLFLAGS := -o pipefail -c

# CoreMark tự kiểm CRC. Lỗi "phải chạy ít nhất 10 giây" là bình thường khi mô phỏng
# nên không tính, mọi dòng ERROR khác làm lần chạy FAIL.
bench-core: $(CORE_OUT)/tb_core_M0W1.vvp $(CORE_OUT)/tb_core_M1W1.vvp \
            $(foreach r,$(CORE_BENCH_RUNS),$(CORE_BENCH_OUT)/$(firstword $(subst @, ,$(r))).tohost)
	@for r in $(CORE_BENCH_RUNS); do \
	  t=$${r%%@*}; e=$(CORE_BENCH_OUT)/$$t.elf; \
	  printf '  %-18s .text %6d B (IMEM %d B), DMEM dùng %6d B (%d B)\n' $$t \
	    $$($(RV_PREFIX)-size -A $$e | awk '$$1==".text"{print $$2}') $(call core_map,IMEM_SIZE) \
	    $$($(RV_PREFIX)-size -A $$e | awk '$$1~/^\.(rodata|data|tohost|bss)$$/{s+=$$2} END{print s}') \
	    $(call core_map,DMEM_SIZE); \
	done
	$(call core_run,bench-core,$(addprefix $(CORE_BENCH_OUT)/,$(CORE_BENCH_RUNS)))
	@fail=0; for r in $(CORE_BENCH_RUNS); do \
	  t=$${r%%@*}; rest=$${r#*@}; log=$(CORE_BENCH_OUT)/$$t.$${rest%@*}.bench.log; \
	  grep '^BENCH' $$log | sed "s/^BENCH /  [$$t] /"; \
	  case $$t in coremark*) \
	    if ! grep -q 'performance run parameters' $$log || \
	       grep 'ERROR' $$log | grep -vq 'at least 10 secs'; then \
	      echo "  [FAIL] $$t: CoreMark khong tu kiem duoc ket qua"; fail=1; fi;; \
	  esac; \
	done; [ $$fail = 0 ]
