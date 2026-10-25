# riscof_rv32_core.py - RISCOF plugin for rv32_core running on tb_core (Icarus).
# Compiling and running each test is done by scripts/arch_run.sh (shared with
# make arch-core-dut). The tb_core configuration (M0W1/M1W1) comes from the tb_cfg key
# in config.ini.
import os
import logging

import riscof.utils as utils
from riscof.pluginTemplate import pluginTemplate

logger = logging.getLogger()

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


class rv32_core(pluginTemplate):
    __model__ = "rv32_core"
    __version__ = "0.1"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        config = kwargs.get("config")
        if config is None:
            print("Please enter input file paths in configuration.")
            raise SystemExit(1)
        self.num_jobs = str(config.get("jobs", 1))
        self.pluginpath = os.path.abspath(config["pluginpath"])
        self.isa_spec = os.path.abspath(config["ispec"])
        self.platform_spec = os.path.abspath(config["pspec"])
        self.tb_cfg = config.get("tb_cfg", "M1W1")
        self.target_run = config.get("target_run", "1") != "0"

    def initialise(self, suite, work_dir, archtest_env):
        self.work_dir = work_dir
        self.suite_dir = suite

    def build(self, isa_yaml, platform_yaml):
        # tb_core with a 2 MB IMEM, compiled once for the whole suite
        vvp = "tb/core/out/tb_core_arch_{0}.vvp".format(self.tb_cfg)
        utils.shellCommand("make -C {0} {1}".format(ROOT, vvp)).run()

    def runTests(self, testList):
        mk = os.path.join(self.work_dir, "Makefile." + self.name[:-1])
        if os.path.exists(mk):
            os.remove(mk)
        make = utils.makeUtil(makefilePath=mk)
        make.makeCommand = "make -k -j" + self.num_jobs
        run = os.path.join(ROOT, "scripts", "arch_run.sh")
        sig = self.name[:-1] + ".signature"
        for testname in testList:
            entry = testList[testname]
            test_dir = entry["work_dir"]
            if self.target_run:
                cmd = "{0} {1} {2} {3} {4}".format(run, self.tb_cfg, entry["test_path"], test_dir,
                                                   " ".join(entry["macros"]))
                # arch_run.sh always writes DUT-rv32_core.signature
                if sig != "DUT-rv32_core.signature":
                    cmd += "; mv DUT-rv32_core.signature " + sig
            else:
                cmd = 'echo "NO RUN"'
            make.add_target("@cd {0}; {1}".format(test_dir, cmd))
        make.execute_all(self.work_dir)
        if not self.target_run:
            raise SystemExit(0)
