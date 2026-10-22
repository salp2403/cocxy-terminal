// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import fs from 'node:fs';
import path from 'node:path';

// Apple moved from macOS 15 straight to macOS 26; there is no macOS 16.
const macOSReleaseNames = new Map([
  [12, 'Monterey'],
  [13, 'Ventura'],
  [14, 'Sonoma'],
  [15, 'Sequoia'],
  [26, 'Tahoe'],
]);

const staleFloorSweepExtensions = new Set([
  '.html', '.htm', '.js', '.json', '.md', '.mjs', '.plist', '.rb', '.sh', '.strings',
  '.toml', '.txt', '.xml', '.yaml', '.yml',
]);
const staleFloorSweepFileNames = new Set(['Makefile', 'Package.swift']);
// Every other file in the checkout is swept for a stale macOS floor.
const staleFloorSweepExclusions = {
  directoryNames: new Set(['.git', 'node_modules']),
  // Paths relative to the repository root; `web/public/docs` stays swept.
  directories: new Set([
    '.build', '.swiftpm', 'build',
    // Private development notes, never published.
    'docs', '.agents', '.claude', '.codex',
    // Prebuilt engine binaries.
    'libs',
    // Swift sources carry `#available` checks and API notes, not the published floor.
    'CLI', 'Daemon', 'QuickLook', 'Shared', 'Sources', 'Tests',
  ]),
  files: new Set([
    // Release history legitimately names the floors of earlier versions.
    'CHANGELOG.md',
    // Asks reporters for their own macOS version, with examples.
    '.github/ISSUE_TEMPLATE/bug_report.yml',
    // Holds the release-name table above.
    'web/scripts/verify-macos-floor.mjs',
  ]),
};

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function parseDeclaredFloor(packageManifest, failures) {
  const declarations = [...packageManifest.matchAll(/\.macOS\("(\d+)\.(\d+)"\)/g)];
  if (declarations.length !== 1) {
    failures.push(
      `Package.swift macOS deployment target expected 1 declaration, found ${declarations.length}`
    );
    return null;
  }

  const major = Number(declarations[0][1]);
  const minor = Number(declarations[0][2]);
  const releaseName = macOSReleaseNames.get(major);
  if (!releaseName) {
    failures.push(`Package.swift declares macOS ${major}.${minor}, but its release name is not registered`);
    return null;
  }

  return {
    major,
    minor,
    version: `${major}.${minor}`,
    releaseName,
    caskName: releaseName.toLowerCase(),
  };
}

function isVersionOlder(candidateMajor, candidateMinor, floor) {
  return candidateMajor < floor.major
    || (candidateMajor === floor.major && candidateMinor < floor.minor);
}

