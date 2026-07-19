# Project-level Verilator/CoreMark flow.
# Run from WSL/Linux in this directory:
#   make sim
#   make clean

PROJECT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SOURCE_DIR := $(PROJECT_DIR)/source
COREMARK_DIR := $(PROJECT_DIR)/coremark
TESTBENCH_DIR := $(PROJECT_DIR)/testbench
TEST_DIR := $(PROJECT_DIR)/test
CSR_SMOKE_DIR ?= /tmp/a_riscv_processor_csr_smoke
ACT4_WORK_DIR := $(PROJECT_DIR)/compliance/act4/work
ARCH_TEST_WORK_DIR := $(PROJECT_DIR)/third_party/riscv-arch-test/work

TOP ?= topCPU
TB_TOP ?= topCPU_tb
MAX_CYCLES ?= 10000000
TRACE ?= 0
PIPE_DUMP ?= 1

VERILATOR ?= verilator
VERILATOR_FLAGS ?= -sv --timing -Wno-TIMESCALEMOD
VERILATOR_BUILD_FLAGS ?= --trace
TOP_PARAM_FLAGS ?=

RISCV_PREFIX ?= riscv64-unknown-elf-
RISCV_GCC ?= $(RISCV_PREFIX)gcc
RISCV_OBJCOPY ?= $(RISCV_PREFIX)objcopy
RISCV_SIZE ?= $(RISCV_PREFIX)size
PYTHON ?= python3

COREMARK_CFLAGS ?= -march=rv32i_zicsr -mabi=ilp32 -O2 -ffreestanding -nostdlib -I.
COREMARK_LDFLAGS ?= -Wl,-T,link.ld -Wl,-Map,coremark.map -lgcc
COREMARK_SRCS := core_main.c core_list_join.c core_matrix.c core_state.c core_util.c core_portme.c start.s

TRACE_ARG :=
ifneq ($(filter 1 true yes on,$(TRACE)),)
TRACE_ARG := +trace
endif

.PHONY: all help sim coremark lint bpu-smoke tage-smoke tage-update-smoke sc-smoke ooo-smoke ooo-backend-smoke rv32i-compliance-smoke act4-build act4-run build run konata csr-smoke clean clean-verilator clean-logs clean-coremark clean-compliance clean-temporary clean-generated clean-all

all: sim

help:
	@printf "Targets:\n"
	@printf "  make sim              Rebuild CoreMark images, lint, build, and run Verilator\n"
	@printf "  make coremark         Rebuild coremark.elf and source/utils memory images\n"
	@printf "  make lint             Verilator lint for RTL plus SV testbench\n"
	@printf "  make bpu-smoke        Run GShare-base direction and BTB tests\n"
	@printf "  make tage-smoke       Run tagged-table/TAGE predictor tests\n"
	@printf "  make tage-update-smoke Run TAGE update-queue FIFO tests\n"
	@printf "  make sc-smoke         Run statistical-corrector timing/training tests\n"
	@printf "  make ooo-smoke        Run structural smoke tests for RAT/PRF/ROB/IQ/LSQ\n"
	@printf "  make ooo-backend-smoke Run end-to-end OoO dispatch/execute/commit tests\n"
	@printf "  make rv32i-compliance-smoke Run directed RV32I decode/trap tests\n"
	@printf "  make act4-build       Build the 1 MiB ACT4 Verilator model\n"
	@printf "  make act4-run         Run generated ACT4 RV32I ELFs on the DUT\n"
	@printf "  make build            Build obj_dir/V$(TOP) with sim_main.cpp\n"
	@printf "  make run              Run obj_dir/V$(TOP)\n"
	@printf "  make konata           Convert source/topCPU_tb_output.txt to Konata trace\n"
	@printf "  make csr-smoke        Run a small CSR instruction/counter smoke test\n"
	@printf "  make clean            Remove Verilator outputs, waves, and sim logs\n"
	@printf "  make clean-coremark   Remove generated CoreMark ELF/bin/map/images\n"
	@printf "  make clean-compliance Remove generated ACT4/arch-test work directories\n"
	@printf "  make clean-generated  Remove all reproducible generated files\n"
	@printf "  make clean-all        Alias for clean-generated\n"
	@printf "\nOptions:\n"
	@printf "  MAX_CYCLES=10000000   Runtime cycle cap passed to sim_main.cpp\n"
	@printf "  TRACE=1               Generate wave.vcd during run\n"
	@printf "  PIPE_DUMP=0           Disable source/topCPU_tb_output.txt during run\n"
	@printf "  TOP_PARAM_FLAGS=...   Pass top-module -G parameter overrides to Verilator\n"

sim: coremark lint build run

