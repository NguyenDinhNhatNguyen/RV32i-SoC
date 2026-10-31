# Common entry point. The Cadence targets run only on the school server.
IVERILOG ?= iverilog
VVP      ?= vvp

ACCEL_RTL = rtl/accel/pe.v rtl/accel/accelerator_top.v rtl/accel/accel_wrapper.v
ACCEL_TB  = tb/unit/tb_accel_wrapper.v

.PHONY: help sim-accel sim-accel-apb wave-accel lint-accel synth-accel lec-accel gls-accel pnr-accel pnr-soc save-pnr-accel save-pnr-soc check-server clean

help:
	@echo "make sim-accel     - simulate the accelerator wrapper (Icarus, at home)"
	@echo "make sim-accel-apb - simulate the accelerator through APB3"
	@echo "make wave-accel    - simulate and dump tb/unit/out/accel.vcd (view in GTKWave)"
	@echo "make lint-accel    - lint the wrapper with Verilator"
	@echo "make check-server  - check libraries and tools on the school server"
	@echo "make synth-accel   - Genus synthesis of the accelerator (server), CG=0 for the baseline"
	@echo "make lec-accel     - Conformal compares RTL with the netlist after make synth-accel (server)"
	@echo "make gls-accel     - Xcelium gate-level sim of the netlist with the 40-multiply testbench (server)"
	@echo "make pnr-accel     - Innovus trial run on the accelerator (server)"
	@echo "make pnr-soc       - Innovus on soc_top with soc_floorplan.tcl, after make synth-soc (server)"
	@echo "make save-pnr-soc  - copy only the text reports of pnr-soc into appendix/pnr_soc (also save-pnr-accel)"
	@echo "make lint-core     - lint the RV32I core with Verilator, 0 warnings"
	@echo "make unit-core     - unit tests of the core blocks (ALU, regfile, decoder, imm_gen, lsu_align)"
	@echo "make fw-core       - assembly tests on tb_core (T=name runs one test)"
	@echo "make isa-core      - riscv-tests (rv32ui/rv32mi/rv32um, env p) on tb_core (T=rv32ui-p-add)"
	@echo "make bench-core    - Dhrystone and CoreMark on tb_core (ENABLE_M=0 and 1), prints CPI (T=coremark)"
	@echo "make bench-soc     - Dhrystone, CoreMark and accelerator speedup on soc_top (tb_soc), T=accel_bench"
	@echo "make boot-gen      - assemble fw/boot/boot.S and regenerate rtl/mem/boot_rom_init.vh"
	@echo "make sim-boot      - UART bootloader on soc_top: load, C ELF, bad CRC, bad address, timeout, strap (T=load)"
	@echo "make arch-core-dut - riscv-arch-test on the core side only, writes signatures (T=add-01)"
	@echo "make arch-core     - riscv-arch-test through RISCOF, compared with Spike (needs riscof, spike)"
	@echo "make synth-core-yosys - trial Yosys synthesis of rv32_core, trends only"
	@echo "make synth-compare-yosys - as above, plus PicoRV32 (ref/picorv32) for comparison"
	@echo "make sta-core-nangate - Yosys + OpenSTA with the open Nangate45 library, critical path ns and F_max (trends)"
	@echo "make synth-core    - Genus synthesis of rv32_core (server), CG=0/1, PERIOD=20, ENABLE_BTB=1"
	@echo "make synth-core-sweep - Genus at PERIODS=\"20 10 8 6 5\" ns, WNS and F_max table (server)"
	@echo "make lec-core      - Conformal compares rv32_core RTL with the netlist (server)"
	@echo "make gls-core      - Xcelium runs rv32ui and rv32um on the netlist with tb_core (server, SDF=auto)"
	@echo "make clean-core    - delete core simulation results"

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
	@test -f syn/out_accel/accel_wrapper_netlist.v || { echo "ERROR: Genus produced no netlist, see syn/run_accel/genus.log"; exit 1; }

# < /dev/null so Conformal exits if the dofile stops midway.
lec-accel:
	@test -f syn/out_accel/accel_wrapper_netlist.v || { echo "ERROR: no netlist yet, run make synth-accel first"; exit 1; }
	mkdir -p syn/out_accel/reports
	lec -nogui -dofile lec/accel_rtl2gate.do < /dev/null > syn/out_accel/lec.txt 2>&1 || true
	@grep -E 'Compare Results|Non-equivalent|Equivalent|Abort|// Error' syn/out_accel/lec.txt | tail -12

# Gate-level simulation without delays (-nospecify): checks netlist function and backs up
# LEC points that abort.
# The cell .v library is read from the PDK on the server and never copied to personal machines.
GLS_LIB ?= $(or $(PDK_DIR),$(HOME)/PDK_GPDK45)/lib/slow_vdd1v0_basiccells.v
gls-accel:
	@test -f syn/out_accel/accel_wrapper_netlist.v || { echo "ERROR: no netlist yet, run make synth-accel first"; exit 1; }
	mkdir -p syn/out_accel/gls
	cd syn/out_accel/gls && xrun -64bit -define GLS -timescale 1ns/1ps -nospecify -notimingchecks \
	  $(CURDIR)/tb/unit/tb_accel_wrapper.v ../accel_wrapper_netlist.v $(GLS_LIB) -l xrun.log > /dev/null 2>&1 || true
	@grep -E 'PASS|FAIL|ERROR|\*E,|\*F,' syn/out_accel/gls/xrun.log | head -15

pnr-accel:
	rm -f pnr/out_accel/accel_wrapper_pnr.v
	cd pnr && mkdir -p run_accel && cd run_accel && rm -f innovus.log* innovus.cmd* && \
	  TOP=accel_wrapper innovus -batch -files ../scripts/run_all.tcl -log innovus.log
	@test -f pnr/out_accel/accel_wrapper_pnr.v || { echo "ERROR: Innovus stopped midway, see pnr/run_accel/innovus.log"; exit 1; }

# Outputs (netlist, SPEF, SDF, GDS) stay in pnr/out_soc and are never committed.
# Copy only pnr/out_soc/reports into appendix/pnr_soc.
pnr-soc:
	@test -f syn/out_soc/soc_top_netlist.v || { echo "ERROR: no netlist yet, run make synth-soc first"; exit 1; }
	rm -f pnr/out_soc/soc_top_pnr.v
	cd pnr && mkdir -p run_soc && cd run_soc && rm -f innovus.log* innovus.cmd* && \
	  TOP=soc_top innovus -batch -files ../scripts/run_all.tcl -log innovus.log
	@test -f pnr/out_soc/soc_top_pnr.v || { echo "ERROR: Innovus stopped midway, see pnr/run_soc/innovus.log"; exit 1; }
	@cat pnr/out_soc/reports/pd_checks.rpt 2>/dev/null || true

# Copy only text reports into appendix/, never netlists, SPEF, SDF or GDS
save-pnr-accel:
	bash scripts/save_reports.sh pnr/out_accel/reports appendix/pnr_accel
	@git status --short appendix/pnr_accel | head -20

save-pnr-soc:
	bash scripts/save_reports.sh pnr/out_soc/reports appendix/pnr_soc
	@git status --short appendix/pnr_soc | head -20

clean:
	rm -rf tb/unit/out syn/run* pnr/run*

# ---------------------------------------------------------------------------
# RV32I core (Nhan). Spec: docs/spec/core.md, decisions: docs/core_decisions.md
# Runs at home (Icarus, Verilator, riscv gcc). Results in tb/unit/out/core and tb/core/out (ignored).
#   make lint-core                 Verilator -Wall on each module in rtl/core, 0 warnings
#   make unit-core                 every tb/unit/tb_rv32_*.v (TB=tb_rv32_alu runs one)
#   make fw-core                   fw/tests/asm assembly tests on tb_core (T=hazard runs one)
#   make unit-core PLUSARGS="+seed=7 +n=1000"     adds simulation plusargs
#   make fw-core T=hazard PLUSARGS=+trace         prints a per-instruction trace
#   make fw-core BTB=1                            branch prediction experiment, see below
# ---------------------------------------------------------------------------
VERILATOR ?= verilator
PYTHON    ?= python3
PLUSARGS  ?=
TB        ?=
T         ?=

# Branch prediction (docs/btb_eval.md). The RTL default is BTB=1 (8-entry BTB). BTB=0 (none) or
# BTB=2 (static backward taken) changes the default ENABLE_BTB / BTB_ENTRIES of rv32_core with -D,
# for every Icarus and Verilator build of this Makefile (tb_core, tb_soc, tb_boot, lint-soc).
# The .vvp files do not record the mode, so when BTB/BTB_N differ from the last run (kept in
# tb/core/out/btb.cfg) every .vvp under tb/core/out, tb/soc/out and tb/boot/out is deleted.
# Do not run two modes at the same time in one checkout.
BTB   ?= 1
BTB_N ?= 8
ifneq ($(BTB)/$(BTB_N),1/8)
IVERILOG  += -DRV_ENABLE_BTB_DEFAULT=$(BTB) -DRV_BTB_ENTRIES_DEFAULT=$(BTB_N)
VERILATOR += -DRV_ENABLE_BTB_DEFAULT=$(BTB) -DRV_BTB_ENTRIES_DEFAULT=$(BTB_N)
endif
ifneq ($(BTB)/$(BTB_N),$(shell cat tb/core/out/btb.cfg 2>/dev/null || echo none))
$(shell find tb/core/out tb/soc/out tb/boot/out -name '*.vvp' -delete 2>/dev/null; \
        mkdir -p tb/core/out; echo '$(BTB)/$(BTB_N)' > tb/core/out/btb.cfg)
endif

