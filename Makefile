# Project-level Verilator/CoreMark/Vivado flow.
# Run from WSL/Linux in this directory:
#   make sim
#   make clean

PROJECT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
RTL_DIR := $(PROJECT_DIR)/rtl
FILELIST_DIR := $(PROJECT_DIR)/config/filelists
VERIFICATION_DIR := $(PROJECT_DIR)/verification
SIM_DIR := $(PROJECT_DIR)/sim/verilator
TOOLS_DIR := $(PROJECT_DIR)/tools
COREMARK_DIR := $(PROJECT_DIR)/coremark
TEST_DIR := $(PROJECT_DIR)/test
BUILD_DIR ?= $(PROJECT_DIR)/build
IMAGE_DIR := $(BUILD_DIR)/images
TRACE_DIR := $(BUILD_DIR)/traces
VERILATOR_DIR := $(BUILD_DIR)/verilator
TOP_BUILD_DIR := $(VERILATOR_DIR)/top
ACT4_BUILD_DIR := $(VERILATOR_DIR)/act4
CORE_FILELIST := $(FILELIST_DIR)/core.f
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
VIVADO ?= vivado
FPGA_PART ?=

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

.PHONY: all help sim coremark lint fetch-queue-smoke bpu-smoke tage-smoke tage-update-smoke \
	sc-smoke icache-smoke dcache-smoke cache-smoke store-buffer-smoke \
	lsu-pending-smoke ooo-smoke ooo-backend-smoke rv32i-compliance-smoke \
	act4-build act4-run build run kanata kanata-legacy konata csr-smoke \
	vivado-project vivado-sim vivado-synth clean clean-cache clean-verilator clean-logs \
	clean-coremark clean-compliance clean-temporary clean-generated clean-all

all: sim

help:
	@printf "Targets:\n"
	@printf "  make sim              Rebuild CoreMark images, lint, build, and run Verilator\n"
	@printf "  make coremark         Rebuild CoreMark and build/images/*.mem\n"
	@printf "  make lint             Verilator lint for RTL plus integration testbench\n"
	@printf "  make fetch-queue-smoke Test buffered dual-fetch enqueue/dequeue/flush\n"
	@printf "  make bpu-smoke        Run GShare-base direction and BTB tests\n"
	@printf "  make tage-smoke       Run tagged-table/TAGE predictor tests\n"
	@printf "  make tage-update-smoke Run TAGE update-queue FIFO tests\n"
	@printf "  make sc-smoke         Run statistical-corrector timing/training tests\n"
	@printf "  make icache-smoke     Run synchronous I-cache refill/flush tests\n"
	@printf "  make dcache-smoke     Run synchronous D-cache/load/store/MMIO tests\n"
	@printf "  make cache-smoke      Run both cache smoke tests\n"
	@printf "  make store-buffer-smoke Run committed Store FIFO/forwarding tests\n"
	@printf "  make lsu-pending-smoke Run tagged multi-pending Load/recovery tests\n"
	@printf "  make ooo-smoke        Run structural smoke tests for RAT/PRF/ROB/IQ/LSQ\n"
	@printf "  make ooo-backend-smoke Run end-to-end OoO backend tests\n"
	@printf "  make rv32i-compliance-smoke Run directed RV32I decode/trap tests\n"
	@printf "  make act4-build       Build the 1 MiB ACT4 Verilator model\n"
	@printf "  make act4-run         Run generated ACT4 RV32I ELFs on the DUT\n"
	@printf "  make build            Build build/verilator/top/V$(TOP)\n"
	@printf "  make run              Run the Verilator model from the project root\n"
	@printf "  make kanata           Convert the V2 OoO dump to a Kanata trace\n"
	@printf "  make kanata-legacy    Run the previous compatibility converter\n"
	@printf "  make konata           Compatibility alias for make kanata\n"
	@printf "  make vivado-project FPGA_PART=<part>  Create build/vivado project\n"
	@printf "  make vivado-sim FPGA_PART=<part>      Run the XSim integration testbench\n"
	@printf "  make vivado-synth FPGA_PART=<part>    Run Vivado synthesis\n"
	@printf "  make csr-smoke        Run a small CSR instruction/counter smoke test\n"
	@printf "  make clean            Remove generated Verilator and trace products\n"
	@printf "  make clean-generated  Remove all reproducible build/test products\n"
	@printf "\nOptions:\n"
	@printf "  MAX_CYCLES=10000000   Runtime cycle cap\n"
	@printf "  TRACE=1               Generate build/traces/wave.vcd\n"
	@printf "  PIPE_DUMP=0           Disable build/traces/topCPU_tb_output.txt\n"
	@printf "  FPGA_PART=...         Required Vivado target part, e.g. xc7a35tcpg236-1\n"

