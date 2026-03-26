#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

function usage() {
  console.error('Usage: check-coverage.js <changed-files-list> <lcov-report-file>');
  process.exit(1);
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function toPosixPath(input) {
  return input.replace(/\\/g, '/');
}

function normalizeSourcePath(repoRoot, sourcePath) {
  const normalizedRaw = toPosixPath(sourcePath.trim());
  if (normalizedRaw === '') return '';

  if (path.isAbsolute(sourcePath)) {
    const relativePath = toPosixPath(path.relative(repoRoot, sourcePath));
    if (relativePath.startsWith('../') || relativePath === '..') return '';
    return relativePath;
  }

  if (normalizedRaw.startsWith('./')) return normalizedRaw.slice(2);
  return normalizedRaw;
}

function parseLcovReport(repoRoot, lcovText) {
  const files = new Map();
  const lines = lcovText.split(/\r?\n/);
  let current = null;

  for (const line of lines) {
    if (line.startsWith('SF:')) {
      const source = normalizeSourcePath(repoRoot, line.slice(3));
      if (source === '') {
        current = null;
        continue;
      }

      current = {
        source,
        lineTotal: 0,
        lineCovered: 0,
        functionNames: new Set(),
        functionHits: new Map(),
        branchTotal: 0,
        branchCovered: 0
      };
      files.set(source, current);
      continue;
    }

    if (current == null) continue;

    if (line.startsWith('DA:')) {
      const [lineNo, hits] = line.slice(3).split(',');
      if (lineNo != null && hits != null) {
        current.lineTotal += 1;
        if (Number(hits) > 0) current.lineCovered += 1;
      }
      continue;
    }

    if (line.startsWith('FN:')) {
      const segments = line.slice(3).split(',');
      const functionName = segments.slice(1).join(',').trim();
      if (functionName !== '') current.functionNames.add(functionName);
      continue;
    }

    if (line.startsWith('FNDA:')) {
      const segments = line.slice(5).split(',');
      if (segments.length < 2) continue;
      const hits = Number(segments[0]);
      const functionName = segments.slice(1).join(',').trim();
      if (functionName === '') continue;
      current.functionNames.add(functionName);
      current.functionHits.set(functionName, hits > 0);
      continue;
    }

    if (line.startsWith('BRDA:')) {
      const segments = line.slice(5).split(',');
      if (segments.length < 4) continue;
      current.branchTotal += 1;
      const taken = segments[3];
      if (taken !== '-' && Number(taken) > 0) current.branchCovered += 1;
      continue;
    }
  }

  const result = new Map();
  for (const [source, metrics] of files.entries()) {
    let functionCovered = 0;
    for (const functionName of metrics.functionNames) {
      if (metrics.functionHits.get(functionName) === true) functionCovered += 1;
    }

    result.set(source, {
      line: { covered: metrics.lineCovered, total: metrics.lineTotal },
      function: { covered: functionCovered, total: metrics.functionNames.size },
      branch: { covered: metrics.branchCovered, total: metrics.branchTotal }
    });
  }

  return result;
}

function findBestTierPath(filePath, tierPaths) {
  let best = null;
  for (const tierPath of tierPaths) {
    if (filePath === tierPath || filePath.startsWith(`${tierPath}/`)) {
      if (best == null || tierPath.length > best.length) best = tierPath;
    }
  }
  return best;
}

function findTierFiles(tierPath, fileMetrics) {
  const matchedFiles = [];
  for (const [sourcePath] of fileMetrics.entries()) {
    if (sourcePath === tierPath || sourcePath.startsWith(`${tierPath}/`)) {
      matchedFiles.push(sourcePath);
    }
  }
  return matchedFiles;
}

function parseBoolean(value, fallback) {
  if (typeof value === 'boolean') return value;
  return fallback;
}

function asNumber(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  return undefined;
}

function parseMetricsList(rawValue) {
  if (typeof rawValue !== 'string' || rawValue.trim() === '') {
    return ['line', 'function', 'branch'];
  }

  const allowed = new Set(['line', 'function', 'branch']);
  const parsed = rawValue
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean);

  if (parsed.length === 0) {
    return ['line', 'function', 'branch'];
  }

  const unique = [];
  for (const metric of parsed) {
    if (!allowed.has(metric)) {
      console.error(`[check-coverage] ERROR: unsupported metric '${metric}'. Allowed: line,function,branch`);
      process.exit(1);
    }
    if (!unique.includes(metric)) unique.push(metric);
  }
  return unique;
}

const [, , changedFilesListPath, lcovReportPath] = process.argv;
if (!changedFilesListPath || !lcovReportPath) usage();

if (!fs.existsSync(changedFilesListPath)) {
  console.error(`[check-coverage] ERROR: changed files list not found: ${changedFilesListPath}`);
  process.exit(1);
}

if (!fs.existsSync(lcovReportPath)) {
  console.error(`[check-coverage] ERROR: lcov report not found: ${lcovReportPath}`);
  process.exit(1);
}