CORE_OUT      := tb/core/out
CORE_UNIT_OUT := tb/unit/out/core
CORE_INC      := rtl/core tb/core
CORE_RTL      := $(wildcard rtl/core/*.v)
CORE_MODELS   := tb/models/sram_1rw_model.v
CORE_IVFLAGS  := -g2012 -Wall $(addprefix -I,$(CORE_INC))
CORE_VLFLAGS  := --lint-only -Wall -Irtl/core -y rtl/core

# Core recipes use bash syntax and pipefail. Set only for core targets so existing targets
# do not change.
lint-core unit-core: SHELL := /bin/bash
lint-core unit-core: .SHELLFLAGS := -o pipefail -c

# Parameter sets per module / testbench: runs are separated by spaces,
# and within a run NAME=VALUE pairs are separated by commas. Undeclared means defaults.
CORE_LINT_CFG_rv32_decoder    := ENABLE_M=0 ENABLE_M=1
CORE_LINT_CFG_rv32_core       := ENABLE_M=0,ENABLE_WFI_SLEEP=0 ENABLE_M=0,ENABLE_WFI_SLEEP=1 \
                                 ENABLE_M=1,ENABLE_WFI_SLEEP=0 ENABLE_M=1,ENABLE_WFI_SLEEP=1 \
                                 ENABLE_M=0,ENABLE_BTB=0 ENABLE_M=1,ENABLE_BTB=0 \
                                 ENABLE_M=1,ENABLE_BTB=1,BTB_ENTRIES=16 \
                                 ENABLE_M=0,ENABLE_BTB=2 ENABLE_M=1,ENABLE_BTB=2
CORE_LINT_CFG_rv32_btb        := ENTRIES=8 ENTRIES=16
CORE_LINT_CFG_rv32_csr        := ENABLE_M=0 ENABLE_M=1
CORE_UNIT_CFG_tb_rv32_decoder := ENABLE_M=0 ENABLE_M=1
CORE_UNIT_CFG_tb_rv32_csr     := ENABLE_M=0 ENABLE_M=1
CORE_UNIT_CFG_tb_rv32_btb     := ENTRIES=8 ENTRIES=16
core_cfgs = $(or $(CORE_LINT_CFG_$(1)),$(CORE_UNIT_CFG_$(1)),default)

# Lint each module as its own top, rv32_core pulls in the whole hierarchy through -y.
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

# A testbench passes when the log has a line starting with PASS and no FAIL line.
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

# Auto-detect the toolchain prefix (override: make fw-core RV_PREFIX=...)
RV_PREFIX ?= $(firstword $(foreach p,riscv64-unknown-elf riscv-none-elf riscv32-unknown-elf,\
               $(if $(shell command -v $(p)-gcc 2>/dev/null),$(p))))
CORE_RV_LDFLAGS := -mabi=ilp32 -nostdlib -nostartfiles -static -T fw/common/link.ld
CORE_RV_ASFLAGS := -march=rv32i_zicsr_zifencei $(CORE_RV_LDFLAGS) -Ifw/tests/asm

# tb_core configuration: M<ENABLE_M>W<ENABLE_WFI_SLEEP>
core_cfg_m = $(word 1,$(subst W, ,$(subst M,,$(1))))
core_cfg_w = $(word 2,$(subst W, ,$(subst M,,$(1))))

# Run modes: exact pipeline timing without stalls, then 3 random bus stall sets
# (fetch port without grant, wait states, delayed responses) with fixed seeds.
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
	@test -n "$(RV_PREFIX)" || { echo "ERROR: riscv gcc not found"; exit 1; }
	$(RV_PREFIX)-gcc $(CORE_RV_ASFLAGS) -o $@ $<

# elf2hex prints "tohost=<hex>", kept as a plusarg for the run
$(CORE_OUT)/%.tohost: $(CORE_OUT)/%.elf scripts/elf2hex.py tb/core/core_tb_map.vh
	@$(PYTHON) scripts/elf2hex.py $< --imem $(CORE_OUT)/$*.imem.hex --dmem $(CORE_OUT)/$*.dmem.hex > $@

$(CORE_OUT)/tb_core_%.vvp: tb/core/tb_core.v tb/core/core_tb_map.vh $(CORE_RTL) $(CORE_MODELS) rtl/core/rv32_defs.vh
	@mkdir -p $(@D)
	$(IVERILOG) $(CORE_IVFLAGS) -s tb_core -Ptb_core.ENABLE_M=$(call core_cfg_m,$*) \
	  -Ptb_core.ENABLE_WFI_SLEEP=$(call core_cfg_w,$*) -o $@ $(CORE_RTL) $(CORE_MODELS) tb/core/tb_core.v

# Run the "<dir>/<test>@<config>@<mode>" list in parallel (CORE_JOBS processes)
# with scripts/core_run.sh. Each run result goes to $(CORE_OUT)/<label>.summary.
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
# riscv-tests (submodule fw/riscv-tests, env p) on tb_core, docs/spec/core.md section 10.3.
# Excluded tests and the reasons are in docs/riscv-tests-status.md.
#   make isa-core                  every test with ENABLE_M=0 and 1
#   make isa-core T=rv32ui-p-add   runs one test
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
# RV32M tests run only with ENABLE_M=1
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
	@test -f $(CORE_ISA_ENV)/riscv_test.h || { echo "ERROR: submodule missing, run: git submodule update --init --recursive fw/riscv-tests"; exit 1; }
	$(call core_run,isa-core,$(addprefix $(CORE_ISA_OUT)/,$(CORE_ISA_RUNS)))

.PHONY: isa-core

clean-core:
	rm -rf $(CORE_OUT) $(CORE_UNIT_OUT)

# ---------------------------------------------------------------------------
# Benchmarks on tb_core: Dhrystone (riscv-tests) and CoreMark (submodule fw/coremark).
# The rv32i build runs with ENABLE_M=0, the rv32im build with ENABLE_M=1. No injected stalls,
# with +strict_timing. CPI is measured over the benchmark region (mcycle/minstret), the
# "BENCH ..." line in the log. Results: docs/bench_core.md.
#   make bench-core                         all 4 runs
#   make bench-core T=coremark              one benchmark
#   make bench-core CM_ITER=10              CoreMark iterations (default 3)
# ---------------------------------------------------------------------------
CM_ITER         ?= 3
CORE_BENCH_OUT  := $(CORE_OUT)/bench
CORE_BENCH_LIST := dhrystone coremark
ifneq ($(T),)
CORE_BENCH_LIST := $(filter $(T),$(CORE_BENCH_LIST))
endif
# <name>_<march>@<tb_core config>@bench
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
# Memory region sizes come from tb/core/core_tb_map.vh
core_map       = $(shell awk '/CORE_TB_$(1) /{print $$3}' tb/core/core_tb_map.vh)

# Benchmark ELF rules for an output folder: $(1) folder, $(2) extra compiler flags.
# The same sources build for tb_core and, with -DBENCH_SOC, for tb_soc (bench-soc).
define bench_elf_rules
.PRECIOUS: $(1)/dhrystone_%.elf $(1)/coremark_%.elf

# The original Dhrystone code is K&R style, so warnings are off (-w). dhrystone_main.c
# renames main to dhry_main, and dhry_wrap.c calls it and checks the results.
$(1)/dhrystone_%.elf: $$(BENCH_COMMON) $$(BENCH_DHRY_C) $$(BENCH_DHRY)/dhrystone_main.c \
                      $$(wildcard fw/bench/dhrystone/*.h) fw/bench/common/bench.h fw/common/link.ld
	@mkdir -p $$(@D)
	@test -f $$(BENCH_DHRY)/dhrystone.h || { echo "ERROR: submodule missing, run: git submodule update --init --recursive"; exit 1; }
	$$(RV_PREFIX)-gcc $$(call bench_march,$$*) $$(BENCH_CFLAGS) $(2) -Ifw/bench/dhrystone -I$$(BENCH_DHRY) -w \
	  -Dmain=dhry_main -c -o $$(@D)/dhrystone_main_$$*.o $$(BENCH_DHRY)/dhrystone_main.c
	$$(RV_PREFIX)-gcc $$(call bench_march,$$*) $$(BENCH_CFLAGS) $(2) -Ifw/bench/dhrystone -I$$(BENCH_DHRY) -w \
	  $$(BENCH_LDFLAGS) -o $$@ $$(BENCH_COMMON) $$(BENCH_DHRY_C) $$(@D)/dhrystone_main_$$*.o -lgcc

$(1)/coremark_%.elf: $$(BENCH_COMMON) $$(BENCH_CM_SRC) fw/bench/coremark/core_portme.h \
                     fw/bench/common/bench.h fw/common/link.ld FORCE_CM_ITER
	@mkdir -p $$(@D)
	@test -f fw/coremark/coremark.h || { echo "ERROR: submodule missing, run: git submodule update --init --recursive"; exit 1; }
	$$(RV_PREFIX)-gcc $$(call bench_march,$$*) $$(BENCH_CFLAGS) $(2) -Ifw/bench/coremark -Ifw/coremark \
	  -DITERATIONS=$$(CM_ITER) -DPERFORMANCE_RUN=1 '-DFLAGS_STR="$$(BENCH_OPT)"' \
	  $$(BENCH_LDFLAGS) -o $$@ $$(BENCH_COMMON) $$(BENCH_CM_SRC) -lgcc
endef
$(eval $(call bench_elf_rules,$(CORE_BENCH_OUT),))

# CM_ITER is not part of the file name, so CoreMark is always rebuilt
.PHONY: FORCE_CM_ITER bench-core
FORCE_CM_ITER:

bench-core: SHELL := /bin/bash
bench-core: .SHELLFLAGS := -o pipefail -c

# CoreMark checks its own CRC. The "must run at least 10 seconds" error is expected in simulation
# and is not counted. Any other ERROR line fails the run.
bench-core: $(CORE_OUT)/tb_core_M0W1.vvp $(CORE_OUT)/tb_core_M1W1.vvp \
            $(foreach r,$(CORE_BENCH_RUNS),$(CORE_BENCH_OUT)/$(firstword $(subst @, ,$(r))).tohost)
	@for r in $(CORE_BENCH_RUNS); do \
	  t=$${r%%@*}; e=$(CORE_BENCH_OUT)/$$t.elf; \
	  printf '  %-18s .text %6d B (IMEM %d B), DMEM used %6d B (%d B)\n' $$t \
	    $$($(RV_PREFIX)-size -A $$e | awk '$$1==".text"{print $$2}') $(call core_map,IMEM_SIZE) \
	    $$($(RV_PREFIX)-size -A $$e | awk '$$1~/^\.(rodata|data|tohost|bss)$$/{s+=$$2} END{print s}') \
	    $(call core_map,DMEM_SIZE); \
	done
	$(call core_run,bench-core,$(addprefix $(CORE_BENCH_OUT)/,$(CORE_BENCH_RUNS)))
	@fail=0; for r in $(CORE_BENCH_RUNS); do \
	  t=$${r%%@*}; rest=$${r#*@}; log=$(CORE_BENCH_OUT)/$$t.$${rest%@*}.bench.log; \
	  grep '^BENCH' $$log | sed "s/^BENCH /  [$$t on $${rest%@*}] /"; \
	  case $$t in coremark*) \
	    if ! grep -q 'performance run parameters' $$log || \
	       grep 'ERROR' $$log | grep -vq 'at least 10 secs'; then \
	      echo "  [FAIL] $$t: CoreMark could not verify its result"; fail=1; fi;; \
	  esac; \
	done; [ $$fail = 0 ]

# ---------------------------------------------------------------------------
# Benchmarks on soc_top (EVA-01): Dhrystone, CoreMark and the accelerator speedup
# (fw/bench/accel_bench.c) on tb_soc, built with -DBENCH_SOC (UART output, BAUDDIV = 1).
# Same sources and flags as bench-core, the rv32i build runs with ENABLE_M=0, the rv32im
# build with ENABLE_M=1, both with ENABLE_WFI_SLEEP=1. Results: docs/bench_soc.md.
#   make bench-soc                          all 6 runs
#   make bench-soc T=accel_bench            one program
# tb_soc is compiled here with scripts/bench_soc_mon.v as a second root, which prints the
# bus stall cycles of each measured region ("BENCH soc region" lines).
# Logs in $(CORE_OUT)/bench_soc.
# ---------------------------------------------------------------------------
SOC_BENCH_OUT  := $(CORE_OUT)/bench_soc
SOC_BENCH_LIST := dhrystone coremark accel_bench
ifneq ($(T),)
SOC_BENCH_LIST := $(filter $(T),$(SOC_BENCH_LIST))
endif
SOC_BENCH_RUNS := $(foreach b,$(SOC_BENCH_LIST),$(b)_rv32i@M0W1 $(b)_rv32im@M1W1)
# Same file set as SOC_RTL in the SoC section (defined further down, so listed here again)
SOC_BENCH_RTL  := $(wildcard rtl/core/*.v rtl/bus/*.v rtl/mem/*.v rtl/periph/*.v rtl/accel/*.v)

$(SOC_BENCH_OUT)/tb_soc_%.vvp: tb/soc/tb_soc.v scripts/bench_soc_mon.v $(SOC_BENCH_RTL) \
                               tb/models/sram_2k_macro.v rtl/core/rv32_defs.vh rtl/bus/soc_map.vh \
                               rtl/mem/boot_rom_init.vh
	@mkdir -p $(@D)
	$(IVERILOG) -g2012 -Irtl/bus -Irtl/mem -Irtl/core -s tb_soc -s bench_soc_mon \
	  -Ptb_soc.ENABLE_M=$(call core_cfg_m,$*) -Ptb_soc.ENABLE_WFI_SLEEP=$(call core_cfg_w,$*) \
	  -o $@ $(SOC_BENCH_RTL) tb/models/sram_2k_macro.v tb/soc/tb_soc.v scripts/bench_soc_mon.v

$(eval $(call bench_elf_rules,$(SOC_BENCH_OUT),-DBENCH_SOC))

.PRECIOUS: $(SOC_BENCH_OUT)/accel_bench_%.elf
$(SOC_BENCH_OUT)/accel_bench_%.elf: $(BENCH_COMMON) fw/bench/accel_bench.c fw/accel.h \
                                    fw/bench/common/bench.h fw/common/link.ld
	@mkdir -p $(@D)
	$(RV_PREFIX)-gcc $(call bench_march,$*) $(BENCH_CFLAGS) -DBENCH_SOC -Ifw \
	  $(BENCH_LDFLAGS) -o $@ $(BENCH_COMMON) fw/bench/accel_bench.c -lgcc

.PHONY: bench-soc
bench-soc: SHELL := /bin/bash
bench-soc: .SHELLFLAGS := -o pipefail -c

# Same pass rules as bench-core (CoreMark CRC, Dhrystone final values, accel results).
bench-soc: $(SOC_BENCH_OUT)/tb_soc_M0W1.vvp $(SOC_BENCH_OUT)/tb_soc_M1W1.vvp \
           $(foreach r,$(SOC_BENCH_RUNS),$(SOC_BENCH_OUT)/$(firstword $(subst @, ,$(r))).tohost)
	@for r in $(SOC_BENCH_RUNS); do \
	  t=$${r%%@*}; e=$(SOC_BENCH_OUT)/$$t.elf; \
	  printf '  %-20s .text %6d B, DMEM used %6d B\n' $$t \
	    $$($(RV_PREFIX)-size -A $$e | awk '$$1==".text"{print $$2}') \
	    $$($(RV_PREFIX)-size -A $$e | awk '$$1~/^\.(rodata|data|tohost|bss)$$/{s+=$$2} END{print s}'); \
	done
	@printf '%s\n' $(addprefix $(SOC_BENCH_OUT)/,$(SOC_BENCH_RUNS)) | \
	  PLUSARGS="+timeout=50000000 $(PLUSARGS)" xargs -P $(CORE_JOBS) -n 1 bash scripts/bench_soc_run.sh $(SOC_BENCH_OUT) \
	  > $(SOC_BENCH_OUT)/bench-soc.summary; \
	cat $(SOC_BENCH_OUT)/bench-soc.summary; \
	fail=$$(grep -c '^  \[FAIL\]' $(SOC_BENCH_OUT)/bench-soc.summary); \
	for r in $(SOC_BENCH_RUNS); do \
	  t=$${r%%@*}; log=$(SOC_BENCH_OUT)/$$t.$${r#*@}.log; \
	  grep '^BENCH' $$log | sed "s/^BENCH /  [$$t on $${r#*@}] /"; \
	  case $$t in coremark*) \
	    if ! grep -q 'performance run parameters' $$log || \
	       grep 'ERROR' $$log | grep -vq 'at least 10 secs'; then \
	      echo "  [FAIL] $$t: CoreMark could not verify its result"; fail=1; fi;; \
	  esac; \
	done; echo "bench-soc: $$fail failed"; [ $$fail = 0 ]

# ---------------------------------------------------------------------------
# UART bootloader (P8): fw/boot/boot.S in the boot ROM at 0x0001_0000. Docs: docs/boot.md.
#   make boot-gen                           assemble boot.S, regenerate rtl/mem/boot_rom_init.vh
#   make sim-boot                           tb/boot/tb_boot.v on soc_top, 7 tests
#   make sim-boot T=timeout                 one test
# BOOT_CLK_HZ, BOOT_BAUD and BOOT_TIMEOUT (cycles) set the committed ROM, the IMEM and DMEM
# ranges come from soc_map.vh. sim-boot builds the ROM again and fails if the committed
# boot_rom_init.vh differs. Most tests use a second ROM from the same source with a short
# timeout and BAUDDIV 1 (BOOT_SIM_*), picked up first through -I. The committed ROM runs the
# strap 0 path and one load at the real baud.
# ---------------------------------------------------------------------------
BOOT_OUT         := tb/boot/out
BOOT_CLK_HZ      ?= 50000000
BOOT_BAUD        ?= 115200
BOOT_TIMEOUT     ?= 50000000
BOOT_SIM_BAUD    := 3125000
BOOT_SIM_TIMEOUT := 20000
BOOT_IMEM_SIZE   := $(shell sed -n 's/^`define SOC_IMEM_SIZE *32.d\([0-9]*\).*/\1/p' \
                      rtl/bus/soc_map.vh)
BOOT_DMEM_SIZE   := $(shell sed -n 's/^`define SOC_DMEM_SIZE *32.d\([0-9]*\).*/\1/p' \
                      rtl/bus/soc_map.vh)
BOOT_DMEM_BASE   := 0x$(shell sed -n 's/^`define SOC_DMEM_BASE *32.h\([0-9A-Fa-f_]*\).*/\1/p' \
                      rtl/bus/soc_map.vh | tr -d _)
boot_asflags      = -march=rv32i_zicsr_zifencei -mabi=ilp32 -nostdlib -nostartfiles -static \
                    -T fw/boot/boot.ld -DCLK_HZ=$(BOOT_CLK_HZ) -DBAUD=$(1) -DTIMEOUT_CYCLES=$(2) \
                    -DIMEM_SIZE=$(BOOT_IMEM_SIZE) -DDMEM_BASE=$(BOOT_DMEM_BASE) \
                    -DDMEM_SIZE=$(BOOT_DMEM_SIZE)
BOOT_RTL         := $(wildcard rtl/core/*.v rtl/bus/*.v rtl/mem/*.v rtl/periph/*.v rtl/accel/*.v)
BOOT_SRC         := fw/boot/boot.S fw/boot/boot.ld scripts/gen_boot_rom.py scripts/elf2hex.py \
                    rtl/bus/soc_map.vh Makefile

# <test>|<rom: rtl or sim>|<files: program in BOOT_OUT and uart_pack options@answer, ...>|
# <plusargs>, ~ is a space. Answer for every packet of the file: A = header and data ACK,
# H = header NAK, D = data NAK. An .elf file also passes +tohost from its .tohost file.
BOOT_TESTS := load|sim|hello.bin~--addr~0x2000@A|+jump=2000~+magic_delay=10000 \
              celf|sim|cprog.elf@A|+jump=0 \
              badcrc|sim|hello.bin~--addr~0x0~--bad-crc@D,hello.bin~--addr~0x0@A|+jump=0 \
              badaddr|sim|hello.bin~--addr~0x4000~--no-check@H,$\
              hello.bin~--addr~0x3fc0~--pad~128~--no-check@H,$\
              hello.bin~--addr~0x1002~--no-check@H,hello.bin~--addr~0x10000~--no-check@H,$\
              hello.bin~--addr~0x10003fc0~--pad~128~--no-check@H,$\
              hello.bin~--addr~0x10004000~--no-check@H,$\
              hello.bin~--addr~0x0~--entry~0x10000000~--no-check@H,$\
              hello.bin~--addr~0x0~--entry~0x2~--no-check@H,$\
              hello.bin~--addr~0x3f00~--pad~256@A|+jump=3f00 \
              timeout|sim||+jump=0~+min_jump=$(BOOT_SIM_TIMEOUT)~+max_jump=$(BOOT_SIM_TIMEOUT)00 \
              fastboot|rtl||+strap=0~+jump=0~+max_jump=100 \
              rtl_load|rtl|hello.bin~--addr~0x0@A|+jump=0
BOOT_LIST  := $(if $(T),$(T),load celf badcrc badaddr timeout fastboot rtl_load)

.PHONY: boot-gen sim-boot
sim-boot: SHELL := /bin/bash
sim-boot: .SHELLFLAGS := -o pipefail -c

boot-gen:
	@mkdir -p $(BOOT_OUT)
	@test -n "$(RV_PREFIX)" || { echo "ERROR: riscv gcc not found"; exit 1; }
	$(RV_PREFIX)-gcc $(call boot_asflags,$(BOOT_BAUD),$(BOOT_TIMEOUT)) \
	  -o $(BOOT_OUT)/boot.elf fw/boot/boot.S
	$(PYTHON) scripts/gen_boot_rom.py $(BOOT_OUT)/boot.elf -o rtl/mem/boot_rom_init.vh

# Fresh builds of both ROMs, rtl/ must equal the committed file
BOOT_ROMS := $(BOOT_OUT)/rtl/boot_rom_init.vh $(BOOT_OUT)/sim/boot_rom_init.vh
$(BOOT_ROMS): $(BOOT_OUT)/%/boot_rom_init.vh: $(BOOT_SRC)
	@mkdir -p $(@D)
	@test -n "$(RV_PREFIX)" || { echo "ERROR: riscv gcc not found"; exit 1; }
	$(RV_PREFIX)-gcc $(if $(filter sim,$*),$(call boot_asflags,$(BOOT_SIM_BAUD),$(BOOT_SIM_TIMEOUT)),$\
	  $(call boot_asflags,$(BOOT_BAUD),$(BOOT_TIMEOUT))) -o $(@D)/boot.elf fw/boot/boot.S
	$(PYTHON) scripts/gen_boot_rom.py $(@D)/boot.elf -o $@ > /dev/null

# The test program: linked at 0 for the IMEM preload, and as a raw .bin for uart_pack
$(BOOT_OUT)/hello.elf: tb/boot/hello.S fw/common/link.ld
	@mkdir -p $(@D)
	$(RV_PREFIX)-gcc $(CORE_RV_ASFLAGS) -o $@ $<

$(BOOT_OUT)/hello.bin: $(BOOT_OUT)/hello.elf scripts/elf2hex.py
	$(RV_PREFIX)-objcopy -O binary -j .text $< $@
	@$(PYTHON) scripts/elf2hex.py $< --imem $(BOOT_OUT)/hello.imem.hex \
	  --dmem $(BOOT_OUT)/hello.dmem.hex > /dev/null

# C program with .text in IMEM and .rodata, .data in DMEM, loaded from its ELF.
# cprog.tohost holds +tohost=<address of the tohost symbol>.
$(BOOT_OUT)/cprog.elf: tb/boot/cprog.c fw/bench/common/crt0.S fw/common/link.ld scripts/elf2hex.py
	@mkdir -p $(@D)
	$(RV_PREFIX)-gcc -march=rv32i_zicsr $(BENCH_CFLAGS) -DBENCH_SOC $(BENCH_LDFLAGS) -o $@ \
	  fw/bench/common/crt0.S tb/boot/cprog.c -lgcc
	@$(PYTHON) scripts/elf2hex.py $@ --imem $(BOOT_OUT)/cprog.imem.hex \
	  --dmem $(BOOT_OUT)/cprog.dmem.hex | sed -n 's/^tohost=/+tohost=/p' > $(BOOT_OUT)/cprog.tohost

# tb_boot_rtl uses rtl/mem/boot_rom_init.vh, tb_boot_sim the simulation ROM
$(BOOT_OUT)/tb_boot_%.vvp: tb/boot/tb_boot.v $(BOOT_RTL) tb/models/sram_2k_macro.v \
                           rtl/core/rv32_defs.vh rtl/bus/soc_map.vh $(BOOT_OUT)/%/boot_rom_init.vh \
                           rtl/mem/boot_rom_init.vh
	$(IVERILOG) -g2012 -Wall -I$(BOOT_OUT)/$* -Irtl/bus -Irtl/mem -Irtl/core -s tb_boot -o $@ \
	  $(BOOT_RTL) tb/models/sram_2k_macro.v tb/boot/tb_boot.v

sim-boot: $(BOOT_OUT)/tb_boot_rtl.vvp $(BOOT_OUT)/tb_boot_sim.vvp $(BOOT_OUT)/hello.bin \
          $(BOOT_OUT)/cprog.elf
	@cmp -s $(BOOT_OUT)/rtl/boot_rom_init.vh rtl/mem/boot_rom_init.vh || \
	  { echo "FAIL: rtl/mem/boot_rom_init.vh does not match fw/boot/boot.S, run make boot-gen"; \
	    exit 1; }
	@for e in $(foreach t,$(BOOT_TESTS),'$(t)'); do \
	  IFS='|' read -r t rom pk pa <<< "$${e//\~/ }"; \
	  [[ " $(BOOT_LIST) " == *" $$t "* ]] || continue; \
	  args="+test=$$t $$pa +timeout=2000000"; n=0; \
	  IFS=',' read -ra list <<< "$$pk"; \
	  for x in "$${list[@]}"; do \
	    $(PYTHON) scripts/uart_pack.py $(BOOT_OUT)/$${x%@*} \
	      --hex $(BOOT_OUT)/$$t.$$n.hex > /dev/null || exit 1; \
	    args="$$args +pkt$$n=$(BOOT_OUT)/$$t.$$n.hex +exp$$n=$${x##*@}"; n=$$((n+1)); \
	    f=$${x%%[ @]*}; [[ $$f != *.elf ]] || args="$$args $$(cat $(BOOT_OUT)/$${f%.elf}.tohost)"; \
	  done; \
	  [ $$n != 0 ] || args="$$args +imem=$(BOOT_OUT)/hello.imem.hex"; \
	  ( $(VVP) -n $(BOOT_OUT)/tb_boot_$$rom.vvp $$args +npkt=$$n > $(BOOT_OUT)/$$t.log 2>&1 ) & \
	done; wait; \
	fail=0; for t in $(BOOT_LIST); do \
	  log=$(BOOT_OUT)/$$t.log; \
	  if grep -q '^PASS' $$log && ! grep -q '^FAIL\|^ERROR' $$log; then \
	    echo "  $$(grep '^PASS' $$log)"; \
	  else \
	    echo "  [FAIL] $$t (log: $$log)"; tail -n 20 $$log | sed 's/^/      /'; fail=1; \
	  fi; \
	done; \
	grep 'Size' rtl/mem/boot_rom_init.vh | sed 's/^\/\/ */  boot ROM: /'; \
	$(PYTHON) scripts/uart_pack.py $(BOOT_OUT)/hello.bin --pad $(BOOT_IMEM_SIZE) | \
	  sed -n 's/^uart_pack: 1 segments, /  full IMEM load: /p'; \
	if [ $$fail = 0 ]; then echo "SIM-BOOT PASS"; else echo "SIM-BOOT FAIL"; exit 1; fi

# ---------------------------------------------------------------------------
# riscv-arch-test (submodule fw/riscv-arch-test, tag 3.10.0) through RISCOF, with Spike
# as the reference model. Guide and install commands: docs/riscof.md.
#   make arch-core          RISCOF compares core signatures with Spike (needs riscof, spike)
#   make arch-core-dut      core side only: compile, run, write signatures, no compare
#                           (use when RISCOF/Spike are not installed, T=add-01 runs one)
# tb_core for arch-test is compiled with a 2 MB IMEM because jal-01 is about 1.7 MB, placed at
# 0x8000_0000 (RESET_PC follows IMEM) to match the Spike load address.
# ---------------------------------------------------------------------------
ARCH_IMEM_BASE := 80000000
ARCH_IMEM_SIZE := 2097152
ARCH_SUITE     := fw/riscv-arch-test/riscv-test-suite
ARCH_OUT       := tb/riscof/out
ARCH_CFGS      := M0W1 M1W1
# Test suites RISCOF picks for the core (RV32I/IM, Zicsr, Zifencei, no C, no
# misaligned access support): I, M, Zifencei, privilege (ecall, ebreak, 13 misalign tests).
# pmp32 is excluded because the core has only M-mode and no PMP (see docs/riscof.md).
ARCH_BASE      := $(wildcard $(ARCH_SUITE)/rv32i_m/I/src/*.S) $(wildcard $(ARCH_SUITE)/rv32i_m/Zifencei/src/*.S)
ARCH_PRIV      := $(wildcard $(ARCH_SUITE)/rv32i_m/privilege/src/*.S)
ARCH_M         := $(wildcard $(ARCH_SUITE)/rv32i_m/M/src/*.S)
ifneq ($(T),)
arch_pick       = $(foreach f,$(1),$(if $(filter $(T),$(basename $(notdir $(f)))),$(f)))
ARCH_BASE      := $(call arch_pick,$(ARCH_BASE))
ARCH_PRIV      := $(call arch_pick,$(ARCH_PRIV))
ARCH_M         := $(call arch_pick,$(ARCH_M))
endif
# <config>@<.S file>@<macro,...>, M tests run only with ENABLE_M=1
arch_runs = $(foreach f,$(ARCH_BASE),$(1)@$(f)@TEST_CASE_1=True) \
            $(foreach f,$(ARCH_PRIV),$(1)@$(f)@TEST_CASE_1=True,rvtest_mtrap_routine=True) \
            $(if $(filter M1%,$(1)),$(foreach f,$(ARCH_M),$(1)@$(f)@TEST_CASE_1=True))

$(CORE_OUT)/tb_core_arch_%.vvp: tb/core/tb_core.v tb/core/core_tb_map.vh $(CORE_RTL) $(CORE_MODELS) rtl/core/rv32_defs.vh
	@mkdir -p $(@D)
	$(IVERILOG) $(CORE_IVFLAGS) -DCORE_TB_IMEM_SIZE=$(ARCH_IMEM_SIZE) "-DCORE_TB_IMEM_BASE=32'h$(ARCH_IMEM_BASE)" -s tb_core \
	  -Ptb_core.ENABLE_M=$(call core_cfg_m,$*) -Ptb_core.ENABLE_WFI_SLEEP=$(call core_cfg_w,$*) \
	  -o $@ $(CORE_RTL) $(CORE_MODELS) tb/core/tb_core.v

.PHONY: arch-core arch-core-dut
arch-core-dut: SHELL := /bin/bash
arch-core-dut: .SHELLFLAGS := -o pipefail -c
arch-core-dut: $(foreach c,$(ARCH_CFGS),$(CORE_OUT)/tb_core_arch_$(c).vvp)
	@test -f $(ARCH_SUITE)/env/arch_test.h || { echo "ERROR: submodule missing, run: git submodule update --init --recursive"; exit 1; }
	@mkdir -p $(ARCH_OUT)
	@printf '%s\n' $(foreach c,$(ARCH_CFGS),$(call arch_runs,$(c))) | \
	  xargs -P $(CORE_JOBS) -I{} bash -c 'r={}; c=$${r%%@*}; x=$${r#*@}; f=$${x%%@*}; m=$${x#*@}; \
	    ARCH_IMEM_BASE=0x$(ARCH_IMEM_BASE) ARCH_IMEM_SIZE=$(ARCH_IMEM_SIZE) RV_PREFIX=$(RV_PREFIX) scripts/arch_run.sh $$c $$f \
	    $(CURDIR)/$(ARCH_OUT)/dut/$$c/$$(basename $$f .S) $${m//,/ }' > $(ARCH_OUT)/dut.summary || true
	@sort $(ARCH_OUT)/dut.summary; \
	pass=$$(grep -c '^  PASS' $(ARCH_OUT)/dut.summary); fail=$$(grep -c '^  \[FAIL\]' $(ARCH_OUT)/dut.summary); \
	echo "arch-core-dut: $$pass passed, $$fail failed (core side only, not compared with Spike)"; [ $$fail = 0 ]

# RISCOF picks tests from the ISA yaml of each config, runs the core and Spike, then compares signatures.
# Suite 3.10.0 also picks pmp32 from the RV32I.*Zicsr regex alone (with no PMP condition
# that the ISA yaml could exclude), so it is filtered out of the testlist first. testlist deletes and
# recreates work-dir, and run --testfile reuses
# that work-dir (it needs the checked ISA files there). HTML report in tb/riscof/out/<config>/report.html.
arch-core: $(foreach c,$(ARCH_CFGS),$(CORE_OUT)/tb_core_arch_$(c).vvp)
	@command -v riscof > /dev/null || { echo "ERROR: riscof not found, see the install commands in docs/riscof.md"; exit 1; }
	@command -v spike > /dev/null || { echo "ERROR: spike not found, see the install commands in docs/riscof.md"; exit 1; }
	@for c in $(ARCH_CFGS); do \
	  echo "== RISCOF $$c =="; \
	  (cd tb/riscof && riscof testlist --config config_$$c.ini --suite $(CURDIR)/$(ARCH_SUITE) \
	     --env $(CURDIR)/$(ARCH_SUITE)/env --work-dir $(CURDIR)/$(ARCH_OUT)/$$c) || exit 1; \
	  awk '/^[^ ]/ { skip = /\/pmp32\// } !skip' $(ARCH_OUT)/$$c/test_list.yaml > $(ARCH_OUT)/$$c.testlist.yaml; \
	  (cd tb/riscof && riscof run --config config_$$c.ini --suite $(CURDIR)/$(ARCH_SUITE) \
	     --env $(CURDIR)/$(ARCH_SUITE)/env --work-dir $(CURDIR)/$(ARCH_OUT)/$$c --no-browser \
	     --testfile $(CURDIR)/$(ARCH_OUT)/$$c.testlist.yaml) || exit 1; \
	done
	@# riscof run returns 0 even with Failed tests, so count again in report.html
	@bad=0; for c in $(ARCH_CFGS); do \
	  r=$(ARCH_OUT)/$$c/report.html; \
	  p=$$(grep -c 'col-result">Passed<' $$r); f=$$(grep -c 'col-result">Failed<' $$r); \
	  echo "arch-core $$c: $$p passed, $$f failed"; [ $$f = 0 ] || bad=1; \
	done; [ $$bad = 0 ]

# ---------------------------------------------------------------------------
# Trial synthesis with Yosys (home flow), only for area and logic depth trends.
# No GPDK45 library. Official numbers come from Genus at school.
#   make synth-core-yosys          rv32_core with ENABLE_M=0 and 1
# Results: syn/run_yosys/<label>/{stat.txt,stat_cmos.txt,ltp.txt}, summary on screen.
# ---------------------------------------------------------------------------
YOSYS ?= yosys
YS_RUN := syn/run_yosys

# $(1) label, $(2) top, $(3) source files, $(4) include, $(5) parameters
define yosys_run
	@mkdir -p $(YS_RUN)/$(1)
	@YS_TOP=$(2) YS_SRCS="$(3)" YS_INC="$(4)" YS_PARAMS="$(5)" YS_OUT=$(YS_RUN)/$(1) \
	  $(YOSYS) -q -l $(YS_RUN)/$(1)/yosys.log -c syn/yosys/synth.tcl > /dev/null
	@bash scripts/yosys_summary.sh $(1) $(YS_RUN)/$(1)
endef

.PHONY: synth-core-yosys
synth-core-yosys:
	$(call yosys_run,rv32_core_M0,rv32_core,$(CORE_RTL),rtl/core,ENABLE_M=0)
	$(call yosys_run,rv32_core_M1,rv32_core,$(CORE_RTL),rtl/core,ENABLE_M=1)

# PicoRV32 (submodule ref/picorv32, unmodified) through the same flow for a first comparison
# with rv32_core. Result table: docs/yosys_compare.md.
#   make synth-ref-yosys           3 PicoRV32 configurations
#   make synth-compare-yosys       rv32_core and PicoRV32
PICO_SRC := ref/picorv32/picorv32.v
PICO_CFG_I  := BARREL_SHIFTER=1 ENABLE_IRQ=1
PICO_CFG_IM := BARREL_SHIFTER=1 ENABLE_IRQ=1 ENABLE_FAST_MUL=1 ENABLE_DIV=1

.PHONY: synth-ref-yosys synth-compare-yosys
synth-ref-yosys:
	@test -f $(PICO_SRC) || { echo "ERROR: submodule missing, run: git submodule update --init ref/picorv32"; exit 1; }
	$(call yosys_run,picorv32_default,picorv32,$(PICO_SRC),,)
	$(call yosys_run,picorv32_I,picorv32,$(PICO_SRC),,$(PICO_CFG_I))
	$(call yosys_run,picorv32_IM,picorv32,$(PICO_SRC),,$(PICO_CFG_IM))

synth-compare-yosys: synth-core-yosys synth-ref-yosys

# Home timing estimate: Yosys maps to the open Nangate45 library and OpenSTA computes
# the critical path (ns) and F_max. Trends only, not GPDK45 numbers.
# Result table: docs/timing_core.md.
#   make sta-core-nangate          rv32_core with ENABLE_M=0 and 1, then the branch prediction
#                                  variants (docs/btb_eval.md): BTB 8 and 16 entries, static
# Results: syn/run_yosys/<label>_ng/{stat.txt,sta.txt,path_reg2reg.txt,...}
STA ?= sta
NG_LIB := syn/run_yosys/lib/NangateOpenCellLibrary_typical.lib

# $(1) label, $(2) top, $(3) source files, $(4) include, $(5) parameters
define nangate_run
	@mkdir -p $(YS_RUN)/$(1)_ng
	@rm -f $(addprefix $(YS_RUN)/$(1)_ng/,stat.txt sta.txt yosys.log sta.log)
	@YS_TOP=$(2) YS_SRCS="$(3)" YS_INC="$(4)" YS_PARAMS="$(5)" YS_OUT=$(YS_RUN)/$(1)_ng YS_LIB=$(NG_LIB) \
	  $(YOSYS) -q -l $(YS_RUN)/$(1)_ng/yosys.log -c syn/yosys/synth_nangate.tcl > /dev/null 2>&1 && \
	  test -s $(YS_RUN)/$(1)_ng/stat.txt || \
	  { echo "ERROR: yosys failed for $(1), last lines of $(YS_RUN)/$(1)_ng/yosys.log:"; \
	    tail -n 20 $(YS_RUN)/$(1)_ng/yosys.log; exit 1; }
	@YS_TOP=$(2) YS_OUT=$(YS_RUN)/$(1)_ng YS_LIB=$(NG_LIB) \
	  $(STA) -no_splash -exit syn/yosys/sta_nangate.tcl > $(YS_RUN)/$(1)_ng/sta.log 2>&1 && \
	  test -s $(YS_RUN)/$(1)_ng/sta.txt && ! grep -q '^Error' $(YS_RUN)/$(1)_ng/sta.log || \
	  { echo "ERROR: sta failed for $(1), last lines of $(YS_RUN)/$(1)_ng/sta.log:"; \
	    tail -n 20 $(YS_RUN)/$(1)_ng/sta.log; exit 1; }
	@printf '  %-14s area %s um2\n' $(1) "$$(awk '/Chip area/ {print $$NF}' $(YS_RUN)/$(1)_ng/stat.txt)"
	@sed 's/^/                 /' $(YS_RUN)/$(1)_ng/sta.txt
endef

NG_BTB16 := ENABLE_M=1 ENABLE_BTB=1 BTB_ENTRIES=16

.PHONY: sta-core-nangate
sta-core-nangate:
	@command -v $(STA) > /dev/null || { echo "ERROR: OpenSTA ($(STA)) not found, see docs/timing_core.md"; exit 1; }
	@bash scripts/get_nangate45.sh > /dev/null
	$(call nangate_run,rv32_core_M0,rv32_core,$(CORE_RTL),rtl/core,ENABLE_M=0 ENABLE_BTB=0)
	$(call nangate_run,rv32_core_M1,rv32_core,$(CORE_RTL),rtl/core,ENABLE_M=1 ENABLE_BTB=0)
	$(call nangate_run,rv32_core_M0_btb8,rv32_core,$(CORE_RTL),rtl/core,ENABLE_M=0 ENABLE_BTB=1)
	$(call nangate_run,rv32_core_M1_btb8,rv32_core,$(CORE_RTL),rtl/core,ENABLE_M=1 ENABLE_BTB=1)
	$(call nangate_run,rv32_core_M1_btb16,rv32_core,$(CORE_RTL),rtl/core,$(NG_BTB16))
	$(call nangate_run,rv32_core_M0_static,rv32_core,$(CORE_RTL),rtl/core,ENABLE_M=0 ENABLE_BTB=2)
	$(call nangate_run,rv32_core_M1_static,rv32_core,$(CORE_RTL),rtl/core,ENABLE_M=1 ENABLE_BTB=2)

# ---------------------------------------------------------------------------
# rv32_core with Cadence (Nhan), server only. Steps and criteria: docs/genus_core.md
# The netlist top is the wrapper rv32_core_syn (ENABLE_M=1, ENABLE_BTB, RESET_PC=0).
#   make synth-core                Genus, CG=1, PERIOD=20 ns, ENABLE_BTB=1 -> syn/out_core/
#   make synth-core CG=0           baseline without clock gating (rename syn/out_core first)
#   make synth-core-sweep          PERIODS="20 10 8 6 5", WNS and F_max table
#   make lec-core                  Conformal, lec/core_rtl2gate.do
#   make gls-core                  Xcelium, tb_core -DGLS with rv32ui and rv32um (SDF=auto|0|1)
# At home these targets print an ERROR line about the missing tool and stop.
# ---------------------------------------------------------------------------
# CG, PERIOD and ENABLE_BTB reach synth_core.tcl as environment variables (make puts
# command-line variables in the environment), defaults are in the script
SYN_CORE_NET := syn/out_core/rv32_core_syn_netlist.v

.PHONY: synth-core synth-core-sweep lec-core gls-core
synth-core:
	@command -v genus > /dev/null || { echo "ERROR: genus not found, synth-core runs on the school server"; exit 1; }
	rm -f $(SYN_CORE_NET)
	mkdir -p syn/run_core && cd syn/run_core && rm -f genus.log* genus.cmd* && \
	  genus -batch -files ../scripts/synth_core.tcl -log genus.log
	@test -f $(SYN_CORE_NET) || { echo "ERROR: Genus produced no netlist, see syn/run_core/genus.log"; exit 1; }
	@cat syn/out_core/reports/synthesis/run_info.txt

synth-core-sweep:
	bash syn/scripts/sweep_core.sh

# < /dev/null so Conformal exits if the dofile stops midway
lec-core:
	@command -v lec > /dev/null || { echo "ERROR: lec (Conformal) not found, lec-core runs on the school server"; exit 1; }
	@test -f $(SYN_CORE_NET) || { echo "ERROR: no netlist yet, run make synth-core first"; exit 1; }
	mkdir -p syn/out_core/reports
	lec -nogui -dofile lec/core_rtl2gate.do < /dev/null > syn/out_core/lec.txt 2>&1 || true
	@grep -E 'Compare Results|Non-equivalent|Equivalent|Abort|// Error' syn/out_core/lec.txt | tail -12

gls-core:
	@bash scripts/gls_core.sh

# ---------------------------------------------------------------------------
# Bus and memories (Phat): RTL-03 rtl/bus, RTL-08 rtl/mem. Docs: docs/bus_mem.md
# Runs at home (Icarus, Verilator). Results in tb/unit/out/bus and tb/soc/out (ignored).
#   make lint-bus                  Verilator -Wall on each module in rtl/bus, rtl/mem, 0 warnings
#   make unit-bus                  tb_sys_bus, tb_apb_bridge, tb_sram_wrap, tb_imem_port (TB=tb_sys_bus runs one)
#   make fw-bus                    the core runs assembly tests and riscv-tests on sys_bus + SRAM macros (T=smoke)
#   make unit-bus PLUSARGS="+seed=7"
# ---------------------------------------------------------------------------
# soc_top needs the core, peripherals and accelerator, so it is linted and run in the SoC part
BUS_RTL     := $(filter-out rtl/bus/soc_top.v,$(wildcard rtl/bus/*.v)) $(wildcard rtl/mem/*.v)
BUS_MODELS  := tb/models/sram_2k_macro.v
BUS_ACCEL   := $(ACCEL_RTL) rtl/accel/accel_apb.v
BUS_OUT     := tb/unit/out/bus
BUS_SOC_OUT := tb/soc/out
BUS_IVFLAGS := -g2012 -Wall -Irtl/bus -Irtl/mem
BUS_VLFLAGS := --lint-only -Wall -Irtl/bus -Irtl/mem -y rtl/bus -y rtl/mem -y tb/models

lint-bus unit-bus fw-bus: SHELL := /bin/bash
lint-bus unit-bus fw-bus: .SHELLFLAGS := -o pipefail -c

# Parameter sets, same convention as the core part: runs separated by spaces, NAME=VALUE by commas
BUS_LINT_CFG_sys_bus    := N_MASTER=1 N_MASTER=2 N_MASTER=4
BUS_LINT_CFG_sram_array := BANK_W=0 BANK_W=2
BUS_LINT_CFG_sram_wrap  := BANK_W=0 BANK_W=2
BUS_LINT_CFG_imem_port  := BANK_W=0 BANK_W=2
BUS_UNIT_CFG_tb_sys_bus    := N_MASTER=1 N_MASTER=2
BUS_UNIT_CFG_tb_sram_wrap  := BANK_W=0 BANK_W=2
BUS_UNIT_CFG_tb_imem_port  := BANK_W=0 BANK_W=2
bus_cfgs = $(or $(BUS_LINT_CFG_$(1)),$(BUS_UNIT_CFG_$(1)),default)

BUS_LINT_RUNS := $(foreach f,$(BUS_RTL),$(foreach c,$(call bus_cfgs,$(basename $(notdir $(f)))),$(f)@$(c)))
BUS_UNIT_TBS  := tb_sys_bus tb_apb_bridge tb_sram_wrap tb_imem_port tb_dma_apb
BUS_UNIT_RUNS := $(foreach t,$(BUS_UNIT_TBS),$(foreach c,$(call bus_cfgs,$(t)),$(t)@$(c)))
ifneq ($(TB),)
BUS_UNIT_RUNS := $(filter $(TB)@%,$(BUS_UNIT_RUNS))
endif

.PHONY: lint-bus unit-bus fw-bus clean-bus

lint-bus:
	@fail=0; \
	for run in $(BUS_LINT_RUNS); do \
	  f=$${run%%@*}; m=$$(basename $$f .v); cfg=$${run#*@}; gflags=""; \
	  if [ "$$cfg" != default ]; then for kv in $${cfg//,/ }; do gflags="$$gflags -G$$kv"; done; fi; \
	  if $(VERILATOR) $(BUS_VLFLAGS) --top-module $$m $$gflags $$f; then \
	    echo "  [ OK ] lint $$m ($$cfg)"; \
	  else \
	    echo "  [FAIL] lint $$m ($$cfg)"; fail=1; \
	  fi; \
	done; \
	if [ $$fail = 0 ]; then echo "LINT-BUS PASS"; else echo "LINT-BUS FAIL"; exit 1; fi

# A testbench passes when the log has a line starting with PASS and no FAIL line.
unit-bus:
	@mkdir -p $(BUS_OUT); pass=0; fail=0; \
	for run in $(BUS_UNIT_RUNS); do \
	  tb=$${run%%@*}; cfg=$${run#*@}; pflags=""; tag=$$tb; \
	  if [ "$$cfg" != default ]; then \
	    for kv in $${cfg//,/ }; do pflags="$$pflags -P$$tb.$$kv"; done; \
	    tag="$${tb}_$${cfg//[=,]/_}"; \
	  fi; \
	  log=$(BUS_OUT)/$$tag.log; \
	  if $(IVERILOG) $(BUS_IVFLAGS) -s $$tb $$pflags -o $(BUS_OUT)/$$tag.vvp \
	       $(BUS_RTL) $(BUS_MODELS) $(BUS_ACCEL) tb/unit/$$tb.v > $$log 2>&1 && \
	     $(VVP) -n $(BUS_OUT)/$$tag.vvp $(PLUSARGS) >> $$log 2>&1 && \
	     grep -q '^PASS' $$log && ! grep -q '^FAIL' $$log; then \
	    pass=$$((pass+1)); echo "  $$(grep '^PASS' $$log | tail -n 1)"; \
	  else \
	    fail=$$((fail+1)); echo "  [FAIL] $$tag (log: $$log)"; tail -n 20 $$log; \
	  fi; \
	done; \
	echo "UNIT-BUS: $$pass passed, $$fail failed"; [ $$fail = 0 ]

# Core on the real bus: assembly tests that do not use the tb_core control block
# (irq, trap, wfi, muldiv need it), the bus tests in fw/tests/bus, and riscv-tests
# as in isa-core. Reuses the core elf2hex rule.
BUS_FW_TESTS  := smoke hazard
BUS_OWN_TESTS := $(basename $(notdir $(wildcard fw/tests/bus/*.S)))
BUS_OWN_OUT   := $(BUS_SOC_OUT)/fw
ifneq ($(T),)
BUS_FW_TESTS  := $(filter $(T),$(BUS_FW_TESTS))
BUS_OWN_TESTS := $(filter $(T),$(BUS_OWN_TESTS))
endif
BUS_FW_CFGS  := M0W0 M1W1
bus_tests = $(addprefix $(CORE_FW_OUT)/,$(BUS_FW_TESTS)) \
            $(addprefix $(BUS_OWN_OUT)/,$(BUS_OWN_TESTS)) \
            $(addprefix $(CORE_ISA_OUT)/,$(call core_isa_tests,$(1)))

.PRECIOUS: $(BUS_OWN_OUT)/%.elf
$(BUS_OWN_OUT)/%.elf: fw/tests/bus/%.S fw/tests/asm/test_macros.h fw/common/link.ld
	@mkdir -p $(@D)
	@test -n "$(RV_PREFIX)" || { echo "ERROR: riscv gcc not found"; exit 1; }
	$(RV_PREFIX)-gcc $(CORE_RV_ASFLAGS) -o $@ $<

$(BUS_OWN_OUT)/%.tohost: $(BUS_OWN_OUT)/%.elf scripts/elf2hex.py tb/core/core_tb_map.vh
	@$(PYTHON) scripts/elf2hex.py $< --imem $(BUS_OWN_OUT)/$*.imem.hex --dmem $(BUS_OWN_OUT)/$*.dmem.hex > $@
BUS_FW_RUNS  := $(foreach c,$(BUS_FW_CFGS),$(foreach t,$(call bus_tests,$(c)),$(t)@$(c)))

$(BUS_SOC_OUT)/tb_core_bus_%.vvp: tb/soc/tb_core_bus.v $(BUS_RTL) $(BUS_MODELS) $(BUS_ACCEL) $(CORE_RTL) rtl/core/rv32_defs.vh
	@mkdir -p $(@D)
	$(IVERILOG) $(BUS_IVFLAGS) -Irtl/core -s tb_core_bus -Ptb_core_bus.ENABLE_M=$(call core_cfg_m,$*) \
	  -Ptb_core_bus.ENABLE_WFI_SLEEP=$(call core_cfg_w,$*) -o $@ \
	  $(CORE_RTL) $(BUS_RTL) $(BUS_MODELS) $(BUS_ACCEL) tb/soc/tb_core_bus.v

fw-bus: $(foreach c,$(BUS_FW_CFGS),$(BUS_SOC_OUT)/tb_core_bus_$(c).vvp) \
        $(foreach t,$(BUS_FW_TESTS),$(CORE_FW_OUT)/$(t).tohost) \
        $(foreach t,$(BUS_OWN_TESTS),$(BUS_OWN_OUT)/$(t).tohost) \
        $(foreach t,$(CORE_ISA_BASE) $(CORE_ISA_M),$(CORE_ISA_OUT)/$(t).tohost)
	@printf '%s\n' $(BUS_FW_RUNS) | xargs -P $(CORE_JOBS) -n 1 bash scripts/bus_run.sh $(BUS_SOC_OUT) \
	  > $(BUS_SOC_OUT)/fw-bus.summary; \
	cat $(BUS_SOC_OUT)/fw-bus.summary; \
	pass=$$(grep -c '^  PASS' $(BUS_SOC_OUT)/fw-bus.summary); \
	fail=$$(grep -c '^  \[FAIL\]' $(BUS_SOC_OUT)/fw-bus.summary); \
	echo "fw-bus: $$pass passed, $$fail failed"; [ $$fail = 0 ] && [ $$pass -gt 0 ]

clean-bus:
	rm -rf $(BUS_OUT) $(BUS_SOC_OUT)

# ---------------------------------------------------------------------------
# Peripherals (Phuc): RTL-04 timer_apb, gpio_apb, RTL-10 uart_apb, RTL-11 irqc_apb.
# Unit tests for VER-02. Runs at home (Icarus). Results in tb/unit/out/periph (ignored).
#   make unit-periph               tb_timer_apb, tb_gpio_apb, tb_uart_apb, tb_irqc_apb (TB=tb_uart_apb runs one)
#   make unit-periph PLUSARGS="+seed=7"
# The peripherals are linted inside soc_top by make lint-soc.
# ---------------------------------------------------------------------------
PERIPH_RTL      := $(wildcard rtl/periph/*.v)
PERIPH_OUT      := tb/unit/out/periph
PERIPH_IVFLAGS  := -g2012 -Wall
PERIPH_UNIT_TBS := tb_timer_apb tb_gpio_apb tb_uart_apb tb_irqc_apb
ifneq ($(TB),)
PERIPH_UNIT_TBS := $(filter $(TB),$(PERIPH_UNIT_TBS))
endif

unit-periph: SHELL := /bin/bash
unit-periph: .SHELLFLAGS := -o pipefail -c

.PHONY: unit-periph clean-periph

# Same pass rule as unit-bus: the log has a line starting with PASS and no FAIL line.
# A TB name that matches nothing fails instead of passing with 0 runs.
unit-periph:
	@mkdir -p $(PERIPH_OUT); pass=0; fail=0; \
	for tb in $(PERIPH_UNIT_TBS); do \
	  log=$(PERIPH_OUT)/$$tb.log; \
	  if $(IVERILOG) $(PERIPH_IVFLAGS) -s $$tb -o $(PERIPH_OUT)/$$tb.vvp \
	       $(PERIPH_RTL) tb/unit/$$tb.v > $$log 2>&1 && \
	     $(VVP) -n $(PERIPH_OUT)/$$tb.vvp $(PLUSARGS) >> $$log 2>&1 && \
	     grep -q '^PASS' $$log && ! grep -q '^FAIL' $$log; then \
	    pass=$$((pass+1)); echo "  $$(grep '^PASS' $$log | tail -n 1)"; \
	  else \
	    fail=$$((fail+1)); echo "  [FAIL] $$tb (log: $$log)"; tail -n 20 $$log; \
	  fi; \
	done; \
	echo "UNIT-PERIPH: $$pass passed, $$fail failed"; [ $$fail = 0 ] && [ $$pass -gt 0 ]

clean-periph:
	rm -rf $(PERIPH_OUT)

# ---------------------------------------------------------------------------
# SoC (Phat): RTL-09 rtl/bus/soc_top.v, rtl/bus/reset_sync.v, RTL-15 rtl/bus/dma_apb.v.
# Docs: docs/soc_top.md. Runs at home (Icarus, Verilator). Results in tb/soc/out/soc (ignored).
#   make lint-soc                  Verilator -Wall on soc_top (ENABLE_M x ENABLE_WFI_SLEEP x ENABLE_DMA),
#                                  0 warnings
#   make fw-soc                    soc_top runs smoke, hazard, soc.S, bus.S, dma.S and riscv-tests
#                                  (T=soc runs one). M1W1 is built with ENABLE_DMA=1, M0W0 without
# ---------------------------------------------------------------------------
SOC_RTL     := $(CORE_RTL) $(wildcard rtl/bus/*.v) $(wildcard rtl/mem/*.v) $(wildcard rtl/periph/*.v) $(BUS_ACCEL)
SOC_OUT     := tb/soc/out/soc
SOC_VLFLAGS := --lint-only -Wall -Irtl/bus -Irtl/mem -Irtl/core \
               -y rtl/bus -y rtl/mem -y rtl/core -y rtl/periph -y rtl/accel -y tb/models
SOC_LINT_CFGS := M0W0 M0W1 M1W0 M1W1
SOC_LINT_DMA  := 0 1

lint-soc fw-soc: SHELL := /bin/bash
lint-soc fw-soc: .SHELLFLAGS := -o pipefail -c

.PHONY: lint-soc fw-soc clean-soc

lint-soc:
	@fail=0; \
	for c in $(SOC_LINT_CFGS); do for d in $(SOC_LINT_DMA); do \
	  m=$${c:1:1}; w=$${c:3:1}; \
	  if $(VERILATOR) $(SOC_VLFLAGS) --top-module soc_top -GENABLE_M=$$m -GENABLE_WFI_SLEEP=$$w \
	       -GENABLE_DMA=$$d rtl/bus/soc_top.v; then \
	    echo "  [ OK ] lint soc_top ($$c, ENABLE_DMA=$$d)"; \
	  else \
	    echo "  [FAIL] lint soc_top ($$c, ENABLE_DMA=$$d)"; fail=1; \
	  fi; \
	done; done; \
	if [ $$fail = 0 ]; then echo "LINT-SOC PASS"; else echo "LINT-SOC FAIL"; exit 1; fi

# Assembly tests that do not use the tb_core control block, the SoC tests in
# fw/tests/soc, bus.S (reuses the bus rule) and riscv-tests.
SOC_FW_TESTS  := smoke hazard
SOC_DMA_TESTS := dma
SOC_OWN_TESTS := $(filter-out $(SOC_DMA_TESTS),$(basename $(notdir $(wildcard fw/tests/soc/*.S))))
SOC_OWN_OUT   := $(SOC_OUT)/fw
ifneq ($(T),)
SOC_FW_TESTS  := $(filter $(T),$(SOC_FW_TESTS))
SOC_OWN_TESTS := $(filter $(T),$(SOC_OWN_TESTS))
SOC_DMA_TESTS := $(filter $(T),$(SOC_DMA_TESTS))
endif
SOC_FW_CFGS   := M0W0 M1W1
SOC_DMA_CFGS  := M1W1                # Configs built with ENABLE_DMA=1, dma.S runs only there
soc_cfg_d = $(if $(filter $(1),$(SOC_DMA_CFGS)),1,0)
soc_tests = $(addprefix $(CORE_FW_OUT)/,$(SOC_FW_TESTS)) \
            $(addprefix $(SOC_OWN_OUT)/,$(SOC_OWN_TESTS)) \
            $(if $(filter 1,$(call soc_cfg_d,$(1))),$(addprefix $(SOC_OWN_OUT)/,$(SOC_DMA_TESTS))) \
            $(addprefix $(BUS_OWN_OUT)/,$(BUS_OWN_TESTS)) \
            $(addprefix $(CORE_ISA_OUT)/,$(call core_isa_tests,$(1)))
SOC_FW_RUNS   := $(foreach c,$(SOC_FW_CFGS),$(foreach t,$(call soc_tests,$(c)),$(t)@$(c)))

.PRECIOUS: $(SOC_OWN_OUT)/%.elf
$(SOC_OWN_OUT)/%.elf: fw/tests/soc/%.S fw/tests/asm/test_macros.h fw/common/link.ld
	@mkdir -p $(@D)
	@test -n "$(RV_PREFIX)" || { echo "ERROR: riscv gcc not found"; exit 1; }
	$(RV_PREFIX)-gcc $(CORE_RV_ASFLAGS) -o $@ $<

$(SOC_OWN_OUT)/%.tohost: $(SOC_OWN_OUT)/%.elf scripts/elf2hex.py tb/core/core_tb_map.vh
	@$(PYTHON) scripts/elf2hex.py $< --imem $(SOC_OWN_OUT)/$*.imem.hex --dmem $(SOC_OWN_OUT)/$*.dmem.hex > $@

$(SOC_OUT)/tb_soc_%.vvp: tb/soc/tb_soc.v $(SOC_RTL) $(BUS_MODELS) rtl/core/rv32_defs.vh rtl/bus/soc_map.vh
	@mkdir -p $(@D)
	$(IVERILOG) $(BUS_IVFLAGS) -Irtl/core -s tb_soc -Ptb_soc.ENABLE_M=$(call core_cfg_m,$*) \
	  -Ptb_soc.ENABLE_WFI_SLEEP=$(call core_cfg_w,$*) -Ptb_soc.ENABLE_DMA=$(call soc_cfg_d,$*) \
	  -o $@ $(SOC_RTL) $(BUS_MODELS) tb/soc/tb_soc.v

fw-soc: $(foreach c,$(SOC_FW_CFGS),$(SOC_OUT)/tb_soc_$(c).vvp) \
        $(foreach t,$(SOC_FW_TESTS),$(CORE_FW_OUT)/$(t).tohost) \
        $(foreach t,$(SOC_OWN_TESTS) $(SOC_DMA_TESTS),$(SOC_OWN_OUT)/$(t).tohost) \
        $(foreach t,$(BUS_OWN_TESTS),$(BUS_OWN_OUT)/$(t).tohost) \
        $(foreach t,$(CORE_ISA_BASE) $(CORE_ISA_M),$(CORE_ISA_OUT)/$(t).tohost)
	@printf '%s\n' $(SOC_FW_RUNS) | xargs -P $(CORE_JOBS) -n 1 bash scripts/soc_run.sh $(SOC_OUT) \
	  > $(SOC_OUT)/fw-soc.summary; \
	cat $(SOC_OUT)/fw-soc.summary; \
	pass=$$(grep -c '^  PASS' $(SOC_OUT)/fw-soc.summary); \
	fail=$$(grep -c '^  \[FAIL\]' $(SOC_OUT)/fw-soc.summary); \
	echo "fw-soc: $$pass passed, $$fail failed"; [ $$fail = 0 ] && [ $$pass -gt 0 ]

clean-soc:
	rm -rf $(SOC_OUT)

# ---------------------------------------------------------------------------
# Genus trial synthesis of each SoC block (Phat, STA-02). Runs ON THE SCHOOL SERVER only.
# Scan flops are forbidden: SDFF* gets dont_use and the netlist is checked for SDFF* cells.
# Results in syn/out_blocks/<block>/ (netlist, block SDC, reports/, summary.txt), logs in
# syn/run_blocks/<block>/genus.log. Both folders are ignored. Docs: docs/sta_results.md.
#   make synth-block B=sys_bus     one block (CG=0 for the run without clock gating)
#   make synth-blocks              every block in SYN_BLOCKS, then prints syn/out_blocks/summary.txt
#   make synth-block B=sram_wrap1  sram_wrap with 1 macro, to practice the macro flow
# ---------------------------------------------------------------------------
# Must match the block table in syn/scripts/synth_block.tcl (the table also has sram_wrap1)
# rv32_core is synthesized by make synth-core (Nhan, docs/genus_core.md), not here
SYN_BLOCKS := sys_bus apb_bridge dma_apb imem_port sram_wrap \
              timer_apb uart_apb gpio_apb irqc_apb accel_apb
B ?=

.PHONY: synth-block synth-blocks

synth-block:
	@test -n "$(B)" || { echo "ERROR: set B=<block>, one of: $(SYN_BLOCKS)"; exit 1; }
	@command -v genus > /dev/null || \
	  { echo "ERROR: genus not found, this target runs on the school server"; exit 1; }
	rm -f syn/out_blocks/$(B)/$(B)_netlist.v syn/out_blocks/$(B)/summary.txt
	mkdir -p syn/run_blocks/$(B)
	cd syn/run_blocks/$(B) && rm -f genus.log* genus.cmd* && \
	  BLOCK=$(B) genus -batch -files ../../scripts/synth_block.tcl -log genus.log \
	    > /dev/null 2>&1 || true
	@test -f syn/out_blocks/$(B)/$(B)_netlist.v || \
	  { echo "ERROR: Genus produced no netlist for $(B), see syn/run_blocks/$(B)/genus.log"; exit 1; }
	@grep -q 'scan_flops=0 ' syn/out_blocks/$(B)/summary.txt || \
	  { echo "ERROR: scan flops in $(B), see syn/out_blocks/$(B)/summary.txt"; exit 1; }
	@cat syn/out_blocks/$(B)/summary.txt

# Keeps going after a failing block so one run of the server session covers every block
synth-blocks:
	@fail=0; \
	for b in $(SYN_BLOCKS); do \
	  echo "== $$b"; $(MAKE) --no-print-directory synth-block B=$$b || fail=1; \
	done; \
	cat syn/out_blocks/*/summary.txt > syn/out_blocks/summary.txt 2>/dev/null; \
	echo "== summary (syn/out_blocks/summary.txt)"; cat syn/out_blocks/summary.txt; \
	[ $$fail = 0 ]

# ---------------------------------------------------------------------------
# Genus synthesis of the whole soc_top with syn/constraints/soc.sdc (Phat). Runs ON THE SCHOOL
# SERVER only. Same scan flop ban as synth-block, and the netlist must hold 8 sram_2k_macro.
# Results in syn/out_soc/ (soc_top_netlist.v, soc_top_synth.sdc, reports/, summary.txt), log in
# syn/run_soc/genus.log. The netlist feeds pnr/scripts/soc_floorplan.tcl (PD-02, PD-03).
#   make synth-soc                 CG=1 (CG=0 for the baseline, rename syn/out_soc first),
#                                  PERIOD=20 ns (replaces SOC_PERIOD of soc.sdc for this run)
#   make synth-soc-sweep           PERIODS="20 18 16 15 14", WNS and F_max table (STA-03)
#   make sta-soc                   Tempus on syn/out_soc: setup, hold, recovery, removal (STA-03)
#                                  SPEF=<file> NETLIST=<file> for the routed design (STA-05)
#   make sta-soc-nangate           AT HOME: Yosys + OpenSTA with Nangate45 and soc.sdc, trends
#                                  only (STA_PERIOD=20). Synthesis takes about 11 minutes and
#                                  reruns only when the RTL changes
# ---------------------------------------------------------------------------
SYN_SOC_NET := syn/out_soc/soc_top_netlist.v

.PHONY: synth-soc synth-soc-sweep sta-soc sta-soc-nangate
synth-soc:
	@command -v genus > /dev/null || \
	  { echo "ERROR: genus not found, this target runs on the school server"; exit 1; }
	rm -f $(SYN_SOC_NET) syn/out_soc/summary.txt
	mkdir -p syn/run_soc && cd syn/run_soc && rm -f genus.log* genus.cmd* && \
	  genus -batch -files ../scripts/synth_soc.tcl -log genus.log
	@test -f $(SYN_SOC_NET) || \
	  { echo "ERROR: Genus produced no netlist, see syn/run_soc/genus.log"; exit 1; }
	@grep -q 'macros=8 scan_flops=0 ' syn/out_soc/summary.txt || \
	  { echo "ERROR: wrong macro count or scan flops, see syn/out_soc/summary.txt"; exit 1; }
	@cat syn/out_soc/summary.txt

# Results in syn/out_soc_sweep/p<period>/ and syn/out_soc_sweep/summary.md
synth-soc-sweep:
	bash syn/scripts/sweep_soc.sh

# Reports in sta/run_soc/pre/ (or sta/run_soc/spef/ with SPEF), log in sta/run_soc/tempus.log.
# < /dev/null so Tempus exits if the script stops midway
sta-soc:
	@command -v tempus > /dev/null || \
	  { echo "ERROR: tempus not found, this target runs on the school server"; exit 1; }
	mkdir -p sta/run_soc && cd sta/run_soc && rm -f tempus.log* tempus.cmd* && \
	  tempus -nowin -files ../scripts/sta_soc.tcl -log tempus.log < /dev/null > /dev/null 2>&1 || true
	@f=sta/run_soc/$$( [ -n "$(SPEF)" ] && echo spef || echo pre )/summary.txt; \
	  test -f $$f || { echo "ERROR: Tempus wrote no summary, see sta/run_soc/tempus.log"; exit 1; }; \
	  cat $$f

# Home trend run of the whole soc_top. The 8 SRAM macros are black boxes (no Nangate45 .lib),
# so paths through them are not timed. Results in syn/run_yosys/soc_top_ng/sta_p<period>/
SOC_NG_DIR := $(YS_RUN)/soc_top_ng
SOC_NG_NET := $(SOC_NG_DIR)/soc_top_nangate.v
SOC_NG_SRC := $(SOC_RTL) syn/yosys/sram_2k_macro_bb.v
STA_PERIOD ?= 20

$(SOC_NG_NET): $(SOC_NG_SRC) rtl/core/rv32_defs.vh rtl/bus/soc_map.vh rtl/mem/boot_rom_init.vh \
               syn/yosys/synth_nangate.tcl
	@bash scripts/get_nangate45.sh > /dev/null
	@mkdir -p $(SOC_NG_DIR)
	@echo "sta-soc-nangate: Yosys synthesis of soc_top (about 11 minutes)"
	@YS_TOP=soc_top YS_SRCS="$(SOC_NG_SRC)" YS_INC="rtl/core rtl/bus rtl/mem" YS_PARAMS="" \
	  YS_OUT=$(SOC_NG_DIR) YS_LIB=$(NG_LIB) nice -n 19 \
	  $(YOSYS) -q -l $(SOC_NG_DIR)/yosys.log -c syn/yosys/synth_nangate.tcl > /dev/null 2>&1 && \
	  test -s $(SOC_NG_NET) || \
	  { echo "ERROR: yosys failed for soc_top, see $(SOC_NG_DIR)/yosys.log"; \
	    rm -f $(SOC_NG_NET); exit 1; }

sta-soc-nangate: $(SOC_NG_NET)
	@command -v $(STA) > /dev/null || { echo "ERROR: OpenSTA ($(STA)) not found"; exit 1; }
	@YS_OUT=$(SOC_NG_DIR) YS_LIB=$(NG_LIB) STA_PERIOD=$(STA_PERIOD) \
	  $(STA) -no_splash -exit syn/yosys/sta_soc_nangate.tcl > $(SOC_NG_DIR)/sta.log 2>&1 && \
	  test -s $(SOC_NG_DIR)/sta_p$(STA_PERIOD)/summary.txt || \
	  { echo "ERROR: sta failed for soc_top, see $(SOC_NG_DIR)/sta.log"; exit 1; }
	@cat $(SOC_NG_DIR)/sta_p$(STA_PERIOD)/summary.txt
