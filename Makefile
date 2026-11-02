# Build, flash and monitor C3 programs on the ESP32-C5, bare metal.
#
#   make EX=uart                 build examples/uart  -> build/uart/app.bin
#   make EX=uart flash           flash it (image goes to 0x2000, replacing the
#                                bootloader; reflash ESP-IDF/Arduino to go back)
#   make monitor                 serial terminal, 115200 baud
#
# Needs ./init.sh to have run once.

EX     ?= uart
C3C    ?= $(HOME)/cousas/c3c/build/c3c
LLVM   ?= /opt/homebrew/opt/llvm/bin
LLD    ?= $(shell command -v ld.lld || echo $(LLVM)/ld.lld)
PORT   ?= $(firstword $(wildcard /dev/cu.usbserial-* /dev/cu.usbmodem*))
BAUD   ?= 460800
PY     := .venv/bin/python

ROMLD  := vendor/esp-idf/components/esp_rom/esp32c5/ld
B      := build/$(EX)
SRCS   := $(wildcard lib/*.c3) $(wildcard gen/*.c3) $(wildcard examples/$(EX)/*.c3)

# freertos-riscv32 gives native local-exec TLS and no libc; --use-stdlib=no
# because the C3 stdlib assumes an OS.
C3FLAGS := --target freertos-riscv32 --use-stdlib=no --no-entry --single-module=yes \
           --riscv-cpu=rvimac --riscv-abi=int-only --reloc=none -Os --safe=no
ASFLAGS := --target=riscv32-unknown-elf -march=rv32imac_zicsr_zifencei -mabi=ilp32 -mno-relax

.PHONY: all flash monitor clean
all: $(B)/app.bin

$(B)/crt0.o: rt/crt0.S
	@mkdir -p $(B)
	$(LLVM)/clang $(ASFLAGS) -c $< -o $@

$(B)/c3.o: $(SRCS)
	@mkdir -p $(B)
	$(C3C) compile-only $(SRCS) $(C3FLAGS) --obj-out $(B)/obj
	@mv $(B)/obj/*.o $@ && rmdir $(B)/obj

$(B)/app.elf: $(B)/crt0.o $(B)/c3.o ld/esp32c5.ld
	$(LLD) -T ld/esp32c5.ld -L $(ROMLD) --gc-sections --no-relax -Map=$(B)/app.map \
	    -o $@ $(B)/crt0.o $(B)/c3.o

$(B)/app.bin: $(B)/app.elf
	$(PY) -m esptool --chip esp32c5 elf2image --flash-mode dio --flash-freq 80m \
	    --flash-size 4MB -o $@ $<
	@$(LLVM)/llvm-size $< 2>/dev/null || true

flash: $(B)/app.bin
	$(PY) -m esptool --chip esp32c5 -p $(PORT) -b $(BAUD) write-flash \
	    --flash-mode keep --flash-freq keep --flash-size keep 0x2000 $<

monitor:
	$(PY) -m serial.tools.miniterm $(PORT) 115200

clean:
	rm -rf build
