#!/usr/bin/env python3
"""Generate C3 constant modules from ESP-IDF's ESP32-C5 register headers.

usage: gen_soc.py <esp-idf dir> <output dir>

C3 cannot read C headers, so every `#define` the headers hold for a peripheral
is evaluated here and written out as `const uint NAME = 0x...;` in a module
named after the peripheral (esp32c5::uart, esp32c5::gpio, ...). The peripheral
prefix is dropped: UART_FIFO_REG becomes uart::FIFO_REG.

Registers that exist once per instance (UART_FIFO_REG(i), TIMG_WDTCONFIG0_REG(i))
are emitted for instance 0, plus a STRIDE constant to reach the others.
"""
import re
import sys
from pathlib import Path

# module name, header, prefixes to strip, number of instances for indexed macros
PERIPHERALS = [
    ("reg_base", "reg_base.h", ["DR_REG_"]),
    ("uart", "uart_reg.h", ["UART_"]),
    ("gpio", "gpio_reg.h", ["GPIO_"]),
    ("io_mux", "io_mux_reg.h", ["IO_MUX_"]),
    ("timg", "timer_group_reg.h", ["TIMG_"]),
    ("lp_wdt", "lp_wdt_reg.h", ["LP_WDT_"]),
    ("pcr", "pcr_reg.h", ["PCR_"]),
    ("systimer", "systimer_reg.h", ["SYSTIMER_"]),
    ("spi", "spi_reg.h", ["SPI_"]),
]

CASTS = re.compile(
    r"\(\s*(?:u?int(?:8|16|32|64)_t|unsigned(?:\s+int|\s+long)?|int|long|size_t)\s*\)")
SUFFIX = re.compile(r"\b(0[xX][0-9a-fA-F]+|\d+)[uUlL]+\b")
DEFINE = re.compile(r"^\s*#\s*define\s+(\w+)(\([^)]*\))?(?:\s+(.*))?$")
VALID = re.compile(r"^[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*$")


def read_defines(path):
    text = path.read_text(errors="replace")
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    text = text.replace("\\\n", " ")
    out = {}
    for line in text.splitlines():
        m = DEFINE.match(line)
        if not m:
            continue
        name, params, body = m.group(1), m.group(2), (m.group(3) or "").strip()
        plist = None
        if params:
            plist = [p.strip() for p in params[1:-1].split(",") if p.strip()]
        out[name] = (plist, body)
    return out


def to_python(expr):
    expr = CASTS.sub("", expr)
    expr = SUFFIX.sub(r"\1", expr)
    expr = re.sub(r"\bBIT\s*\(", "_bit(", expr)
    expr = expr.replace("&&", " and ").replace("||", " or ")
    expr = re.sub(r"(?<![/])/(?![/])", "//", expr)
    return expr


class Env(dict):
    """Evaluation scope: unknown names are looked up (and cached) as macros."""

    def __init__(self, macros, cache, bound=None):
        super().__init__(bound or {})
        self.macros, self.cache = macros, cache
        self["_bit"] = lambda n: 1 << n

    def __missing__(self, name):
        if name not in self.macros:
            raise KeyError(name)
        params, body = self.macros[name]
        if params is not None:
            fn = self.make_function(params, body)
            return fn
        if name in self.cache:
            value = self.cache[name]
        else:
            self.cache[name] = None  # break cycles
            value = eval(to_python(body), {"__builtins__": {}},
                         Env(self.macros, self.cache))
            self.cache[name] = value
        if value is None:
            raise KeyError(name)
        return value

    def make_function(self, params, body):
        def call(*args):
            scope = Env(self.macros, self.cache, dict(zip(params, args)))
            return eval(to_python(body), {"__builtins__": {}}, scope)
        return call


def evaluate(name, macros, cache, index=0):
    params, body = macros[name]
    if params is None:
        if not body:
            return None
        return Env(macros, cache)[name]
    if len(params) != 1:
        return None
    return eval(to_python(body), {"__builtins__": {}},
                Env(macros, cache, {params[0]: index}))


def main():
    idf, out = Path(sys.argv[1]), Path(sys.argv[2])
    soc = idf / "components/soc/esp32c5"
    regdir = soc / "register/soc"
    macros = {}
    for header in [soc / "include/soc/soc.h", *regdir.glob("*.h")]:
        macros.update(read_defines(header))
    cache = {}
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.c3"):
        old.unlink()

    total = 0
    for module, header, prefixes in PERIPHERALS:
        own = read_defines(regdir / header)
        consts, stride = {}, None
        for name, (params, body) in sorted(own.items()):
            try:
                value = evaluate(name, macros, cache)
                if value is None or not isinstance(value, int):
                    continue
                if params is not None:
                    other = evaluate(name, macros, cache, 1)
                    if other is not None and stride in (None, other - value):
                        stride = other - value
            except Exception:
                continue
            short = name
            for p in prefixes:
                if name.startswith(p) and VALID.match(name[len(p):] or "_"):
                    short = name[len(p):]
                    break
            if not VALID.match(short) or "__" in short or short in consts:
                continue
            consts[short] = value & 0xFFFFFFFF
        if stride:
            consts.setdefault("STRIDE", stride & 0xFFFFFFFF)
        lines = [
            "// Generated by scripts/gen_soc.py from ESP-IDF's "
            f"components/soc/esp32c5/register/soc/{header}",
            "// (Apache-2.0, Espressif). Do not edit.",
            f"module esp32c5::{module};",
            "",
        ]
        lines += [f"const uint {n} = 0x{v:X};" for n, v in sorted(consts.items())]
        (out / f"{module}.c3").write_text("\n".join(lines) + "\n")
        total += len(consts)
        print(f"  {module:9} {len(consts):5} constants")
    print(f"wrote {total} constants to {out}/")


if __name__ == "__main__":
    main()