function discoverStaleFloorSweepSurfaces(repoRoot, readUTF8) {
  const surfaces = [];
  function visit(directory) {
    let entries;
    try {
      entries = fs.readdirSync(directory, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const fullPath = path.join(directory, entry.name);
      const label = path.relative(repoRoot, fullPath).split(path.sep).join('/');
      if (entry.isDirectory()) {
        if (
          !staleFloorSweepExclusions.directoryNames.has(entry.name)
          && !staleFloorSweepExclusions.directories.has(label)
        ) {
          visit(fullPath);
        }
      } else if (
        entry.isFile()
        && !staleFloorSweepExclusions.files.has(label)
        && (staleFloorSweepExtensions.has(path.extname(entry.name))
          || staleFloorSweepFileNames.has(entry.name))
      ) {
        surfaces.push({ label, content: readUTF8(fullPath, label) });
      }
    }
  }
  visit(repoRoot);
  return surfaces;
}

function rejectStaleFloorReferences(failures, surfaces, floor) {
  for (const { label, content } of surfaces) {
    const staleVersions = new Set();
    for (const match of content.matchAll(/\bmacOS\s+(\d+)(?:\.(\d+))?\+?/gi)) {
      const major = Number(match[1]);
      const minor = Number(match[2] ?? 0);
      if (isVersionOlder(major, minor, floor)) staleVersions.add(match[0]);
    }
    for (const staleVersion of staleVersions) {
      failures.push(`${label} contains stale floor reference: ${staleVersion}`);
    }

    for (const [major, releaseName] of macOSReleaseNames) {
      if (major >= floor.major) continue;
      if (new RegExp(`\\b${escapeRegExp(releaseName)}\\b`, 'i').test(content)) {
        failures.push(`${label} contains stale floor release name: ${releaseName}`);
      }
    }
  }
}

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

  // Published text only needs its required mentions; stale mentions are
  // caught by the repository-wide sweep, so extra correct ones must pass.
  function expectTextCount(label, content, expectedText, minimumCount) {
    const count = content.split(expectedText).length - 1;
    if (count < minimumCount) {
      failures.push(`${label} expected at least ${minimumCount} occurrence(s), found ${count}`);
    }
  }

  function expectPatternCount(label, content, pattern, expectedCount) {
    const count = content.match(pattern)?.length ?? 0;
    if (count !== expectedCount) {
      failures.push(`${label} expected ${expectedCount} declaration(s), found ${count}`);
    }
  }

  const surfaces = [
    ['Package.swift', path.join(repoRoot, 'Package.swift')],
    ['README.md', path.join(repoRoot, 'README.md')],
    ['Resources/Info.plist', path.join(repoRoot, 'Resources/Info.plist')],
    ['project.yml', path.join(repoRoot, 'project.yml')],
    ['.github/workflows/release.yml', path.join(repoRoot, '.github/workflows/release.yml')],
    ['.github/workflows/nightly.yml', path.join(repoRoot, '.github/workflows/nightly.yml')],
    ['.github/workflows/preview.yml', path.join(repoRoot, '.github/workflows/preview.yml')],
    ['Distribution/Info.plist', path.join(repoRoot, 'Distribution/Info.plist')],
    ['Distribution/Makefile', path.join(repoRoot, 'Distribution/Makefile')],
    ['Distribution/cocxy-terminal.rb', path.join(repoRoot, 'Distribution/cocxy-terminal.rb')],
    ['scripts/embed-pty-daemon-helper.sh', path.join(repoRoot, 'scripts/embed-pty-daemon-helper.sh')],
    ['web/scripts/build-site.mjs', path.join(webRoot, 'scripts/build-site.mjs')],
    ['web/scripts/generate-releases-page.mjs', path.join(webRoot, 'scripts/generate-releases-page.mjs')],
    ['web/preview/components.html', path.join(webRoot, 'preview/components.html')],
    ['web/public/releases.html', path.join(publicRoot, 'releases.html')],
    ['web/public/es/releases.html', path.join(publicRoot, 'es/releases.html')],
    ['web/public/press.html', path.join(publicRoot, 'press.html')],
    ['web/public/es/press.html', path.join(publicRoot, 'es/press.html')],
    ['web/public/llms.txt', path.join(publicRoot, 'llms.txt')],
  ].map(([label, filePath]) => ({ label, content: readUTF8(filePath, label) }));
  const content = Object.fromEntries(surfaces.map((surface) => [surface.label, surface.content]));
  const floor = parseDeclaredFloor(content['Package.swift'], failures);
  if (!floor) return failures;

  const escapedVersion = escapeRegExp(floor.version);
  const infoPlistFloorPattern = new RegExp(
    `<key>LSMinimumSystemVersion<\\/key>\\s*<string>${escapedVersion}<\\/string>`,
    'g'
  );

  expectPatternCount(
    'Resources/Info.plist minimum system version',
    content['Resources/Info.plist'],
    infoPlistFloorPattern,
    1
  );
  expectPatternCount(
    'Resources/Info.plist minimum system version declarations',
    content['Resources/Info.plist'],
    /<key>LSMinimumSystemVersion<\/key>\s*<string>\d+\.\d+<\/string>/g,
    1
  );
  expectPatternCount(
    'project.yml global deployment target',
    content['project.yml'],
    new RegExp(`^  deploymentTarget:\\n    macOS: "${escapedVersion}"$`, 'gm'),
    1
  );
  expectPatternCount(
    'project.yml global deployment target declarations',
    content['project.yml'],
    /^  deploymentTarget:\n    macOS: "\d+\.\d+"$/gm,
    1
  );
  expectPatternCount(
    'project.yml target deployment target',
    content['project.yml'],
    new RegExp(`^    deploymentTarget: "${escapedVersion}"$`, 'gm'),
    1
  );
  expectPatternCount(
    'project.yml target deployment target declarations',
    content['project.yml'],
    /^    deploymentTarget: "\d+\.\d+"$/gm,
    1
  );
  expectPatternCount(
    'project.yml build setting deployment target',
    content['project.yml'],
    new RegExp(`^        MACOSX_DEPLOYMENT_TARGET: ${escapedVersion}$`, 'gm'),
    1
  );
  expectPatternCount(
    'project.yml build setting deployment target declarations',
    content['project.yml'],
    /^        MACOSX_DEPLOYMENT_TARGET: \d+\.\d+$/gm,
    1
  );

  const workflowExpectations = [
    ['release', content['.github/workflows/release.yml']],
    ['nightly', content['.github/workflows/nightly.yml']],
    ['preview', content['.github/workflows/preview.yml']],
  ];
  for (const [channel, workflow] of workflowExpectations) {
    expectTextCount(
      `${channel} workflow Sparkle minimum`,
      workflow,
      `<sparkle:minimumSystemVersion>${floor.version}</sparkle:minimumSystemVersion>`,
      1
    );
    expectPatternCount(
      `${channel} workflow Sparkle minimum declarations`,
      workflow,
      /<sparkle:minimumSystemVersion>\d+\.\d+<\/sparkle:minimumSystemVersion>/g,
      1
    );
    expectTextCount(
      `${channel} workflow cask minimum`,
      workflow,
      `depends_on macos: ">= :${floor.caskName}"`,
      1
    );
    expectPatternCount(
      `${channel} workflow cask minimum declarations`,
      workflow,
      /depends_on macos: ">= :[a-z]+"/g,
      1
    );
  }

  expectTextCount(
    'release workflow user-facing requirement',
    content['.github/workflows/release.yml'],
    `- macOS ${floor.version} (${floor.releaseName}) or later`,
    1
  );
  expectPatternCount(
    'release workflow user-facing requirement declarations',
    content['.github/workflows/release.yml'],
    /- macOS \d+\.\d+ \([^)]+\) or later/g,
    1
  );
  expectTextCount(
    'release workflow JSON-LD operating system',
    content['.github/workflows/release.yml'],
    `"operatingSystem": "macOS ${floor.version}+"`,
    2
  );
  expectPatternCount(
    'release workflow JSON-LD operating system declarations',
    content['.github/workflows/release.yml'],
    /"operatingSystem": "macOS \d+\.\d+\+"/g,
    2
  );

  expectPatternCount(
    'Distribution/Info.plist minimum system version',
    content['Distribution/Info.plist'],
    infoPlistFloorPattern,
    1
  );
  expectPatternCount(
    'Distribution/Makefile minimum system version',
    content['Distribution/Makefile'],
    new RegExp(
      `<key>LSMinimumSystemVersion<\\/key>\\\\?\\s*<string>${escapedVersion}<\\/string>`,
      'g'
    ),
    1
  );
  expectTextCount(
    'Distribution cask minimum',
    content['Distribution/cocxy-terminal.rb'],
    `depends_on macos: ">= :${floor.caskName}"`,
    1
  );
  expectPatternCount(
    'embedded daemon minimum system version',
    content['scripts/embed-pty-daemon-helper.sh'],
    infoPlistFloorPattern,
    1
  );

  expectTextCount('web source version floor', content['web/scripts/build-site.mjs'], `macOS ${floor.version}+`, 3);
  expectTextCount('web source major floor', content['web/scripts/build-site.mjs'], `macOS ${floor.major}+`, 1);
  expectTextCount(
    'web source floor statistics',
    content['web/scripts/build-site.mjs'],
    `stat('${floor.major}+', 'macOS')`,
    2
  );
  expectTextCount(
    'release page generator operating system',
    content['web/scripts/generate-releases-page.mjs'],
    `operatingSystem: 'macOS ${floor.version}+'`,
    2
  );

  const homes = [
    ['English homepage', homeContent ?? ''],
    ['Spanish homepage', spanishHomeContent ?? ''],
  ];
  for (const [label, homepage] of homes) {
    expectTextCount(`${label} version floor`, homepage, `macOS ${floor.version}+`, 2);
    expectTextCount(
      `${label} floor statistic`,
      homepage,
      `<strong>${floor.major}+</strong><span>macOS</span>`,
      1
    );
  }
  expectTextCount(
    'component preview floor statistic',
    content['web/preview/components.html'],
    `<strong>${floor.major}+</strong><span>macOS</span>`,
    1
  );
  expectTextCount(
    'English releases operating system',
    content['web/public/releases.html'],
    `macOS ${floor.version}+`,
    2
  );
  expectTextCount(
    'Spanish releases operating system',
    content['web/public/es/releases.html'],
    `macOS ${floor.version}+`,
    2
  );
  expectTextCount('English press floor', content['web/public/press.html'], `macOS ${floor.major}+`, 1);
  expectTextCount('Spanish press floor', content['web/public/es/press.html'], `macOS ${floor.major}+`, 1);
  expectTextCount(
    'LLM index floor',
    content['web/public/llms.txt'],
    `Platform: macOS ${floor.version}+`,
    1
  );
  expectTextCount(
    'README system requirement',
    content['README.md'],
    `- macOS ${floor.version} (${floor.releaseName}) or later`,
    1
  );
  expectTextCount('README platform badge', content['README.md'], `macOS-${floor.major}%2B`, 1);

  rejectStaleFloorReferences(failures, discoverStaleFloorSweepSurfaces(repoRoot, readUTF8), floor);

  return failures;
}
