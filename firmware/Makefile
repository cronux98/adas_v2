# ========================================================================
# Makefile — ADAS v2 Firmware SDK Build System
# ========================================================================
# Target:   RV32IM (rv32im_zicsr_zifencei) | sky130hs | 100 MHz | bare-metal
# Tool:     riscv32-unknown-elf-gcc 14.2.1 (GCC14 at OpenROAD)
# SDK:      adas_v2_firmware_sdk v0.1.0-dev
#
# Usage:
#   make all        — Build firmware ELF, BIN, DIS
#   make clean      — Remove build artifacts
#   make test       — Integration test (compile + link + symbol verify)
#   make disasm     — Generate disassembly
#   make size       — Print section sizes
# ========================================================================

# ---- Toolchain (GCC14 riscv32 @ OpenROAD) ----
TOOLCHAIN  ?= /opt/OpenROAD/riscv/gcc14-no-zcmp/bin
CROSS      := riscv32-unknown-elf-
CC         := $(TOOLCHAIN)/$(CROSS)gcc
AS         := $(TOOLCHAIN)/$(CROSS)as
LD         := $(TOOLCHAIN)/$(CROSS)ld
OBJCOPY    := $(TOOLCHAIN)/$(CROSS)objcopy
OBJDUMP    := $(TOOLCHAIN)/$(CROSS)objdump
SIZE       := $(TOOLCHAIN)/$(CROSS)size

# ---- Directories ----
SDK_DIR     := .
HAL_DIR     := $(SDK_DIR)/hal
BUILD_DIR   := $(SDK_DIR)/build
ALGO_DIR    := ../deliverables/firmware_engineer

# ---- Target ----
TARGET      := adas_v2_firmware
ELF         := $(BUILD_DIR)/$(TARGET).elf
BIN         := $(BUILD_DIR)/$(TARGET).bin
DIS         := $(BUILD_DIR)/$(TARGET).dis
MAP         := $(BUILD_DIR)/$(TARGET).map

# ---- Compiler Flags ----
ARCH        := rv32im_zicsr_zifencei
ABI         := ilp32

CFLAGS      := -march=$(ARCH) -mabi=$(ABI)
CFLAGS      += -O2
CFLAGS      += -Wall -Wextra -Werror
CFLAGS      += -ffreestanding -nostdlib -nostartfiles
CFLAGS      += -fno-builtin -fno-common
CFLAGS      += -ffunction-sections -fdata-sections
CFLAGS      += -I$(SDK_DIR) -I$(ALGO_DIR) -I$(HAL_DIR)

# ---- Linker Flags ----
LDFLAGS     := -march=$(ARCH) -mabi=$(ABI)
LDFLAGS     += -nostdlib -nostartfiles
# libgcc path for rv32im_zicsr_zifencei (required for int64 div/mod emulation)
LIBGCC_DIR  := $(shell $(CC) -march=$(ARCH) -mabi=$(ABI) -print-libgcc-file-name | xargs dirname)
LDFLAGS     += -L$(LIBGCC_DIR) -lgcc
LDFLAGS     += -T $(SDK_DIR)/linker.ld
LDFLAGS     += -Wl,-Map=$(MAP)
LDFLAGS     += -Wl,--gc-sections
LDFLAGS     += -Wl,--cref

# ---- Source Files (SDK) ----
SDK_S_SRCS   := $(SDK_DIR)/crt0.s
SDK_C_SRCS   := $(SDK_DIR)/divdi3.c

# ---- SDK Objects ----
SDK_S_OBJS   := $(patsubst $(SDK_DIR)/%.s, $(BUILD_DIR)/sdk_%.o, $(SDK_S_SRCS))
SDK_C_OBJS   := $(patsubst $(SDK_DIR)/%.c, $(BUILD_DIR)/sdk_%.o, $(SDK_C_SRCS))
SDK_OBJS     := $(SDK_S_OBJS) $(SDK_C_OBJS)

# ---- Application Sources (for integration test) ----
APP_C_SRCS   := $(SDK_DIR)/main.c \
                $(SDK_DIR)/ai_accel_driver.c \
                $(ALGO_DIR)/adas_algorithm.c
APP_OBJS     := $(patsubst %.c, $(BUILD_DIR)/%.o, $(notdir $(APP_C_SRCS)))

# ---- All Objects ----
ALL_OBJS     := $(SDK_OBJS) $(APP_OBJS)

# ========================================================================
# RULES
# ========================================================================

.PHONY: all clean test disasm size

all: $(ELF) $(BIN) $(DIS) size

# ---- Compile SDK assembly (crt0.s) ----
$(BUILD_DIR)/sdk_%.o: $(SDK_DIR)/%.s
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

# ---- Compile SDK C sources (divdi3.c) ----
$(BUILD_DIR)/sdk_%.o: $(SDK_DIR)/%.c
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

# ---- Compile application C sources ----
$(BUILD_DIR)/main.o: $(SDK_DIR)/main.c
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/adas_algorithm.o: $(ALGO_DIR)/adas_algorithm.c
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/ai_accel_driver.o: $(SDK_DIR)/ai_accel_driver.c
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

