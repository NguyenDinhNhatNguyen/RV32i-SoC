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
lint-core unit-core fw-core: SHELL := /bin/bash
lint-core unit-core fw-core: .SHELLFLAGS := -o pipefail -c

# Bộ tham số cho từng module / testbench: mỗi lần chạy cách nhau dấu cách,
# trong một lần chạy là danh sách NAME=VALUE cách nhau dấu phẩy. Không khai báo thì dùng mặc định.
CORE_LINT_CFG_rv32_decoder    := ENABLE_M=0 ENABLE_M=1
CORE_LINT_CFG_rv32_core       := ENABLE_M=0 ENABLE_M=1
CORE_UNIT_CFG_tb_rv32_decoder := ENABLE_M=0 ENABLE_M=1
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
CORE_RV_ASFLAGS := -march=rv32i_zicsr_zifencei -mabi=ilp32 -nostdlib -nostartfiles -static \
                   -T fw/common/link.ld -Ifw/tests/asm

CORE_FW_OUT   := $(CORE_OUT)/fw
CORE_FW_TESTS := $(basename $(notdir $(wildcard fw/tests/asm/*.S)))
ifneq ($(T),)
CORE_FW_TESTS := $(filter $(T),$(CORE_FW_TESTS))
endif
CORE_FW_M     := 0 1
# Chế độ chạy: đúng timing pipeline khi không stall, rồi 3 bộ stall bus ngẫu nhiên
# (cổng lệnh không được cấp quyền, wait state, phản hồi trễ) với seed cố định.
CORE_FW_MODES := nominal stall1 stall2 stall3
CORE_FW_PLUS_nominal := +strict_timing
CORE_FW_PLUS_stall1  := +seed=1 +if_stall=25 +d_stall=30 +rsp_delay=3
CORE_FW_PLUS_stall2  := +seed=2 +if_stall=50 +d_stall=50 +rsp_delay=5
CORE_FW_PLUS_stall3  := +seed=3 +if_stall=10 +d_stall=70 +rsp_delay=1
CORE_FW_RUNS  := $(foreach m,$(CORE_FW_M),$(foreach t,$(CORE_FW_TESTS),$(foreach md,$(CORE_FW_MODES),$(t)@$(m)@$(md))))

.PRECIOUS: $(CORE_FW_OUT)/%.elf
$(CORE_FW_OUT)/%.elf: fw/tests/asm/%.S fw/tests/asm/test_macros.h fw/common/link.ld
	@mkdir -p $(@D)
	@test -n "$(RV_PREFIX)" || { echo "LOI: khong tim thay riscv gcc"; exit 1; }
	$(RV_PREFIX)-gcc $(CORE_RV_ASFLAGS) -o $@ $<

# elf2hex in ra "tohost=<hex>", giữ lại làm plusarg khi chạy
$(CORE_FW_OUT)/%.tohost: $(CORE_FW_OUT)/%.elf scripts/elf2hex.py tb/core/core_tb_map.vh
	$(PYTHON) scripts/elf2hex.py $< --imem $(CORE_FW_OUT)/$*.imem.hex --dmem $(CORE_FW_OUT)/$*.dmem.hex > $@

$(CORE_OUT)/tb_core_M%.vvp: tb/core/tb_core.v tb/core/core_tb_map.vh $(CORE_RTL) $(CORE_MODELS) rtl/core/rv32_defs.vh
	@mkdir -p $(@D)
	$(IVERILOG) $(CORE_IVFLAGS) -s tb_core -Ptb_core.ENABLE_M=$* -o $@ $(CORE_RTL) $(CORE_MODELS) tb/core/tb_core.v

fw-core: $(foreach m,$(CORE_FW_M),$(CORE_OUT)/tb_core_M$(m).vvp) $(foreach t,$(CORE_FW_TESTS),$(CORE_FW_OUT)/$(t).tohost)
	@pass=0; fail=0; \
	run_one() { \
	  t=$$1; m=$$2; md=$$3; log=$(CORE_FW_OUT)/$$t.M$$m.$$md.log; \
	  if $(VVP) -n $(CORE_OUT)/tb_core_M$$m.vvp +imem=$(CORE_FW_OUT)/$$t.imem.hex \
	       +dmem=$(CORE_FW_OUT)/$$t.dmem.hex +$$(cat $(CORE_FW_OUT)/$$t.tohost) \
	       +test=$$t/M$$m/$$md $$4 $(PLUSARGS) > $$log 2>&1 && \
	     grep -q '^PASS' $$log && ! grep -q '^FAIL' $$log; then \
	    pass=$$((pass+1)); echo "  $$(grep '^PASS' $$log | tail -n 1)"; \
	  else \
	    fail=$$((fail+1)); echo "  [FAIL] $$t M$$m $$md (log: $$log)"; tail -n 20 $$log; \
	  fi; \
	}; \
	$(foreach r,$(CORE_FW_RUNS),run_one $(subst @, ,$(r)) "$(CORE_FW_PLUS_$(lastword $(subst @, ,$(r))))";) \
	echo "FW-CORE: $$pass passed, $$fail failed"; [ $$fail = 0 ]

clean-core:
	rm -rf $(CORE_OUT) $(CORE_UNIT_OUT)
