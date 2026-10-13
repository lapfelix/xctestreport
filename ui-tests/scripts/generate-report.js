#!/usr/bin/env node
// Seed xcresulttool's cached JSON, then use the shipping CLI for every HTML page and ZIP.
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

function generateReport(executable, directory) {
  const output = path.resolve(directory);
  fs.mkdirSync(output, { recursive: true });
  if (fs.readdirSync(output).length) throw new Error(`Fixture output must be empty: ${output}`);
  const writeJSON = (name, value) => fs.writeFileSync(path.join(output, name), JSON.stringify(value));
  const startTime = 1_800_000_000;
  const device = {
    deviceId: 'SMOKE-DEVICE', deviceName: 'Apple Watch', architecture: 'arm64',
    modelName: 'Apple Watch Series 11', platform: 'watchOS Simulator',
    osVersion: '27.0', osBuildNumber: '24R1',
  };
  const configuration = { configurationId: 'SMOKE-CONFIG', configurationName: 'Default' };
  const tests = [
    { name: 'testSnapshot()', nodeType: 'Test Case', nodeIdentifier: 'SmokeTests/testSnapshot()', result: 'Failed', duration: '2s', details: 'Snapshot differs from its reference.', startTime },
    { name: 'testPassing()', nodeType: 'Test Case', nodeIdentifier: 'SmokeTests/testPassing()', result: 'Passed', duration: '1s', startTime: startTime + 2 },
  ];
  writeJSON('summary.json', {
    title: 'Generated smoke report', startTime, finishTime: startTime + 3,
    environmentDescription: 'Cached fixture', topInsights: [], result: 'Failed',
    totalTestCount: 2, passedTests: 1, failedTests: 1, skippedTests: 0, expectedFailures: 0,
    statistics: [], devicesAndConfigurations: [{ device, testPlanConfiguration: configuration, passedTests: 1, failedTests: 1, skippedTests: 0, expectedFailures: 0 }],
    testFailures: [{ testName: tests[0].name, targetName: 'SmokeTests', failureText: tests[0].details, testIdentifier: 1 }],
  });
  writeJSON('tests_full.json', { devices: [device], testNodes: tests, testPlanConfigurations: [configuration] });
  writeJSON('tests_inventory.json', { schemaVersion: 1, tests, sourceBundles: [] });
  writeJSON('test_details.json', Object.fromEntries(tests.map(test => [test.nodeIdentifier, {
    devices: [device], duration: test.duration, hasMediaAttachments: test.result === 'Failed',
    hasPerformanceMetrics: false, startTime: test.startTime, testDescription: test.name,
    testIdentifier: test.nodeIdentifier, testName: test.name, testPlanConfigurations: [configuration],
    testResult: test.result, testRuns: [{ name: 'Run 1', nodeType: 'Test Case Run', result: test.result, duration: test.duration, children: [] }],
  }])));
  writeJSON('test_activities.json', Object.fromEntries(tests.map(test => [test.nodeIdentifier, {
    testIdentifier: test.nodeIdentifier,
    testRuns: [{ activities: test.result === 'Failed' ? [{
      title: 'Capture screenshot', startTime: test.startTime, isAssociatedWithFailure: true,
      attachments: [{ name: 'Screenshot', timestamp: test.startTime + 0.5, payloadId: 'screenshot' }],
    }] : [] }],
  }])));
  writeJSON('build_results.json', { startTime, endTime: startTime + 1, errorCount: 0, warningCount: 0 });

  const attachments = path.join(output, 'attachments');
  fs.mkdirSync(attachments);
  const images = path.resolve(__dirname, '../fixtures/snapshots');
  for (const [source, destination] of [
    ['NearbyRow-pinned.expected.png', '1.png'],
    ['NearbyRow-pinned.actual.png', '2.png'],
    ['NearbyRow-pinned.actual.png', '3.png'],
  ]) fs.copyFileSync(path.join(images, source), path.join(attachments, destination));
  fs.writeFileSync(path.join(attachments, 'manifest.json'), JSON.stringify([
    { testIdentifier: tests[0].nodeIdentifier, attachments: [
      { exportedFileName: '1.png', suggestedHumanReadableName: 'Card.expected.png', isAssociatedWithFailure: true, timestamp: startTime, payloadRefId: 'expected' },
      { exportedFileName: '2.png', suggestedHumanReadableName: 'Card.actual.png', isAssociatedWithFailure: true, timestamp: startTime, payloadRefId: 'actual' },
      { exportedFileName: '3.png', suggestedHumanReadableName: 'Screenshot', isAssociatedWithFailure: true, timestamp: startTime + 0.5, payloadRefId: 'screenshot' },
    ] },
  ]));

  const sourceBundle = path.join(output, 'Source.xcresult'); // Intentionally absent: --html-only must use the caches.
  const invoke = () => {
    const result = spawnSync(path.resolve(executable), [sourceBundle, output, '--html-only', '--header-note', 'Production renderer fixture'], { encoding: 'utf8', stdio: 'pipe' });
    if (result.error) throw result.error;
    return result;
  };
  const generate = () => {
    const result = invoke();
    if (result.status !== 0) throw new Error(`Report generation failed (${result.status}):\n${result.stdout}\n${result.stderr}`);
    for (const name of ['index.html', 'snapshots.html']) {
      if (!fs.existsSync(path.join(output, name))) throw new Error(`Production generator omitted ${name}`);
    }
    const testFiles = fs.readdirSync(path.join(output, 'tests'));
    if (testFiles.filter(name => name.endsWith('.html')).length !== tests.length || testFiles.filter(name => name.endsWith('.zip')).length !== tests.length) {
      throw new Error('Production generator must emit one detail page and ZIP for each fixture test.');
    }
    if (fs.existsSync(path.join(attachments, '3.png'))) throw new Error('The ordinary screenshot must be packed and its loose copy pruned.');
    if (fs.existsSync(sourceBundle)) throw new Error('The regeneration fixture must not have an original .xcresult.');
  };
  generate();
  // Recover the pruned screenshot from the shipping ZIP, then regenerate without the source bundle.
  generate();

  const artifactNames = ['index.html', 'snapshots.html', ...fs.readdirSync(path.join(output, 'tests'))
    .filter(name => /\.(html|zip)$/.test(name)).map(name => 'tests/' + name)];
  const preserved = new Map(artifactNames.map(name => [name, fs.readFileSync(path.join(output, name))]));
  const detailsCache = path.join(output, 'test_details.json');
  const validDetails = fs.readFileSync(detailsCache);
  try {
    fs.writeFileSync(detailsCache, '{');
    const failed = invoke();
    if (failed.status === 0) throw new Error('Corrupt required cache must make regeneration fail.');
    for (const [name, bytes] of preserved) {
      if (!fs.existsSync(path.join(output, name)) || !fs.readFileSync(path.join(output, name)).equals(bytes)) {
        throw new Error(`Failed regeneration changed the previously published artifact: ${name}`);
      }
    }
  } finally {
    fs.writeFileSync(detailsCache, validDetails);
  }
  process.stdout.write(`Generated production report in ${output}\n`);
  process.stdout.write('Verified regeneration of pruned attachments and preservation after a corrupt-cache failure.\n');
}

if (require.main === module) {
  if (process.argv.length !== 4) {
    process.stderr.write('Usage: node generate-report.js /path/to/xctestreport /empty/output/directory\n');
    process.exitCode = 1;
  } else {
    try { generateReport(process.argv[2], process.argv[3]); }
    catch (error) { process.stderr.write(`${error.message}\n`); process.exitCode = 1; }
  }
}

module.exports = { generateReport };
