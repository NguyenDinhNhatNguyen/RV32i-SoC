# Điểm vào chung. Các target Cadence chỉ chạy trên server trường.
IVERILOG ?= iverilog
VVP      ?= vvp

ACCEL_RTL = rtl/accel/sa_core_model.v rtl/accel/accel_wrapper.v
ACCEL_TB  = tb/unit/tb_accel_wrapper.v

.PHONY: help sim-accel lint-accel synth-accel pnr-accel check-server clean

help:
	@echo "make sim-accel     - mô phỏng wrapper accelerator (Icarus, chạy ở nhà)"
	@echo "make lint-accel    - lint wrapper bằng Verilator nếu có"
	@echo "make check-server  - kiểm tra thư viện/tool trên server trường"
	@echo "make synth-accel   - Genus tổng hợp accelerator (server); CG=0 để chạy baseline"
	@echo "make pnr-accel     - Innovus chạy thử accelerator (server)"

sim-accel:
	@mkdir -p tb/unit/out
	$(IVERILOG) -g2005 -Wall -o tb/unit/out/accel.vvp $(ACCEL_RTL) $(ACCEL_TB)
	$(VVP) -n tb/unit/out/accel.vvp

lint-accel:
	verilator --lint-only -Wall $(ACCEL_RTL) --top-module accel_wrapper

check-server:
	bash scripts/check_server.sh

synth-accel:
	cd syn && mkdir -p run_accel && cd run_accel && genus -batch -files ../scripts/synth_accel.tcl -log genus.log

pnr-accel:
	cd pnr && mkdir -p run_accel && cd run_accel && innovus -batch -files ../scripts/run_all.tcl -log innovus.log

clean:
	rm -rf tb/unit/out syn/run* pnr/run*
