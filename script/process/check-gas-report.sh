#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

forge_bin="${FORGE_BIN:-forge}"
tmp_dir="$(mktemp -d)"
snapshot_file="$tmp_dir/gas-snapshot.txt"

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

if ! "$forge_bin" snapshot --snap "$snapshot_file"; then
    echo "[check-gas-report] ERROR: gas report generation failed"
    exit 1
fi

if [ ! -s "$snapshot_file" ]; then
    echo "[check-gas-report] ERROR: gas report was not generated"
    exit 1
fi

echo "[check-gas-report] INFO: gas report"
cat "$snapshot_file"
