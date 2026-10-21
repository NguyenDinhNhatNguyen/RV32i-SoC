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
