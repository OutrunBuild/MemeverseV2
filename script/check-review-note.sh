#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <review-note> [review-note ...]"
    exit 1
fi

required_headings=(
    "## Scope"
    "## Impact"
    "## Findings"
    "## Simplification"
    "## Docs"
    "## Tests"
    "## Verification"
    "## Decision"
)

required_fields=(
    "Change summary"
    "Files reviewed"
    "Behavior change"
    "ABI change"
    "Storage layout change"
    "Config change"
    "High findings"
    "Medium findings"
    "Low findings"
    "None"
    "Candidate simplifications considered"
    "Applied"
    "Rejected (with reason)"
    "Docs updated"
    "Why these docs"
    "No-doc reason"
    "Tests updated"
    "Existing tests exercised"
    "No-test-change reason"
    "Commands run"
    "Results"
    "Ready to commit"
    "Residual risks"
)

placeholder_values=(
    ""
    "TBD"
    "<path>"
    "<path>|none"
    "<selectors or paths>"
    "yes/no"
)

extract_field() {
    local file="$1"
    local field="$2"

    awk -v field="$field" '
        index($0, "- " field ":") == 1 {
            value = substr($0, length("- " field ":") + 1)
            sub(/^ /, "", value)
            print value
            exit
        }
    ' "$file"
}

is_placeholder() {
    local value="$1"
    shift

    for placeholder in "${placeholder_values[@]}"; do
        if [ "$value" = "$placeholder" ]; then
            return 0
        fi
    done

    return 1
}

validate_boolean_field() {
    local file="$1"
    local field="$2"
    local value="$3"

    if [ "$value" != "yes" ] && [ "$value" != "no" ]; then
        echo "[check-review-note] ERROR: $file field '$field' must be 'yes' or 'no'"
        exit 1
    fi
}

for file in "$@"; do
    if [ ! -f "$file" ]; then
        echo "[check-review-note] ERROR: review note not found: $file"
        exit 1
    fi

    for heading in "${required_headings[@]}"; do
        if ! grep -qF "$heading" "$file"; then
            echo "[check-review-note] ERROR: $file is missing required heading: $heading"
            exit 1
        fi
    done

    for field in "${required_fields[@]}"; do
        value="$(extract_field "$file" "$field")"
        if is_placeholder "$value"; then
            echo "[check-review-note] ERROR: $file field '$field' is empty or still uses a placeholder"
            exit 1
        fi

        case "$field" in
            "Behavior change"|"ABI change"|"Storage layout change"|"Config change"|"Ready to commit")
                validate_boolean_field "$file" "$field" "$value"
                ;;
        esac
    done

    none_value="$(extract_field "$file" "None")"
    if [ -z "$none_value" ]; then
        echo "[check-review-note] ERROR: $file field 'None' must explicitly state 'none' or explain why it is not applicable"
        exit 1
    fi
done
