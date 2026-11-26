# Power soc_top before layout (PWR-01)

Netlist /home/s23521043/RV32i-SoC/syn/out_soc/soc_top_netlist.v, Genus, slow corner, clock 10 ns. Power in mW, energy in uJ.

| Case | Activity | Cycles | Leakage | Internal | Switching | Total | Energy |
|------|----------|-------:|--------:|---------:|----------:|------:|-------:|
| default | default |  | 0.0109 | 0.5463 | 0.1787 | 0.7359 |  |
| accel_bench_rv32im | SAIF | 162595 | 0.0192 | 0.2965 | 0.1088 | 0.4245 | 0.6902 |
| coremark_rv32im | SAIF | 1040707 | 0.0197 | 0.3126 | 0.1235 | 0.4557 | 4.7428 |
| dhrystone_rv32im | SAIF | 378275 | 0.0205 | 0.2824 | 0.1060 | 0.4090 | 1.5471 |
| dma | SAIF | 12539 | 0.0189 | 0.2685 | 0.0952 | 0.3826 | 0.0480 |
| i2c | SAIF | 1503 | 0.0180 | 0.2337 | 0.0696 | 0.3214 | 0.0048 |
| soc | SAIF | 2458 | 0.0173 | 0.2230 | 0.0656 | 0.3060 | 0.0075 |
| soc_fw_rv32im | SAIF | 247980 | 0.0183 | 0.3287 | 0.1306 | 0.4776 | 1.1844 |
| spi_pwm | SAIF | 2606 | 0.0181 | 0.2600 | 0.0803 | 0.3584 | 0.0093 |
