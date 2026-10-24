#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# run-matrix.sh — run the PIN-free checks and archive the result.
# Usage: ./tests/run-matrix.sh
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

arch=$(uname -m)
stamp=$(date +%Y%m%d-%H%M%S)
out="artifacts/matrix-${arch}-${stamp}.txt"
mkdir -p artifacts

status=0
{
  echo "arch=${arch}"
  echo "date=${stamp}"
  echo "kernel=$(uname -r)"
  echo "opensc=$(opensc-tool --version 2>/dev/null | head -1)"
  echo "pcscd=$(pcscd --version 2>/dev/null | head -1)"
  echo
  echo "===== verify-stack ====="
  ./scripts/verify-stack.sh || status=1
  echo
  echo "===== verify-card ====="
  ./scripts/verify-card.sh || status=1
} 2>&1 | tee "$out"

echo
echo "Result archived at: $out"
exit "$status"
