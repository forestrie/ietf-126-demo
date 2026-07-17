#!/usr/bin/env bash
#
# Slide 4 — Throughput and latency: 100 statements, one checkpoint.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]:-$0}")/demo-lib.sh"
demo_init 04

note "publish 100 statements at once — a single checkpoint covers them all, and every receipt derives offline"
run 'N=100 bun batch-receipts.ts'
