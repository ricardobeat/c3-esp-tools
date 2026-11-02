# c3-esp-tools

Write bare-metal ESP32-C5 firmware in [C3](https://c3-lang.org), with no
ESP-IDF toolchain and no Arduino. C3 compiles through LLVM, so the only things
needed besides `c3c` are `clang` (for one assembly file), `lld` and `esptool`.

Nothing here uses boomkat, FreeRTOS or a libc. It is a starting point: a
startup file, a linker script, register bindings generated from ESP-IDF, a few
small drivers, and two examples.

## Setup

Needs `c3c` built from the `freertos-riscv32` branch of
`~/cousas/c3c` (override with `C3C=`), plus `brew install llvm lld`.

```sh
./init.sh                  # once
make EX=uart flash monitor
make EX=lcd  flash         # NM-CYD-C5 display test
```

`init.sh` sparse-clones ESP-IDF (`components/soc`, `esp_rom` and a memory map,
about 13 MB, no toolchain, no submodules), creates `.venv` with `esptool`, and
runs `scripts/gen_soc.py` to turn IDF's C register headers into C3 constants
under `gen/`. `./init.sh --idf PATH` links an existing checkout instead.

## Examples

| `EX=` | What it does |
|---|---|
| `uart` | Banner, echo of anything you type, a tick every second. Also calls a ROM function and uses `tlocal` variables. |
| `lcd` | Colour bars, grey ramp and a block "C3" on the NM-CYD-C5's ST7789, over bit-banged SPI. Pins are board-specific (see `examples/lcd/main.c3`). |

## Layout

```
init.sh            fetch ESP-IDF parts, esptool, generate bindings
Makefile           build / flash / monitor
rt/crt0.S          entry: sp, gp, .bss, TLS block + tp, trap vector -> c3_main
ld/esp32c5.ld      SRAM-only memory map; includes IDF's ROM symbol tables
lib/               mmio, rom, wdt, console (UART0), pin (GPIO), st7789, trap
gen/               generated: esp32c5::uart, ::gpio, ::io_mux, ::timg, ...
examples/          one directory per program, each defines c3_main
```

Registers are used like `mmio::write(uart::FIFO_REG, c)`, with names from
IDF's headers minus the peripheral prefix (`UART_FIFO_REG` is `uart::FIFO_REG`).
Registers that exist once per instance come out for instance 0, with a `STRIDE`
constant to reach the others.

## How it boots

The ESP32-C5 ROM loads an image from flash offset `0x2000`, copies its segments
into SRAM and jumps to the entry point. Normally that image is ESP-IDF's
second-stage bootloader. Here it is the program itself: `esptool elf2image`
turns the linked ELF into that format, and everything (code, data, stack) lives
in the 300 KB of SRAM below `0x4084B000`. There is no flash cache or MMU setup.

Because the ROM expects a bootloader to take over, the program must disable the
watchdogs itself (`wdt::disable_all()`), or the chip resets a few seconds in.

## Compiler target

Code is built with `--target freertos-riscv32 --use-stdlib=no`. That target
gives native local-exec thread-locals, so `tlocal` is `tp + constant`. `crt0.S`
builds a TLS block and sets `tp`, which is the contract a FreeRTOS port would
also have to meet. There is no scheduler here yet; the examples run on one
context.

Without the C3 stdlib there is no heap, `String`, formatting or panic handler.
The library prints numbers itself, and the build passes `--safe=no`.

## Caveats

- `make flash` writes `0x2000`, replacing the bootloader. To go back to
  Arduino or ESP-IDF, flash them again; they rewrite it.
- The display test bit-bangs SPI (about a second per full-screen fill). The
  SPI peripheral, DMA, PSRAM and interrupts are not set up.
- Only the ESP32-C5 is supported, and only tested on the NM-CYD-C5 board.