coremark:
	cd "$(COREMARK_DIR)" && \
	$(RISCV_GCC) $(COREMARK_CFLAGS) $(COREMARK_SRCS) $(COREMARK_LDFLAGS) -o coremark.elf
	cd "$(COREMARK_DIR)" && $(RISCV_OBJCOPY) -O binary -j .text coremark.elf imem.bin
	cd "$(COREMARK_DIR)" && $(RISCV_OBJCOPY) -O binary -j .data coremark.elf dmem.bin
	cd "$(COREMARK_DIR)" && $(PYTHON) bin2words.py imem.bin insMemCore.txt 0x10000
	cd "$(COREMARK_DIR)" && $(PYTHON) bin2words.py dmem.bin dataMemCore.hex 0x10000
	cp "$(COREMARK_DIR)/insMemCore.txt" "$(SOURCE_DIR)/utils/insn.mem"
	cp "$(COREMARK_DIR)/dataMemCore.hex" "$(SOURCE_DIR)/utils/data.mem"
	cd "$(COREMARK_DIR)" && $(RISCV_SIZE) coremark.elf

lint:
	cd "$(SOURCE_DIR)" && \
	$(VERILATOR) --lint-only $(VERILATOR_FLAGS) -f filelist.f \
		"$(TESTBENCH_DIR)/topCPU_tb.sv" --top-module $(TB_TOP)

bpu-smoke:
	cd "$(SOURCE_DIR)" && \
	$(VERILATOR) --binary $(VERILATOR_FLAGS) -f filelist.f \
		"$(TESTBENCH_DIR)/bpu_tb.sv" --top-module bpu_tb \
		--Mdir obj_dir_bpu
	cd "$(SOURCE_DIR)" && ./obj_dir_bpu/Vbpu_tb

tage-smoke:
	cd "$(SOURCE_DIR)" && \
	$(VERILATOR) --binary $(VERILATOR_FLAGS) -f filelist.f \
		"$(TESTBENCH_DIR)/tage_tb.sv" --top-module tage_tb \
		--Mdir obj_dir_tage
	cd "$(SOURCE_DIR)" && ./obj_dir_tage/Vtage_tb

tage-update-smoke:
	cd "$(SOURCE_DIR)" && \
	$(VERILATOR) --binary $(VERILATOR_FLAGS) -f filelist.f \
		"$(TESTBENCH_DIR)/tage_update_queue_tb.sv" \
		--top-module tage_update_queue_tb \
		--Mdir obj_dir_tage_update
	cd "$(SOURCE_DIR)" && ./obj_dir_tage_update/Vtage_update_queue_tb

sc-smoke:
	cd "$(SOURCE_DIR)" && \
	$(VERILATOR) --binary $(VERILATOR_FLAGS) \
		TypesPkg.sv functional/BPU/StatisticalCorrector.sv \
		"$(TESTBENCH_DIR)/sc_tb.sv" --top-module sc_tb \
		--Mdir obj_dir_sc
	cd "$(SOURCE_DIR)" && ./obj_dir_sc/Vsc_tb

ooo-smoke:
	cd "$(SOURCE_DIR)" && \
	$(VERILATOR) --binary $(VERILATOR_FLAGS) -f filelist.f \
		"$(TESTBENCH_DIR)/ooo_smoke_tb.sv" --top-module ooo_smoke_tb \
		--Mdir obj_dir_ooo
	cd "$(SOURCE_DIR)" && ./obj_dir_ooo/Vooo_smoke_tb

ooo-backend-smoke:
	cd "$(SOURCE_DIR)" && \
	$(VERILATOR) --binary $(VERILATOR_FLAGS) -f filelist.f \
		"$(TESTBENCH_DIR)/ooo_backend_tb.sv" --top-module ooo_backend_tb \
		--Mdir obj_dir_ooo_backend
	cd "$(SOURCE_DIR)" && ./obj_dir_ooo_backend/Vooo_backend_tb

rv32i-compliance-smoke:
	cd "$(SOURCE_DIR)" && \
	$(VERILATOR) --binary $(VERILATOR_FLAGS) -f filelist.f \
		"$(TESTBENCH_DIR)/rv32i_compliance_tb.sv" --top-module rv32i_compliance_tb \
		--Mdir obj_dir_rv32i
	cd "$(SOURCE_DIR)" && ./obj_dir_rv32i/Vrv32i_compliance_tb