sim: coremark lint build run

coremark:
	mkdir -p "$(IMAGE_DIR)"
	cd "$(COREMARK_DIR)" && \
	$(RISCV_GCC) $(COREMARK_CFLAGS) $(COREMARK_SRCS) $(COREMARK_LDFLAGS) -o coremark.elf
	cd "$(COREMARK_DIR)" && $(RISCV_OBJCOPY) -O binary -j .text coremark.elf imem.bin
	cd "$(COREMARK_DIR)" && $(RISCV_OBJCOPY) -O binary -j .data coremark.elf dmem.bin
	cd "$(COREMARK_DIR)" && $(PYTHON) bin2words.py imem.bin insMemCore.txt 0x10000
	cd "$(COREMARK_DIR)" && $(PYTHON) bin2words.py dmem.bin dataMemCore.hex 0x10000
	cp "$(COREMARK_DIR)/insMemCore.txt" "$(IMAGE_DIR)/insn.mem"
	cp "$(COREMARK_DIR)/dataMemCore.hex" "$(IMAGE_DIR)/data.mem"
	cd "$(COREMARK_DIR)" && $(RISCV_SIZE) coremark.elf

lint:
	cd "$(PROJECT_DIR)" && \
	$(VERILATOR) --lint-only $(VERILATOR_FLAGS) -f "$(CORE_FILELIST)" \
		"$(VERIFICATION_DIR)/integration/core/topCPU_tb.sv" --top-module $(TB_TOP)

fetch-queue-smoke:
	mkdir -p "$(VERILATOR_DIR)/fetch-queue"
	cd "$(PROJECT_DIR)" && \
	$(VERILATOR) --binary $(VERILATOR_FLAGS) \
		rtl/common/TypesPkg.sv rtl/common/interfaces/InstructionPacketIf.sv \
		rtl/frontend/fetch/FetchQueue.sv \
		"$(VERIFICATION_DIR)/unit/frontend/fetch_queue_tb.sv" \
		--top-module fetch_queue_tb --Mdir "$(VERILATOR_DIR)/fetch-queue"
	"$(VERILATOR_DIR)/fetch-queue/Vfetch_queue_tb"

bpu-smoke:
	mkdir -p "$(VERILATOR_DIR)/bpu"
	cd "$(PROJECT_DIR)" && \
	$(VERILATOR) --binary $(VERILATOR_FLAGS) -f "$(CORE_FILELIST)" \
		"$(VERIFICATION_DIR)/unit/bpu/bpu_tb.sv" --top-module bpu_tb \
		--Mdir "$(VERILATOR_DIR)/bpu"
	"$(VERILATOR_DIR)/bpu/Vbpu_tb"

tage-smoke:
	mkdir -p "$(VERILATOR_DIR)/tage"
	cd "$(PROJECT_DIR)" && \
	$(VERILATOR) --binary $(VERILATOR_FLAGS) -f "$(CORE_FILELIST)" \
		"$(VERIFICATION_DIR)/unit/bpu/tage_tb.sv" --top-module tage_tb \
		--Mdir "$(VERILATOR_DIR)/tage"
	"$(VERILATOR_DIR)/tage/Vtage_tb"

