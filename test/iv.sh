#!/bin/sh
# iv.sh — run iverilog without its known-harmless "sorry" notices (unsupported
# but irrelevant SystemVerilog qualifiers). Real warnings and errors still
# print, and iverilog's exit status is kept, so a broken build still fails.
out=$(iverilog "$@" 2>&1); status=$?
printf '%s\n' "$out" | grep -v 'sorry:' | grep -v '^$'
exit $status
