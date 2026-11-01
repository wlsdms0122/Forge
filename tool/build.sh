#!/bin/bash
# Builds the release binary and leaves it at `.build/forge`, one address that
# does not move when Swift rearranges its own build directory.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build=(swift build --package-path "$root/package" -c release)

"${build[@]}"

# Asked for rather than spelled out: the bin path is named after the
# toolchain's layout.
product="$("${build[@]}" --show-bin-path)/forge"

[ -f "$product" ] || { echo "built, but no product at $product" >&2; exit 1; }

mkdir -p "$root/.build"
install -m 0755 "$product" "$root/.build/forge"

echo ".build/forge"
"$root/.build/forge" --version