act4-build:
	cd "$(SOURCE_DIR)" && \
	$(VERILATOR) $(VERILATOR_FLAGS) --cc -f filelist.f --top-module $(TOP) \
		--exe sim_main.cpp --trace --build --Mdir obj_dir_act4 \
		-GINSN_MEM_ADDR_W=20 -GINSN_MEM_BYTES=1048576 \
		-GDATA_MEM_ADDR_W=20 -GDATA_MEM_BYTES=1048576 \
		-GUART_TX_MMIO_ADDR=1048544 -GFROMHOST_MMIO_ADDR=1048560 \
		-GTOHOST_MMIO_ADDR=1048568

act4-run: act4-build
	$(PYTHON) "$(PROJECT_DIR)/compliance/run_act4.py"

build:
	cd "$(SOURCE_DIR)" && \
	$(VERILATOR) $(VERILATOR_FLAGS) --cc -f filelist.f \
		--top-module $(TOP) --exe sim_main.cpp $(VERILATOR_BUILD_FLAGS) \
		$(TOP_PARAM_FLAGS) --build

run:
	cd "$(SOURCE_DIR)" && SIM_PIPE_DUMP=$(PIPE_DUMP) ./obj_dir/V$(TOP) +max-cycles=$(MAX_CYCLES) $(TRACE_ARG)

konata:
	$(PYTHON) "$(TESTBENCH_DIR)/tb_dump_to_konata.py" \
		"$(SOURCE_DIR)/topCPU_tb_output.txt" \
		"$(SOURCE_DIR)/topCPU_tb_konata.trace"

csr-smoke: build
	mkdir -p "$(CSR_SMOKE_DIR)"
	$(RISCV_GCC) -march=rv32i_zicsr -mabi=ilp32 -ffreestanding -nostdlib \
		"$(TEST_DIR)/csr_smoke.S" -Wl,-T,"$(COREMARK_DIR)/link.ld" \
		-o "$(CSR_SMOKE_DIR)/csr_smoke.elf"
	$(RISCV_OBJCOPY) -O binary -j .text "$(CSR_SMOKE_DIR)/csr_smoke.elf" "$(CSR_SMOKE_DIR)/imem.bin"
	: > "$(CSR_SMOKE_DIR)/dmem.bin"
	cd "$(COREMARK_DIR)" && $(PYTHON) bin2words.py "$(CSR_SMOKE_DIR)/imem.bin" "$(CSR_SMOKE_DIR)/insn.mem" 0x10000
	cd "$(COREMARK_DIR)" && $(PYTHON) bin2words.py "$(CSR_SMOKE_DIR)/dmem.bin" "$(CSR_SMOKE_DIR)/data.mem" 0x10000
	cp "$(CSR_SMOKE_DIR)/insn.mem" "$(SOURCE_DIR)/utils/insn.mem"
	cp "$(CSR_SMOKE_DIR)/data.mem" "$(SOURCE_DIR)/utils/data.mem"
	cd "$(SOURCE_DIR)" && ./obj_dir/V$(TOP) +max-cycles=10000; \
	status=$$?; \
	cd "$(PROJECT_DIR)" && $(MAKE) --no-print-directory coremark >/dev/null; \
	exit $$status

clean: clean-verilator clean-logs

clean-verilator:
	rm -rf "$(SOURCE_DIR)"/obj_dir*
	rm -f "$(SOURCE_DIR)/wave.vcd" "$(SOURCE_DIR)/simulation_output.txt"

clean-logs:
	rm -f "$(SOURCE_DIR)/topCPU_tb_output.txt"
	rm -f "$(SOURCE_DIR)/topCPU_tb_debug.txt"
	rm -f "$(SOURCE_DIR)/topCPU_tb_konata.trace"
	rm -f "$(SOURCE_DIR)/coremark_branch.csv"

clean-coremark:
	rm -f "$(COREMARK_DIR)/coremark.elf" "$(COREMARK_DIR)/coremark.map"
	rm -f "$(COREMARK_DIR)/imem.bin" "$(COREMARK_DIR)/dmem.bin" "$(COREMARK_DIR)/mem.bin"
	rm -f "$(COREMARK_DIR)/insMemCore.txt" "$(COREMARK_DIR)/dataMemCore.hex"

clean-compliance:
	rm -rf "$(ACT4_WORK_DIR)"
	rm -rf "$(ARCH_TEST_WORK_DIR)"

clean-temporary:
	rm -rf "$(CSR_SMOKE_DIR)"
	rm -f "$(SOURCE_DIR)"/core "$(SOURCE_DIR)"/core.*
	rm -f "$(SOURCE_DIR)"/*.vcd "$(SOURCE_DIR)"/*.fst "$(SOURCE_DIR)"/*.log

# Remove only reproducible build/test products. Source memory images and the
# downloaded toolchain under .tools are intentionally preserved.
clean-generated: clean clean-coremark clean-compliance clean-temporary

clean-all: clean-generated
