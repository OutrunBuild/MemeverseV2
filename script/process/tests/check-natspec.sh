#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

missing_file="$tmp_dir/MissingNatSpec.sol"
passing_file="$tmp_dir/PassingNatSpec.sol"

cat > "$missing_file" <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MissingNatSpec {
    function missingDoc(address receiver, uint256 amount) external returns (uint256 mintedAmount) {
        return amount;
    }
}
EOF

cat > "$passing_file" <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract PassingNatSpec {
    /**
     * @notice Mints tokens for a receiver.
     * @dev Minimal passing NatSpec coverage for the P1 gate.
     * @param receiver Recipient of the minted amount.
     * @param amount Amount to mint.
     * @return mintedAmount Amount minted for the receiver.
     */
    function mint(address receiver, uint256 amount) external returns (uint256 mintedAmount) {
        return amount;
    }
}
EOF

set +e
missing_output="$(bash ./script/process/check-natspec.sh "$missing_file" 2>&1)"
missing_status=$?
set -e

if [ "$missing_status" -eq 0 ]; then
    echo "Expected missing NatSpec fixture to fail"
    exit 1
fi

if ! printf '%s\n' "$missing_output" | grep -q "missing"; then
    echo "Expected missing NatSpec failure output"
    printf '%s\n' "$missing_output"
    exit 1
fi

bash ./script/process/check-natspec.sh "$passing_file"
