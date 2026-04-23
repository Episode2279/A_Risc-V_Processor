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

TOP ?= topCPU
TB_TOP ?= topCPU_tb
MAX_CYCLES ?= 10000000
TRACE ?= 0
PIPE_DUMP ?= 1

VERILATOR ?= verilator
VERILATOR_FLAGS ?= -sv --timing -Wno-TIMESCALEMOD
VERILATOR_BUILD_FLAGS ?= --trace

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

.PHONY: all help sim coremark lint build run konata csr-smoke clean clean-verilator clean-logs clean-coremark clean-all

all: sim

help:
	@printf "Targets:\n"
	@printf "  make sim              Rebuild CoreMark images, lint, build, and run Verilator\n"
	@printf "  make coremark         Rebuild coremark.elf and source/utils memory images\n"
	@printf "  make lint             Verilator lint for RTL plus SV testbench\n"
	@printf "  make build            Build obj_dir/V$(TOP) with sim_main.cpp\n"
	@printf "  make run              Run obj_dir/V$(TOP)\n"
	@printf "  make konata           Convert source/topCPU_tb_output.txt to Konata trace\n"
	@printf "  make csr-smoke        Run a small CSR instruction/counter smoke test\n"
	@printf "  make clean            Remove Verilator outputs, waves, and sim logs\n"
	@printf "  make clean-coremark   Remove generated CoreMark ELF/bin/map/images\n"
	@printf "  make clean-all        Run clean and clean-coremark\n"
	@printf "\nOptions:\n"
	@printf "  MAX_CYCLES=10000000   Runtime cycle cap passed to sim_main.cpp\n"
	@printf "  TRACE=1               Generate wave.vcd during run\n"
	@printf "  PIPE_DUMP=0           Disable source/topCPU_tb_output.txt during run\n"

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

build:
	cd "$(SOURCE_DIR)" && \
	$(VERILATOR) $(VERILATOR_FLAGS) --cc -f filelist.f \
		--top-module $(TOP) --exe sim_main.cpp $(VERILATOR_BUILD_FLAGS) --build

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
	rm -rf "$(SOURCE_DIR)/obj_dir"
	rm -f "$(SOURCE_DIR)/wave.vcd" "$(SOURCE_DIR)/simulation_output.txt"

clean-logs:
	rm -f "$(SOURCE_DIR)/topCPU_tb_output.txt"
	rm -f "$(SOURCE_DIR)/topCPU_tb_debug.txt"
	rm -f "$(SOURCE_DIR)/topCPU_tb_konata.trace"

clean-coremark:
	rm -f "$(COREMARK_DIR)/coremark.elf" "$(COREMARK_DIR)/coremark.map"
	rm -f "$(COREMARK_DIR)/imem.bin" "$(COREMARK_DIR)/dmem.bin" "$(COREMARK_DIR)/mem.bin"
	rm -f "$(COREMARK_DIR)/insMemCore.txt" "$(COREMARK_DIR)/dataMemCore.hex"

clean-all: clean clean-coremark
