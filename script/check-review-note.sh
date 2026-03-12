#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <review-note> [review-note ...]"
    exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

mapfile -t required_headings < <(node ./script/read-process-config.js policy review_note.required_headings --lines)
mapfile -t required_fields < <(node ./script/read-process-config.js policy review_note.required_fields --lines)
mapfile -t boolean_fields < <(node ./script/read-process-config.js policy review_note.boolean_fields --lines)
mapfile -t placeholder_values < <(node ./script/read-process-config.js policy review_note.placeholder_values --lines)

field_is_required() {
    local field="$1"

    case " ${required_fields[*]} " in
        *" $field "*) return 0 ;;
        *) return 1 ;;
    esac
}

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

        case " ${boolean_fields[*]} " in
            *" $field "*)
                validate_boolean_field "$file" "$field" "$value"
                ;;
        esac
    done

    if field_is_required "None"; then
        none_value="$(extract_field "$file" "None")"
        if [ -z "$none_value" ]; then
            echo "[check-review-note] ERROR: $file field 'None' must explicitly state 'none' or explain why it is not applicable"
            exit 1
        fi
    fi
done
