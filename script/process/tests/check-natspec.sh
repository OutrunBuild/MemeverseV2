#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

selftest::enter_repo_root
selftest::setup_tmpdir

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

selftest::assert_text_contains "$missing_output" "missing" "Expected missing NatSpec failure output"

bash ./script/process/check-natspec.sh "$passing_file"
