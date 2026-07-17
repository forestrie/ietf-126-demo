#!/usr/bin/env bash
#
# Slide 4 — Throughput and latency: 100 statements, one checkpoint.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]:-$0}")/demo-lib.sh"
demo_init 04

note 'batch-receipts.ts reads ROBERT_LOG_ID / ROBERT_PEM / ROOT_GRANT_B64 from the env'
run 'N=100 bun batch-receipts.ts'