tage-update-smoke:
	mkdir -p "$(VERILATOR_DIR)/tage-update"
	cd "$(PROJECT_DIR)" && \
	$(VERILATOR) --binary $(VERILATOR_FLAGS) -f "$(CORE_FILELIST)" \
		"$(VERIFICATION_DIR)/unit/bpu/tage_update_queue_tb.sv" \
		--top-module tage_update_queue_tb --Mdir "$(VERILATOR_DIR)/tage-update"
	"$(VERILATOR_DIR)/tage-update/Vtage_update_queue_tb"

sc-smoke:
	mkdir -p "$(VERILATOR_DIR)/sc"
	cd "$(PROJECT_DIR)" && \
	$(VERILATOR) --binary $(VERILATOR_FLAGS) \
		rtl/common/TypesPkg.sv rtl/frontend/bpu/StatisticalCorrector.sv \
		"$(VERIFICATION_DIR)/unit/bpu/sc_tb.sv" --top-module sc_tb \
		--Mdir "$(VERILATOR_DIR)/sc"
	"$(VERILATOR_DIR)/sc/Vsc_tb"

icache-smoke:
	mkdir -p "$(VERILATOR_DIR)/icache"
	cd "$(PROJECT_DIR)" && \
	$(VERILATOR) --binary $(VERILATOR_FLAGS) \
		rtl/common/TypesPkg.sv rtl/memory/icache/InstructionCache.sv \
		"$(VERIFICATION_DIR)/unit/cache/icache_tb.sv" --top-module icache_tb \
		--Mdir "$(VERILATOR_DIR)/icache"
	"$(VERILATOR_DIR)/icache/Vicache_tb"

dcache-smoke:
	mkdir -p "$(VERILATOR_DIR)/dcache"
	cd "$(PROJECT_DIR)" && \
	$(VERILATOR) --binary $(VERILATOR_FLAGS) \
		rtl/common/TypesPkg.sv rtl/memory/dcache/DataCache.sv \
		rtl/memory/backing/dataMem.sv rtl/memory/subsystem/MEMStages.sv \
		"$(VERIFICATION_DIR)/unit/cache/dcache_tb.sv" --top-module dcache_tb \
		--Mdir "$(VERILATOR_DIR)/dcache"
	"$(VERILATOR_DIR)/dcache/Vdcache_tb"

cache-smoke: icache-smoke dcache-smoke

store-buffer-smoke:
	mkdir -p "$(VERILATOR_DIR)/store-buffer"
	cd "$(PROJECT_DIR)" && \
	$(VERILATOR) --binary $(VERILATOR_FLAGS) \
		rtl/common/TypesPkg.sv rtl/backend/execute/lsu/StoreBuffer.sv \
		"$(VERIFICATION_DIR)/unit/lsu/store_buffer_tb.sv" \
		--top-module store_buffer_tb --Mdir "$(VERILATOR_DIR)/store-buffer"
	"$(VERILATOR_DIR)/store-buffer/Vstore_buffer_tb"

lsu-pending-smoke:
	mkdir -p "$(VERILATOR_DIR)/lsu-pending"
	cd "$(PROJECT_DIR)" && \
	$(VERILATOR) --binary $(VERILATOR_FLAGS) \
		rtl/common/TypesPkg.sv rtl/backend/execute/lsu/LoadStoreExecutionUnit.sv \
		"$(VERIFICATION_DIR)/unit/lsu/lsu_pending_tb.sv" \
		--top-module lsu_pending_tb --Mdir "$(VERILATOR_DIR)/lsu-pending"
	"$(VERILATOR_DIR)/lsu-pending/Vlsu_pending_tb"

ooo-smoke:
	mkdir -p "$(VERILATOR_DIR)/ooo"
	cd "$(PROJECT_DIR)" && \
	$(VERILATOR) --binary $(VERILATOR_FLAGS) -f "$(CORE_FILELIST)" \
		"$(VERIFICATION_DIR)/unit/backend/ooo_smoke_tb.sv" --top-module ooo_smoke_tb \
		--Mdir "$(VERILATOR_DIR)/ooo"
	"$(VERILATOR_DIR)/ooo/Vooo_smoke_tb"

