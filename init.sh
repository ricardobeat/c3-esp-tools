#!/usr/bin/env bash
# One-time setup. Fetches only what C3 needs from ESP-IDF (register headers, the
# ROM symbol tables and the memory map) with a sparse partial clone: no compiler
# toolchain, no submodules, a few MB. Also creates a venv with esptool and
# generates the C3 register bindings into gen/.
#
#   ./init.sh                    sparse-clone ESP-IDF (IDF_TAG, default v6.1)
#   ./init.sh --idf PATH         link an existing ESP-IDF checkout instead
#   ./init.sh --update           re-fetch and regenerate
set -euo pipefail
cd "$(dirname "$0")"

IDF_REPO=${IDF_REPO:-https://github.com/espressif/esp-idf.git}
IDF_TAG=${IDF_TAG:-v6.1}
C3C=${C3C:-$HOME/cousas/c3c/build/c3c}
LLVM=${LLVM:-/opt/homebrew/opt/llvm/bin}
LLD=${LLD:-$(command -v ld.lld || echo "$LLVM/ld.lld")}

# The only parts of ESP-IDF this project reads.
SPARSE_DIRS=(
  components/soc/esp32c5/register   # peripheral register definitions
  components/soc/esp32c5/include    # soc.h: REG_*_BASE(i) helpers
  components/esp_rom/esp32c5/ld     # ROM function addresses (printf, delay, ...)
  components/esp_system/ld/esp32c5  # reference memory map
)

idf_arg=""; update=0
while [ $# -gt 0 ]; do
  case $1 in
    --idf) idf_arg=$2; shift 2 ;;
    --update) update=1; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
missing=0
need() { # tool, hint
  if ! command -v "$1" >/dev/null 2>&1 && [ ! -x "$1" ]; then
    echo "missing: $1  ($2)" >&2; missing=1
  fi
}

say "checking tools"
need git "xcode-select --install"
need python3 "brew install python"
need "$C3C" "build ~/cousas/c3c on the freertos-riscv32 branch, or set C3C=/path/to/c3c"
need "$LLVM/clang" "brew install llvm"
need "$LLD" "brew install lld"
need "$LLVM/llvm-objdump" "brew install llvm"
[ $missing = 0 ] || exit 1
if ! "$C3C" --list-targets 2>&1 | tr ' ' '\n' | grep -qx freertos-riscv32; then
  echo "$C3C has no freertos-riscv32 target; build the c3c freertos-riscv32 branch" >&2; exit 1
fi
if ! "$LLVM/clang" --print-targets | grep -q riscv32; then
  echo "$LLVM/clang has no riscv32 target" >&2; exit 1
fi

say "ESP-IDF sources"
mkdir -p vendor
if [ -n "$idf_arg" ]; then
  rm -rf vendor/esp-idf
  ln -s "$(cd "$idf_arg" && pwd)" vendor/esp-idf
  echo "linked vendor/esp-idf -> $idf_arg"
else
  if [ $update = 1 ]; then rm -rf vendor/esp-idf; fi
  if [ ! -d vendor/esp-idf ]; then
    git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$IDF_TAG" --filter=blob:none --sparse \
      "$IDF_REPO" vendor/esp-idf
    git -C vendor/esp-idf sparse-checkout set "${SPARSE_DIRS[@]}"
  fi
  du -sh vendor/esp-idf | sed 's/^/fetched /'
fi
for d in "${SPARSE_DIRS[@]}"; do
  [ -d "vendor/esp-idf/$d" ] || { echo "vendor/esp-idf/$d is missing" >&2; exit 1; }
done

say "esptool (venv)"
if [ ! -x .venv/bin/python ] || [ $update = 1 ]; then
  python3 -m venv .venv
  .venv/bin/pip install --quiet --upgrade pip
  .venv/bin/pip install --quiet "esptool>=5"
fi
.venv/bin/python -m esptool version | tail -1

say "C3 register bindings"
python3 scripts/gen_soc.py vendor/esp-idf gen

say "done. Try: make EX=uart flash monitor"
