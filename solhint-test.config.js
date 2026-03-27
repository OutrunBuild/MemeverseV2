const base = require("./solhint.config");

module.exports = {
    ...base,
    rules: {
        ...base.rules,
        "avoid-low-level-calls": "off",
        "check-send-result": "off",
        "gas-custom-errors": "off",
        "gas-calldata-parameters": "off",
        "gas-increment-by-one": "off",
        "gas-length-in-loops": "off",
        "gas-strict-inequalities": "off",
        "gas-small-strings": "off",
        "multiple-sends": "off",
        "no-console": "off",
        "one-contract-per-file": "off"
    }
};
