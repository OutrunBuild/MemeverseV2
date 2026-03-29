#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <review-note> [review-note ...]"
    exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

mapfile -t required_headings < <(node ./script/process/read-process-config.js policy review_note.required_headings --lines)
mapfile -t required_fields < <(node ./script/process/read-process-config.js policy review_note.required_fields --lines)
mapfile -t boolean_fields < <(node ./script/process/read-process-config.js policy review_note.boolean_fields --lines)
mapfile -t owner_prefixed_source_fields < <(node ./script/process/read-process-config.js policy review_note.owner_prefixed_source_fields --lines)
mapfile -t placeholder_values < <(node ./script/process/read-process-config.js policy review_note.placeholder_values --lines)
field_owners_json="$(node ./script/process/read-process-config.js policy review_note.field_owners)"

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
    local angle_placeholder_pattern='<[^>]+>'

    if [[ "$value" =~ $angle_placeholder_pattern ]]; then
        return 0
    fi

    for placeholder in "${placeholder_values[@]}"; do
        if [ "$value" = "$placeholder" ]; then
            return 0
        fi
    done

    return 1
}

field_requires_owner_prefix() {
    local field="$1"

    case " ${owner_prefixed_source_fields[*]} " in
        *" $field "*) return 0 ;;
        *) return 1 ;;
    esac
}

owners_for_field() {
    local field="$1"

    FIELD_OWNERS_JSON="$field_owners_json" node -e '
const owners = JSON.parse(process.env.FIELD_OWNERS_JSON || "{}");
const field = process.argv[1];
process.stdout.write(String(owners[field] || ""));
' "$field"
}

validate_owner_prefix() {
    local file="$1"
    local field="$2"
    local value="$3"
    local owners_spec
    local owner
    local matched=1
    local source_payload

    owners_spec="$(owners_for_field "$field")"
    if [ -z "$owners_spec" ]; then
        echo "[check-review-note] ERROR: $file field '$field' is configured for owner-prefix validation but has no field owner mapping"
        exit 1
    fi

    IFS='|' read -r -a owners <<< "$owners_spec"
    for owner in "${owners[@]}"; do
        if [[ "$value" == "$owner:"* ]]; then
            source_payload="${value#"$owner:"}"
            source_payload="${source_payload#"${source_payload%%[![:space:]]*}"}"

            if [ -n "$source_payload" ]; then
                matched=0
                break
            fi
        fi
    done

    if [ "$matched" -ne 0 ]; then
        echo "[check-review-note] ERROR: $file field '$field' must use 'role: source' with one of the allowed owner prefixes: ${owners_spec//|/, }"
        exit 1
    fi
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

        if field_requires_owner_prefix "$field"; then
            validate_owner_prefix "$file" "$field" "$value"
        fi
    done
done

echo "[check-review-note] PASS"
