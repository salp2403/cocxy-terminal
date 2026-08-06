// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import fs from 'node:fs';
import path from 'node:path';

export function verifyMacOSFloor({ repoRoot, webRoot, homeContent, spanishHomeContent }) {
  const failures = [];
  const publicRoot = path.join(webRoot, 'public');

  function readUTF8(filePath, label) {
    try {
      return fs.readFileSync(filePath, 'utf8');
    } catch (error) {
      if (error?.code === 'ENOENT') {
        failures.push(`Missing required file: ${label}`);
      } else {
        const detail = error instanceof Error ? error.message : String(error);
        failures.push(`Unable to read ${label}: ${detail}`);
      }
      return '';
    }
  }

  function expectTextCount(label, content, expectedText, expectedCount) {
    const count = content.split(expectedText).length - 1;
    if (count !== expectedCount) {
      failures.push(`${label} expected ${expectedCount} occurrence(s), found ${count}`);
    }
  }

  function expectPatternCount(label, content, pattern, expectedCount) {
    const count = content.match(pattern)?.length ?? 0;
    if (count !== expectedCount) {
      failures.push(`${label} expected ${expectedCount} declaration(s), found ${count}`);
    }
  }

  const packageManifest = readUTF8(path.join(repoRoot, 'Package.swift'), 'Package.swift');
  const infoPlist = readUTF8(path.join(repoRoot, 'Resources/Info.plist'), 'Resources/Info.plist');
  const projectManifest = readUTF8(path.join(repoRoot, 'project.yml'), 'project.yml');
  const releaseWorkflow = readUTF8(
    path.join(repoRoot, '.github/workflows/release.yml'),
    '.github/workflows/release.yml'
  );
  const buildSite = readUTF8(
    path.join(webRoot, 'scripts/build-site.mjs'),
    'web/scripts/build-site.mjs'
  );
  const releasePageGenerator = readUTF8(
    path.join(webRoot, 'scripts/generate-releases-page.mjs'),
    'web/scripts/generate-releases-page.mjs'
  );
  const preview = readUTF8(
    path.join(webRoot, 'preview/components.html'),
    'web/preview/components.html'
  );
  const generatedReleases = readUTF8(
    path.join(publicRoot, 'releases.html'),
    'web/public/releases.html'
  );
  const generatedSpanishReleases = readUTF8(
    path.join(publicRoot, 'es/releases.html'),
    'web/public/es/releases.html'
  );
  const generatedPress = readUTF8(
    path.join(publicRoot, 'press.html'),
    'web/public/press.html'
  );
  const generatedSpanishPress = readUTF8(
    path.join(publicRoot, 'es/press.html'),
    'web/public/es/press.html'
  );
  const generatedLLMs = readUTF8(
    path.join(publicRoot, 'llms.txt'),
    'web/public/llms.txt'
  );

  expectPatternCount(
    'Package.swift macOS deployment target',
    packageManifest,
    /\.macOS\("15\.0"\)/g,
    1
  );
  expectPatternCount(
    'Package.swift macOS deployment target declarations',
    packageManifest,
    /\.macOS\("\d+\.\d+"\)/g,
    1
  );
  expectPatternCount(
    'Resources/Info.plist minimum system version',
    infoPlist,
    /<key>LSMinimumSystemVersion<\/key>\s*<string>15\.0<\/string>/g,
    1
  );
  expectPatternCount(
    'Resources/Info.plist minimum system version declarations',
    infoPlist,
    /<key>LSMinimumSystemVersion<\/key>\s*<string>\d+\.\d+<\/string>/g,
    1
  );
  expectPatternCount(
    'project.yml global deployment target',
    projectManifest,
    /^  deploymentTarget:\n    macOS: "15\.0"$/gm,
    1
  );
  expectPatternCount(
    'project.yml global deployment target declarations',
    projectManifest,
    /^  deploymentTarget:\n    macOS: "\d+\.\d+"$/gm,
    1
  );
  expectPatternCount(
    'project.yml target deployment target',
    projectManifest,
    /^    deploymentTarget: "15\.0"$/gm,
    1
  );
  expectPatternCount(
    'project.yml target deployment target declarations',
    projectManifest,
    /^    deploymentTarget: "\d+\.\d+"$/gm,
    1
  );
  expectPatternCount(
    'project.yml build setting deployment target',
    projectManifest,
    /^        MACOSX_DEPLOYMENT_TARGET: 15\.0$/gm,
    1
  );
  expectPatternCount(
    'project.yml build setting deployment target declarations',
    projectManifest,
    /^        MACOSX_DEPLOYMENT_TARGET: \d+\.\d+$/gm,
    1
  );

  expectTextCount(
    'release workflow Sparkle minimum',
    releaseWorkflow,
    '<sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>',
    1
  );
  expectPatternCount(
    'release workflow Sparkle minimum declarations',
    releaseWorkflow,
    /<sparkle:minimumSystemVersion>\d+\.\d+<\/sparkle:minimumSystemVersion>/g,
    1
  );
  expectTextCount(
    'release workflow user-facing requirement',
    releaseWorkflow,
    '- macOS 15.0 (Sequoia) or later',
    1
  );
  expectPatternCount(
    'release workflow user-facing requirement declarations',
    releaseWorkflow,
    /- macOS \d+\.\d+ \([^)]+\) or later/g,
    1
  );
  expectTextCount(
    'release workflow JSON-LD operating system',
    releaseWorkflow,
    '"operatingSystem": "macOS 15.0+"',
    2
  );
  expectPatternCount(
    'release workflow JSON-LD operating system declarations',
    releaseWorkflow,
    /"operatingSystem": "macOS \d+\.\d+\+"/g,
    2
  );
  expectTextCount(
    'release workflow cask minimum',
    releaseWorkflow,
    'depends_on macos: ">= :sequoia"',
    1
  );
  expectPatternCount(
    'release workflow cask minimum declarations',
    releaseWorkflow,
    /depends_on macos: ">= :[a-z]+"/g,
    1
  );
  expectTextCount('release workflow stale macOS 14 floor', releaseWorkflow, 'macOS 14.0', 0);

  expectTextCount('web source version floor', buildSite, 'macOS 15.0+', 3);
  expectTextCount('web source major floor', buildSite, 'macOS 15+', 1);
  expectTextCount('web source floor statistics', buildSite, "stat('15+', 'macOS')", 2);
  expectTextCount(
    'release page generator operating system',
    releasePageGenerator,
    "operatingSystem: 'macOS 15.0+'",
    2
  );

  expectTextCount('English homepage version floor', homeContent, 'macOS 15.0+', 2);
  expectTextCount(
    'English homepage floor statistic',
    homeContent,
    '<strong>15+</strong><span>macOS</span>',
    1
  );
  expectTextCount('Spanish homepage version floor', spanishHomeContent, 'macOS 15.0+', 2);
  expectTextCount(
    'Spanish homepage floor statistic',
    spanishHomeContent,
    '<strong>15+</strong><span>macOS</span>',
    1
  );
  expectTextCount(
    'component preview floor statistic',
    preview,
    '<strong>15+</strong><span>macOS</span>',
    1
  );
  expectTextCount('English releases operating system', generatedReleases, 'macOS 15.0+', 2);
  expectTextCount(
    'Spanish releases operating system',
    generatedSpanishReleases,
    'macOS 15.0+',
    2
  );
  expectTextCount('English press floor', generatedPress, 'macOS 15+', 1);
  expectTextCount('Spanish press floor', generatedSpanishPress, 'macOS 15+', 1);
  expectTextCount('LLM index floor', generatedLLMs, 'Platform: macOS 15.0+', 1);

  return failures;
}
