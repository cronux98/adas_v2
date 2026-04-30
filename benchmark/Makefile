# Makefile for CoreMark RV32I port

CC = riscv64-unknown-elf-gcc
CFLAGS = -march=rv32i -mabi=ilp32 -O2 -nostartfiles -nostdlib -ffreestanding \
         -I. -Isrc -DITERATIONS=1 -DPERFORMANCE_RUN=1 -DTOTAL_DATA_SIZE=2000 \
         -DMAIN_HAS_NOARGC=1 -DHAS_FLOAT=0 -DHAS_TIME_H=0 -DUSE_CLOCK=0 \
         -DHAS_STDIO=0 -DHAS_PRINTF=0 -DMEM_METHOD=MEM_STATIC \
         -DSEED_METHOD=SEED_VOLATILE
LDFLAGS = -T memory.ld -Wl,--gc-sections

SRCS = src/crt0.s \
       src/ee_printf.c \
       core_portme.c \
       core_main.c \
       core_list_join.c \
       core_matrix.c \
       core_state.c \
       core_util.c

OBJS = $(SRCS:.c=.o)
OBJS := $(OBJS:.s=.o)

TARGET = coremark.elf
HEX = coremark.hex
DATA_HEX = coremark_data.hex

.PHONY: all clean

all: $(TARGET) $(HEX) $(DATA_HEX)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.s
	$(CC) $(CFLAGS) -c $< -o $@

$(TARGET): $(OBJS) memory.ld
	$(CC) $(CFLAGS) $(LDFLAGS) $(OBJS) -lgcc -o $@

$(HEX): $(TARGET)
	riscv64-unknown-elf-objcopy -O verilog --only-section=.text $< $@

$(DATA_HEX): $(TARGET)
	riscv64-unknown-elf-objcopy -O verilog --only-section=.data $< $@

clean:
	rm -f $(OBJS) $(TARGET) $(HEX) $(DATA_HEX)

.PHONY: disasm
disasm: $(TARGET)
	riscv64-unknown-elf-objdump -d $< | head -100