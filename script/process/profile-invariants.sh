#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

forge_bin="${FORGE_BIN:-forge}"
verbosity="${PROFILE_INVARIANTS_VERBOSITY:--vv}"
tmp_log="$(mktemp)"
trap 'rm -f "$tmp_log"' EXIT

echo "[profile-invariants] running: $forge_bin test $verbosity --match-test '^invariant_'"
"$forge_bin" test "$verbosity" --match-test '^invariant_' | tee "$tmp_log"

echo "[profile-invariants] suite timing (sorted):"
LOG_PATH="$tmp_log" node <<'EOF'
const fs = require('fs');

const logPath = process.env.LOG_PATH;
const lines = fs.readFileSync(logPath, 'utf8').split(/\r?\n/);
const results = [];
let pendingSuite = '';

function toMs(value, unit) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return 0;
  switch (unit) {
    case 's': return numeric * 1000;
    case 'ms': return numeric;
    case 'us': return numeric / 1000;
    case 'ns': return numeric / 1_000_000;
    default: return numeric;
  }
}

for (const line of lines) {
  const suiteMatch = line.match(/^Ran .* for (.+)$/);
  if (suiteMatch) {
    pendingSuite = suiteMatch[1].trim();
    continue;
  }

  const timingMatch = line.match(/^Suite result: .*finished in ([0-9.]+)(s|ms|us|ns)\b/);
  if (timingMatch) {
    const durationMs = toMs(timingMatch[1], timingMatch[2]);
    const suiteName = pendingSuite || '(unknown suite)';
    results.push({ suiteName, durationMs, raw: `${timingMatch[1]}${timingMatch[2]}` });
    pendingSuite = '';
  }
}

results.sort((a, b) => b.durationMs - a.durationMs);
if (results.length === 0) {
  process.stdout.write('[profile-invariants] no suite timing lines parsed. Try PROFILE_INVARIANTS_VERBOSITY=-vvv.\n');
  process.exit(0);
}
for (const [index, entry] of results.entries()) {
  process.stdout.write(`${String(index + 1).padStart(2, '0')}. ${entry.raw.padStart(8, ' ')}  ${entry.suiteName}\n`);
}
EOF