ooo-backend-smoke:
	mkdir -p "$(VERILATOR_DIR)/ooo-backend"
	cd "$(PROJECT_DIR)" && \
	$(VERILATOR) --binary $(VERILATOR_FLAGS) -f "$(CORE_FILELIST)" \
		"$(VERIFICATION_DIR)/unit/backend/ooo_backend_tb.sv" --top-module ooo_backend_tb \
		--Mdir "$(VERILATOR_DIR)/ooo-backend"
	"$(VERILATOR_DIR)/ooo-backend/Vooo_backend_tb"

rv32i-compliance-smoke:
	mkdir -p "$(VERILATOR_DIR)/rv32i"
	cd "$(PROJECT_DIR)" && \
	$(VERILATOR) --binary $(VERILATOR_FLAGS) -f "$(CORE_FILELIST)" \
		"$(VERIFICATION_DIR)/unit/isa/rv32i_compliance_tb.sv" --top-module rv32i_compliance_tb \
		--Mdir "$(VERILATOR_DIR)/rv32i"
	"$(VERILATOR_DIR)/rv32i/Vrv32i_compliance_tb"

act4-build:
	mkdir -p "$(ACT4_BUILD_DIR)"
	cd "$(PROJECT_DIR)" && \
	$(VERILATOR) $(VERILATOR_FLAGS) --cc -f "$(CORE_FILELIST)" --top-module $(TOP) \
		--exe "$(SIM_DIR)/sim_main.cpp" --trace --build --Mdir "$(ACT4_BUILD_DIR)" \
		-GINSN_MEM_ADDR_W=20 -GINSN_MEM_BYTES=1048576 \
		-GDATA_MEM_ADDR_W=20 -GDATA_MEM_BYTES=1048576 \
		-GUART_TX_MMIO_ADDR=1048544 -GFROMHOST_MMIO_ADDR=1048560 \
		-GTOHOST_MMIO_ADDR=1048568

act4-run: act4-build
	$(PYTHON) "$(PROJECT_DIR)/compliance/run_act4.py"

build:
	mkdir -p "$(TOP_BUILD_DIR)" "$(TRACE_DIR)"
	cd "$(PROJECT_DIR)" && \
	$(VERILATOR) $(VERILATOR_FLAGS) --cc -f "$(CORE_FILELIST)" \
		--top-module $(TOP) --exe "$(SIM_DIR)/sim_main.cpp" \
		$(VERILATOR_BUILD_FLAGS) $(TOP_PARAM_FLAGS) --Mdir "$(TOP_BUILD_DIR)" --build

run:
	mkdir -p "$(TRACE_DIR)"
	cd "$(PROJECT_DIR)" && SIM_PIPE_DUMP=$(PIPE_DUMP) "$(TOP_BUILD_DIR)/V$(TOP)" \
		+max-cycles=$(MAX_CYCLES) +insn-mem="$(IMAGE_DIR)/insn.mem" \
		+data-mem="$(IMAGE_DIR)/data.mem" $(TRACE_ARG)

kanata:
	mkdir -p "$(TRACE_DIR)"
	$(PYTHON) "$(TOOLS_DIR)/kanata/tb_dump_v2_to_kanata.py" \
		"$(TRACE_DIR)/topCPU_tb_output.txt" \
		"$(TRACE_DIR)/topCPU_tb_kanata.trace" --strict

konata: kanata

kanata-legacy:
	mkdir -p "$(TRACE_DIR)"
	$(PYTHON) "$(TOOLS_DIR)/kanata/tb_dump_to_konata_legacy.py" \
		"$(TRACE_DIR)/topCPU_tb_output.txt" \
		"$(TRACE_DIR)/topCPU_tb_konata_legacy.trace"

