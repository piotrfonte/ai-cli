#!/bin/bash
# Sample the oMLX process's REAL memory while a test runs.
#
# `ps -o rss` is the wrong tool here and W17 said so: MLX allocates through
# IOAccelerator, so RSS misses the Metal pages. Measured on this box with two
# models resident, RSS read 18.64 GB against a phys_footprint of 31 GB — a
# 1.66x under-read. oMLX prices itself on phys_footprint, so that is what this
# samples.
#
# usage: sample-footprint.sh <pid> <outfile> [interval_s]
set -u
PID=$1
OUT=$2
INT=${3:-3}
: > "$OUT"
while kill -0 "$PID" 2>/dev/null; do
  fp=$(footprint -p "$PID" 2>/dev/null | awk '/phys_footprint:/ {print $2, $3}')
  printf '%s %s\n' "$(date +%s)" "${fp:-NA}" >> "$OUT"
  sleep "$INT"
done
