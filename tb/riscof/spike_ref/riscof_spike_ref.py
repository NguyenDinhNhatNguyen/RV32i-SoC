# riscof_spike_ref.py - RISCOF plugin that uses Spike as the reference model.
# Based on riscof-plugins/rv32/spike_simple from riscv-arch-test, except that the
# gcc prefix can change (prefix key, default riscv64-unknown-elf) and it reuses the
# spike_simple env (model_test.h, link.ld) from the submodule.
import os
import logging

import riscof.utils as utils
from riscof.pluginTemplate import pluginTemplate

logger = logging.getLogger()

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SPIKE_ENV = os.path.join(ROOT, "fw", "riscv-arch-test", "riscof-plugins", "rv32", "spike_simple", "env")


class spike_ref(pluginTemplate):
    __model__ = "spike"
    __version__ = "XXX"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        config = kwargs.get("config")
        if config is None:
            print("Please enter input file paths in configuration.")
            raise SystemExit(1)
        self.spike = os.path.join(config.get("PATH", ""), "spike")
        self.prefix = config.get("prefix", "riscv64-unknown-elf")
        self.num_jobs = str(config.get("jobs", 1))
        self.pluginpath = os.path.abspath(config["pluginpath"])

    def initialise(self, suite, work_dir, archtest_env):
        self.work_dir = work_dir
        self.suite_dir = suite
        self.compile_cmd = (self.prefix + "-gcc -march={0} -mabi=ilp32 -static -mcmodel=medany"
                            " -fvisibility=hidden -nostdlib -nostartfiles -g"
                            " -T " + SPIKE_ENV + "/link.ld -I " + SPIKE_ENV +
                            " -I " + archtest_env + " {1} -o {2} {3}")

    def build(self, isa_yaml, platform_yaml):
        # Spike ISA from the DUT ISA yaml
        ispec = utils.load_yaml(isa_yaml)["hart0"]
        self.isa = "rv32i"
        if "M" in ispec["ISA"]:
            self.isa += "m"
        self.isa += "_zicsr_zifencei"

    def runTests(self, testList):
        mk = os.path.join(self.work_dir, "Makefile." + self.name[:-1])
        if os.path.exists(mk):
            os.remove(mk)
        make = utils.makeUtil(makefilePath=mk)
        make.makeCommand = "make -k -j" + self.num_jobs
        for testname in testList:
            entry = testList[testname]
            test_dir = entry["work_dir"]
            sig = os.path.join(test_dir, self.name[:-1] + ".signature")
            macros = " -D" + " -D".join(entry["macros"])
            cmd = self.compile_cmd.format(entry["isa"].lower(), entry["test_path"], "ref.elf", macros)
            sim = "{0} --isa={1} +signature={2} +signature-granularity=4 ref.elf".format(
                self.spike, self.isa, sig)
            make.add_target("@cd {0}; {1}; {2};".format(test_dir, cmd, sim))
        make.execute_all(self.work_dir)
