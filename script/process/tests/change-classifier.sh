#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

selftest::enter_repo_root
selftest::setup_tmpdir
file_list="$tmp_dir/files.txt"
patch_file="$tmp_dir/diff.patch"
output_json="$tmp_dir/classifier.json"

run_classifier() {
    local changed_file="$1"
    local patch_content="$2"

    printf '%s\n' "$changed_file" > "$file_list"
    printf '%s\n' "$patch_content" > "$patch_file"

    QUALITY_GATE_MODE=ci \
    QUALITY_GATE_FILE_LIST="$file_list" \
    CHANGE_CLASSIFIER_DIFF_FILE="$patch_file" \
    node ./script/process/classify-change.js --json > "$output_json"
}

assert_field() {
    local field="$1"
    local expected="$2"
    local actual

    actual="$(node -e '
const fs = require("fs");
const document = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
let value = document;
for (const key of process.argv[2].split(".")) {
  if (key === "") continue;
  value = value[key];
}
if (Array.isArray(value)) {
  process.stdout.write(value.join(","));
} else {
  process.stdout.write(String(value));
}
' "$output_json" "$field")"

    if [ "$actual" != "$expected" ]; then
        echo "Expected $field='$expected', got '$actual'"
        cat "$output_json"
        exit 1
    fi
}

run_classifier \
  "src/router/CommentOnly.sol" \
  "diff --git a/src/router/CommentOnly.sol b/src/router/CommentOnly.sol
--- a/src/router/CommentOnly.sol
+++ b/src/router/CommentOnly.sol
@@ -10 +10 @@
-    // old comment
+    // new comment"
assert_field "classification" "non-semantic"
assert_field "verifier_profile" "light"
assert_field "required_roles" "verifier"

run_classifier \
  "test/router/Router.t.sol" \
  "diff --git a/test/router/Router.t.sol b/test/router/Router.t.sol
--- a/test/router/Router.t.sol
+++ b/test/router/Router.t.sol
@@ -42 +42 @@
-        assertEq(result, 1);
+        assertEq(result, 2);"
assert_field "classification" "test-semantic"
assert_field "verifier_profile" "light"
assert_field "required_roles" "logic-reviewer,verifier"

run_classifier \
  "src/misc/RouterHelper.sol" \
 "diff --git a/src/misc/RouterHelper.sol b/src/misc/RouterHelper.sol
--- a/src/misc/RouterHelper.sol
+++ b/src/misc/RouterHelper.sol
@@ -20 +20 @@
-        return nextNonce;
+        return nextNonce + 1;"
assert_field "classification" "prod-semantic"
assert_field "verifier_profile" "full"
assert_field "required_roles" "logic-reviewer,security-reviewer,gas-reviewer,verifier"

run_classifier \
  "src/router/Router.sol" \
  "diff --git a/src/router/Router.sol b/src/router/Router.sol
--- a/src/router/Router.sol
+++ b/src/router/Router.sol
@@ -20 +20 @@
-        return amount;
+        token.safeTransfer(msg.sender, amount);"
assert_field "classification" "high-risk"
assert_field "verifier_profile" "full"

echo "change-classifier selftest: PASS"