csr-smoke: build
	mkdir -p "$(CSR_SMOKE_DIR)" "$(IMAGE_DIR)"
	$(RISCV_GCC) -march=rv32i_zicsr -mabi=ilp32 -ffreestanding -nostdlib \
		"$(TEST_DIR)/csr_smoke.S" -Wl,-T,"$(COREMARK_DIR)/link.ld" \
		-o "$(CSR_SMOKE_DIR)/csr_smoke.elf"
	$(RISCV_OBJCOPY) -O binary -j .text "$(CSR_SMOKE_DIR)/csr_smoke.elf" "$(CSR_SMOKE_DIR)/imem.bin"
	: > "$(CSR_SMOKE_DIR)/dmem.bin"
	cd "$(COREMARK_DIR)" && $(PYTHON) bin2words.py "$(CSR_SMOKE_DIR)/imem.bin" "$(IMAGE_DIR)/insn.mem" 0x10000
	cd "$(COREMARK_DIR)" && $(PYTHON) bin2words.py "$(CSR_SMOKE_DIR)/dmem.bin" "$(IMAGE_DIR)/data.mem" 0x10000
	cd "$(PROJECT_DIR)" && SIM_PIPE_DUMP=0 "$(TOP_BUILD_DIR)/V$(TOP)" \
		+insn-mem="$(IMAGE_DIR)/insn.mem" +data-mem="$(IMAGE_DIR)/data.mem" \
		+max-cycles=10000; \
	status=$$?; \
	cd "$(PROJECT_DIR)" && $(MAKE) --no-print-directory coremark >/dev/null; \
	exit $$status

vivado-project:
	@test -n "$(FPGA_PART)" || (echo "FPGA_PART is required" && exit 2)
	$(VIVADO) -mode batch -source "$(PROJECT_DIR)/fpga/vivado/scripts/create_project.tcl" \
		-tclargs "$(FPGA_PART)"

vivado-sim: coremark
	@test -n "$(FPGA_PART)" || (echo "FPGA_PART is required" && exit 2)
	$(VIVADO) -mode batch -source "$(PROJECT_DIR)/fpga/vivado/scripts/run_simulation.tcl" \
		-tclargs "$(FPGA_PART)"

vivado-synth:
	@test -n "$(FPGA_PART)" || (echo "FPGA_PART is required" && exit 2)
	$(VIVADO) -mode batch -source "$(PROJECT_DIR)/fpga/vivado/scripts/run_synthesis.tcl" \
		-tclargs "$(FPGA_PART)"

clean: clean-verilator clean-logs

clean-cache:
	rm -rf "$(VERILATOR_DIR)/icache" "$(VERILATOR_DIR)/dcache"
	rm -rf "$(VERILATOR_DIR)/store-buffer" "$(VERILATOR_DIR)/lsu-pending"

clean-verilator:
	rm -rf "$(VERILATOR_DIR)"

clean-logs:
	rm -rf "$(TRACE_DIR)"

clean-coremark:
	rm -f "$(COREMARK_DIR)/coremark.elf" "$(COREMARK_DIR)/coremark.map"
	rm -f "$(COREMARK_DIR)/imem.bin" "$(COREMARK_DIR)/dmem.bin" "$(COREMARK_DIR)/mem.bin"
	rm -f "$(COREMARK_DIR)/insMemCore.txt" "$(COREMARK_DIR)/dataMemCore.hex"

clean-compliance:
	rm -rf "$(ACT4_WORK_DIR)"
	rm -rf "$(ARCH_TEST_WORK_DIR)"

clean-temporary:
	rm -rf "$(CSR_SMOKE_DIR)"
	rm -f "$(BUILD_DIR)"/core "$(BUILD_DIR)"/core.*

clean-generated: clean clean-coremark clean-compliance clean-temporary
	rm -rf "$(IMAGE_DIR)" "$(BUILD_DIR)/vivado"

clean-all: clean-generated
