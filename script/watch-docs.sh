#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

echo "Watching Solidity files under src/ for doc regeneration..."
last_fingerprint=""

while true; do
    fingerprint="$(find src -type f -name '*.sol' -print0 | xargs -0 sha256sum | sha256sum | awk '{print $1}')"

    if [ "$fingerprint" != "$last_fingerprint" ]; then
        bash ./script/generate-docs.sh
        last_fingerprint="$fingerprint"
        echo "Docs updated in docs/contracts"
    fi

    sleep 1
done
