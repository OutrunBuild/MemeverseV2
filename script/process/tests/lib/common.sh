#!/usr/bin/env bash

if [ "${PROCESS_SELFTEST_COMMON_LOADED:-0}" = "1" ]; then
    return 0
fi
PROCESS_SELFTEST_COMMON_LOADED=1

selftest::enter_repo_root() {
    local repo_root

    repo_root="$(git rev-parse --show-toplevel)"
    cd "$repo_root"
}

selftest::setup_tmpdir() {
    selftest_tmp_dir="$(mktemp -d)"
    tmp_dir="$selftest_tmp_dir"
    selftest_cleanup_paths=()
    trap 'selftest::cleanup' EXIT
}

selftest::cleanup() {
    local path

    if [ "${#selftest_cleanup_paths[@]}" -gt 0 ]; then
        for path in "${selftest_cleanup_paths[@]}"; do
            if [ -e "$path" ] || [ -L "$path" ]; then
                rm -rf "$path"
            fi
        done
    fi

    if [ -n "${tmp_dir:-}" ] && [ -e "$tmp_dir" ]; then
        rm -rf "$tmp_dir"
        tmp_dir=""
        selftest_tmp_dir=""
    elif [ -n "${selftest_tmp_dir:-}" ] && [ -e "$selftest_tmp_dir" ]; then
        rm -rf "$selftest_tmp_dir"
        selftest_tmp_dir=""
    fi
}

selftest::register_cleanup_path() {
    selftest_cleanup_paths+=("$@")
}

selftest::assert_text_contains() {
    local haystack="$1"
    local pattern="$2"
    local message="$3"

    if ! printf '%s\n' "$haystack" | grep -q -- "$pattern"; then
        echo "$message"
        printf '%s\n' "$haystack"
        exit 1
    fi
}

selftest::assert_text_lacks() {
    local haystack="$1"
    local pattern="$2"
    local message="$3"

    if printf '%s\n' "$haystack" | grep -q -- "$pattern"; then
        echo "$message"
        printf '%s\n' "$haystack"
        exit 1
    fi
}

selftest::assert_file_contains() {
    local path="$1"
    local pattern="$2"
    local message="$3"

    if ! grep -q -- "$pattern" "$path"; then
        echo "$message"
        cat "$path"
        exit 1
    fi
}