const repoRoot = process.cwd();
const policyPath = process.env.PROCESS_POLICY_FILE || 'docs/process/policy.json';
const policy = readJson(path.resolve(policyPath));
const coveragePolicy = policy?.quality_gate?.coverage || {};
const tiers = Array.isArray(coveragePolicy.tiers) ? coveragePolicy.tiers : [];

if (tiers.length === 0) {
  console.error('[check-coverage] ERROR: quality_gate.coverage.tiers is empty');
  process.exit(1);
}

const failOnMissingData = parseBoolean(coveragePolicy.fail_on_missing_data, true);
const onlyChangedTiers = parseBoolean(coveragePolicy.only_changed_tiers, true);
const defaultThresholds = coveragePolicy.default_thresholds || {};
const srcPatternText = policy?.quality_gate?.src_sol_pattern || '^src/.*\\.sol$';

let srcPattern;
try {
  srcPattern = new RegExp(srcPatternText);
} catch (error) {
  console.error(`[check-coverage] ERROR: invalid src_sol_pattern regex: ${srcPatternText}`);
  process.exit(1);
}

const tierMap = new Map();
for (const tier of tiers) {
  if (!tier || typeof tier.path !== 'string' || tier.path.trim() === '') {
    console.error('[check-coverage] ERROR: every coverage tier must define a non-empty string path');
    process.exit(1);
  }
  const normalizedTierPath = toPosixPath(tier.path.trim().replace(/\/+$/, ''));
  tierMap.set(normalizedTierPath, tier);
}

const tierPaths = [...tierMap.keys()];
const changedFiles = fs.readFileSync(changedFilesListPath, 'utf8')
  .split(/\r?\n/)
  .map((entry) => toPosixPath(entry.trim()))
  .filter(Boolean);

const targetTierPaths = new Set();
if (onlyChangedTiers) {
  const changedSourceFiles = changedFiles.filter((entry) => srcPattern.test(entry));
  for (const sourceFile of changedSourceFiles) {
    const tierPath = findBestTierPath(sourceFile, tierPaths);
    if (tierPath) targetTierPaths.add(tierPath);
  }
} else {
  for (const tierPath of tierPaths) targetTierPaths.add(tierPath);
}

if (targetTierPaths.size === 0) {
  console.log('[check-coverage] no coverage tiers matched current source changes, skipping.');
  process.exit(0);
}

const lcovReport = fs.readFileSync(lcovReportPath, 'utf8');
if (lcovReport.trim() === '') {
  console.error('[check-coverage] ERROR: lcov report is empty');
  process.exit(1);
}

const fileMetrics = parseLcovReport(repoRoot, lcovReport);
if (fileMetrics.size === 0) {
  console.error('[check-coverage] ERROR: no valid source files found in lcov report');
  process.exit(1);
}

const metrics = parseMetricsList(process.env.COVERAGE_METRICS || '');
const failures = [];
const passes = [];

for (const tierPath of targetTierPaths) {
  const tierConfig = tierMap.get(tierPath);
  const matchedFiles = findTierFiles(tierPath, fileMetrics);

  if (matchedFiles.length === 0) {
    if (failOnMissingData) {
      failures.push(`${tierPath}: no coverage data found for this tier`);
    } else {
      passes.push(`${tierPath}: no coverage data found (allowed by policy)`);
    }
    continue;
  }

  const totals = {
    line: { covered: 0, total: 0 },
    function: { covered: 0, total: 0 },
    branch: { covered: 0, total: 0 }
  };

  for (const filePath of matchedFiles) {
    const metricSet = fileMetrics.get(filePath);
    for (const metric of metrics) {
      totals[metric].covered += metricSet[metric].covered;
      totals[metric].total += metricSet[metric].total;
    }
  }

  for (const metric of metrics) {
    const explicitThreshold = asNumber(tierConfig?.[metric]);
    const defaultThreshold = asNumber(defaultThresholds?.[metric]);
    const threshold = explicitThreshold ?? defaultThreshold;

    if (threshold == null) continue;

    if (totals[metric].total === 0) {
      if (failOnMissingData) {
        failures.push(`${tierPath} ${metric}: no measurable entries in lcov`);
      } else {
        passes.push(`${tierPath} ${metric}: no measurable entries (allowed by policy)`);
      }
      continue;
    }

    const actual = (totals[metric].covered / totals[metric].total) * 100;
    const formattedActual = actual.toFixed(2);
    const formattedThreshold = threshold.toFixed(2);
    const resultText = `${tierPath} ${metric}: ${formattedActual}% (${totals[metric].covered}/${totals[metric].total})`;

    if (actual + 1e-9 < threshold) {
      failures.push(`${resultText} < ${formattedThreshold}%`);
    } else {
      passes.push(`${resultText} >= ${formattedThreshold}%`);
    }
  }
}

if (failures.length > 0) {
  console.error('[check-coverage] FAIL');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log('[check-coverage] PASS');
for (const pass of passes) {
  console.log(`- ${pass}`);
}
