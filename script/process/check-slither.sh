#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 0 ]; then
    echo "Usage: $0"
    exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

slither_bin="${SLITHER_BIN:-slither}"
slither_target="${SLITHER_TARGET:-.}"
filter_paths="$(node ./script/process/read-process-config.js policy quality_gate.slither_filter_paths)"
exclude_detectors="$(node ./script/process/read-process-config.js policy quality_gate.slither_exclude_detectors)"

tmp_dir="$(mktemp -d)"
slither_json="$tmp_dir/slither.json"
normalized_output="$tmp_dir/slither.normalized"
slither_stderr="$tmp_dir/slither.stderr"

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

set +e
"$slither_bin" "$slither_target" \
    --filter-paths "$filter_paths" \
    --exclude-dependencies \
    --exclude "$exclude_detectors" \
    --json "$slither_json" \
    2> "$slither_stderr"
slither_status=$?
set -e

if ! node ./script/process/normalize-slither-results.js "$slither_json" > "$normalized_output" 2>/dev/null; then
    echo "[check-slither] ERROR: slither failed"
    if [ -s "$slither_stderr" ]; then
        cat "$slither_stderr" >&2
    fi
    exit 1
fi

if [ -s "$normalized_output" ]; then
    echo "[check-slither] INFO: normalized findings"
    cat "$normalized_output"
else
    echo "[check-slither] INFO: no normalized findings"
fi

if [ "$slither_status" -ne 0 ]; then
    echo "[check-slither] INFO: slither returned status $slither_status with parseable findings"
fi