# ---- Link ----
$(ELF): $(ALL_OBJS)
	$(CC) $(LDFLAGS) $(ALL_OBJS) -lgcc -o $@

# ---- Binary (raw) ----
$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

# ---- Disassembly ----
$(DIS): $(ELF)
	$(OBJDUMP) -D -M numeric,no-aliases $< > $@

# ---- Size Report ----
size: $(ELF)
	@echo "============================================"
	@echo " ADAS v2 Firmware — Section Sizes"
	@echo "============================================"
	@$(SIZE) $(ELF)

# ---- Integration Test ----
test: all
	@echo ""
	@echo "============================================"
	@echo " INTEGRATION TEST"
	@echo "============================================"
	@echo "  ELF:       $(ELF)"
	@echo "  Binary:    $(BIN)"
	@echo "  Disasm:    $(DIS)"
	@echo "  Map file:  $(MAP)"
	@echo ""
	@# Verify key symbols exist
	@$(OBJDUMP) -t $(ELF) | grep -q "ai_accel_sw_compute" && \
	 echo "  [PASS] ai_accel_sw_compute found" || \
	 (echo "  [FAIL] MISSING: ai_accel_sw_compute" && false)
	@$(OBJDUMP) -t $(ELF) | grep -q "ai_accel_init_pipeline" && \
	 echo "  [PASS] ai_accel_init_pipeline found" || \
	 (echo "  [FAIL] MISSING: ai_accel_init_pipeline" && false)
	@$(OBJDUMP) -t $(ELF) | grep -q "ai_accel_run" && \
	 echo "  [PASS] ai_accel_run found" || \
	 (echo "  [FAIL] MISSING: ai_accel_run" && false)
	@$(OBJDUMP) -t $(ELF) | grep -q "ai_accel_classify" && \
	 echo "  [PASS] ai_accel_classify found" || \
	 (echo "  [FAIL] MISSING: ai_accel_classify" && false)
	@$(OBJDUMP) -t $(ELF) | grep -q "_start" && \
	 echo "  [PASS] _start entry point found" || \
	 (echo "  [FAIL] MISSING: _start" && false)
	@$(OBJDUMP) -t $(ELF) | grep -q "vector_table" && \
	 echo "  [PASS] vector_table found" || \
	 (echo "  [FAIL] MISSING: vector_table" && false)
	@# Verify ADAS algorithm symbols (--gc-sections must NOT drop these)
	@$(OBJDUMP) -t $(ELF) | grep -q "adas_init" && \
	 echo "  [PASS] adas_init found" || \
	 (echo "  [FAIL] MISSING: adas_init" && false)
	@$(OBJDUMP) -t $(ELF) | grep -q "adas_process_frame" && \
	 echo "  [PASS] adas_process_frame found" || \
	 (echo "  [FAIL] MISSING: adas_process_frame" && false)
	@$(OBJDUMP) -t $(ELF) | grep -q "adas_validate_frame" && \
	 echo "  [PASS] adas_validate_frame found" || \
	 (echo "  [FAIL] MISSING: adas_validate_frame" && false)
	@$(OBJDUMP) -t $(ELF) | grep -q "adas_compute_ttc" && \
	 echo "  [PASS] adas_compute_ttc found" || \
	 (echo "  [FAIL] MISSING: adas_compute_ttc" && false)
	@$(OBJDUMP) -t $(ELF) | grep -q "adas_safety_monitor_tick" && \
	 echo "  [PASS] adas_safety_monitor_tick found" || \
	 (echo "  [FAIL] MISSING: adas_safety_monitor_tick" && false)
	@# Verify no C-extension or FLH/FLD/FSH/FSD instructions
	@! $(OBJDUMP) -d $(ELF) | grep -qP '\tc\.' && \
	 echo "  [PASS] No C-extension instructions" || \
	 (echo "  [FAIL] C-extension instructions found" && false)
	@! $(OBJDUMP) -d $(ELF) | grep -qP '\tf(l[whd]|s[whd])\b' && \
	 echo "  [PASS] No floating-point instructions" || \
	 (echo "  [FAIL] FP instructions found" && false)
	@echo ""
	@echo "============================================"
	@echo " INTEGRATION TEST PASSED"
	@echo "============================================"

# ---- Clean ----
clean:
	rm -rf $(BUILD_DIR)

# ---- Help ----
help:
	@echo "ADAS v2 Firmware SDK Build System"
	@echo ""
	@echo "Targets:"
	@echo "  make all      — Full build: ELF, BIN, DIS"
	@echo "  make test     — Integration test (all + symbol/ISA verification)"
	@echo "  make clean    — Remove build directory"
	@echo "  make size     — Print section sizes"
	@echo ""
	@echo "Toolchain: $(TOOLCHAIN)/$(CROSS)gcc"
	@echo "Target:    $(ARCH) | ABI: $(ABI) | Clock: 100 MHz"
	@echo "SDK:       v0.1.0-dev"
	@echo "PDK:       sky130_fd_sc_hs"
