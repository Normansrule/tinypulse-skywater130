#!/bin/sh
# fetch.sh — download the official RISC-V architecture tests used by run_act.py.
#
# Source: https://github.com/riscv-non-isa/riscv-arch-test, branch
# old-framework-2.x — the last framework that ships precomputed reference
# signatures, so no golden-model simulator is needed to check results.
# Only the RV32E base-instruction tests and their shared headers are kept.
set -e
cd "$(dirname "$0")"
URL=https://codeload.github.com/riscv-non-isa/riscv-arch-test/tar.gz/refs/heads/old-framework-2.x
EXPECT=3fd2d35c59a497bfa39ba8ceb1817d85c2f5f0fc39794057326411af42f9c71d
curl -sL --fail -o arch-test.tgz "$URL"
GOT=$(sha256sum arch-test.tgz | cut -c1-64)
if [ "$GOT" != "$EXPECT" ]; then
    echo "note: the archive differs from the one these results were recorded against"
    echo "      (expected $EXPECT, got $GOT) — the branch may have been updated"
fi
rm -rf riscv-arch-test && mkdir riscv-arch-test
tar -xzf arch-test.tgz --strip-components=1 -C riscv-arch-test \
    --wildcards '*/riscv-test-suite/rv32e_unratified/E/*' '*/riscv-test-suite/env/*' '*/LICENSE*'
rm arch-test.tgz
echo "fetched $(ls riscv-arch-test/riscv-test-suite/rv32e_unratified/E/src | wc -l) RV32E tests into act/riscv-arch-test"
