#!/usr/bin/env node

const fs = require('fs');

function usage() {
  console.error('Usage: normalize-slither-results.js <slither-json>');
  process.exit(1);
}

const [, , inputPath] = process.argv;

if (!inputPath) {
  usage();
}

const document = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
const detectors = document.results && Array.isArray(document.results.detectors) ? document.results.detectors : [];

function pickPrimaryElement(detector) {
  return (
    (detector.elements || []).find((element) => element.source_mapping && element.source_mapping.filename_relative) ||
    (detector.elements || [])[0] ||
    null
  );
}

const normalized = detectors
  .map((detector) => {
    const element = pickPrimaryElement(detector);
    return JSON.stringify({
      check: detector.check || '',
      impact: detector.impact || '',
      confidence: detector.confidence || '',
      file: element && element.source_mapping ? element.source_mapping.filename_relative || '' : '',
      lines: element && element.source_mapping ? element.source_mapping.lines || [] : [],
      element_name: element ? element.name || '' : '',
      element_type: element ? element.type || '' : ''
    });
  })
  .sort();

if (normalized.length > 0) {
  process.stdout.write(normalized.join('\n'));
  process.stdout.write('\n');
}
