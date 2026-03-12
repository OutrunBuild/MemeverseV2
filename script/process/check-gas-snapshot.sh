#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

forge_bin="${FORGE_BIN:-forge}"
baseline_file="$(node ./script/process/read-process-config.js policy quality_gate.gas_snapshot_file)"
tolerance_percent="$(node ./script/process/read-process-config.js policy quality_gate.gas_snapshot_tolerance_percent)"

if [ ! -f "$baseline_file" ]; then
    echo "[check-gas-snapshot] ERROR: gas baseline file not found: $baseline_file"
    exit 1
fi

if ! "$forge_bin" snapshot --check "$baseline_file" --tolerance "$tolerance_percent"; then
    echo "[check-gas-snapshot] ERROR: gas snapshot check failed"
    exit 1
fi
