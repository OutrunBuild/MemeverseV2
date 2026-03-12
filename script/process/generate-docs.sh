#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

out_dir="docs/contracts"
legacy_out_dir="docs/contracts-api"
tmp_dir="$(mktemp -d)"

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

forge doc --out "$tmp_dir"

generated_src_root="$tmp_dir/src"
generated_contracts="$generated_src_root/src"

if [ ! -d "$generated_contracts" ]; then
    echo "Expected generated contract docs under: $generated_contracts"
    exit 1
fi

rm -rf "$legacy_out_dir"
rm -rf "$out_dir"
mkdir -p "$out_dir"

cp "$generated_src_root/README.md" "$out_dir/README.md"
cp "$generated_src_root/SUMMARY.md" "$out_dir/SUMMARY.md"
cp -R "$generated_contracts"/. "$out_dir/"

while IFS= read -r -d '' markdown; do
    sed -i \
        -e 's|(/src/|(/|g' \
        -e 's|(src/|(|g' \
        "$markdown"
done < <(find "$out_dir" -type f -name '*.md' -print0)

if [ -f "$out_dir/SUMMARY.md" ]; then
    sed -i -e 's|^# src$|# contracts|' "$out_dir/SUMMARY.md"
fi
