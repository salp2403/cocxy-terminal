# Contributing to Cocxy Terminal

Thank you for your interest in contributing. Cocxy Terminal is a native macOS terminal built for developers who work with coding agents. Contributions of all kinds are welcome: bug reports, feature requests, code, documentation, and tests.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How to Contribute](#how-to-contribute)
- [Development Environment](#development-environment)
- [Pull Request Process](#pull-request-process)
- [Code Style](#code-style)
- [Commit Conventions](#commit-conventions)
- [Testing Requirements](#testing-requirements)
- [Documentation](#documentation)
- [Security Issues](#security-issues)
- [Dependency Policy](#dependency-policy)

## Code of Conduct

This project follows the [Contributor Covenant v2.1](CODE_OF_CONDUCT.md). By participating you agree to abide by its terms. Report unacceptable behavior to security@cocxy.dev.

## How to Contribute

### Reporting Bugs

1. Search [existing issues](https://github.com/salp2403/cocxy-terminal/issues) to avoid duplicates.
2. Open a new issue using the **Bug Report** template.
3. Include: macOS version, chip (Apple Silicon or Intel), Cocxy version (`cocxy --version`), steps to reproduce, expected vs. actual behavior, and relevant log output.

To collect log output:

```bash
log show --predicate 'subsystem == "dev.cocxy.terminal"' --last 5m
```

### Suggesting Features

Open an issue using the **Feature Request** template. Describe the problem you are trying to solve, not just the solution you have in mind. If your feature involves security implications (new permissions, network access, IPC changes), explain your threat model.

### Contributing Code

1. Fork the repository.
2. Create a branch from `main`.
3. Make your changes following the guidelines below.
4. Open a pull request.

## Development Environment

### Prerequisites

- macOS 14 Sonoma or later (macOS 15 recommended)
- Xcode 16 or later
- Zig 0.15+ (`brew install zig`)

### Setup

1. Fork and clone:

   ```bash
   git clone https://github.com/YOUR_USERNAME/cocxy-terminal.git
   cd cocxy-terminal
   ```

2. Build libghostty (takes 5-10 minutes on first run):

   ```bash
   chmod +x scripts/build-libghostty.sh
   ./scripts/build-libghostty.sh
   ```

3. Build and run:

   ```bash
   swift build
   swift run CocxyTerminal
   ```

4. Run the test suite:

   ```bash
   swift test
   ```

   All tests must pass before you open a pull request.

## Pull Request Process

### Branch Naming

| Type | Pattern | Example |
|------|---------|---------|
| Feature | `feat/short-description` | `feat/ssh-tunnel-support` |
| Bug fix | `fix/short-description` | `fix/agent-detection-false-positive` |
| Documentation | `docs/short-description` | `docs/cli-examples` |
| Refactor | `refactor/short-description` | `refactor/extract-theme-parser` |
| Test | `test/short-description` | `test/split-manager-edge-cases` |

If your change relates to a GitHub issue, reference it: `fix/123-crash-on-split-close`.

### Requirements

1. **One concern per PR.** Do not mix a feature, a bug fix, and a refactor in the same pull request.
2. **Fill in the PR template completely.** A clear title, a description of *why* the change is needed, testing details, and screenshots if the change is visual.
3. **Write tests.** New code must have tests. Bug fixes must include a test that would have caught the bug.
4. **Run the full test suite** locally before opening the PR. Do not rely on CI to catch failures.
5. **Address review feedback.** At least one maintainer review is required before merge. PRs touching security-sensitive code (socket server, permissions, authentication) require additional review.
6. **Keep a clean history.** Squash or rebase noisy commit histories before merging.

### What Makes a Good PR

- A clear title that describes the change (not "fix bug" or "update code").
- A description that explains the motivation, not just the mechanics.
- Small, focused diffs that are easy to review.
- No unrelated changes.

## Code Style

### Swift Conventions

- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/).
- Use `Combine` for reactive state propagation (consistent with the existing codebase).
- Prefer protocols and dependency injection over concrete types. Every module boundary has a protocol.
- Mark types as `final` unless designed for subclassing.
- Use `Sendable` conformance explicitly for types shared across concurrency boundaries.

### Naming

| Element | Convention | Example |
|---------|-----------|---------|
| Types, protocols | `UpperCamelCase` | `AgentDetectionEngine` |
| Functions, variables | `lowerCamelCase` | `activeTheme` |
| Constants | `lowerCamelCase` | `defaultIdleTimeout` |
| Enum cases | `lowerCamelCase` | `TabPosition.left` |
| Protocol names | Noun or `-ing`/`-able`/`-Providing` | `ConfigProviding` |

### File Organization

- One primary type per file. Extensions of that type belong in the same file.
- File name matches the primary type: `AgentDetectionEngine.swift`.
- Use `// MARK: -` to organize sections within a file.

## Commit Conventions

Follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

### Types

| Type | When to use |
|------|-------------|
| `feat` | A new feature |
| `fix` | A bug fix |
| `test` | Adding or updating tests |
| `docs` | Documentation changes only |
| `refactor` | Code change that is neither a fix nor a feature |
| `chore` | Build scripts, dependency updates, tooling |
| `perf` | Performance improvement |
| `security` | Security fix |

### Scope

Use the affected module or directory: `agent-detection`, `config`, `theme`, `session`, `cli`, `ui`, `terminal`, `browser`.

### Example

```
feat(agent-detection): add OSC sequence detector for Kiro

Implements OSC-based detection for the Kiro coding agent. Uses the same
three-layer strategy as other agents (OSC > pattern > timing).

Closes #42
```

### Breaking Changes

Add `BREAKING CHANGE:` in the commit footer and explain what changed and how to migrate.

## Testing Requirements

### What to Test

- Every public function has at least one test covering the happy path.
- Edge cases: empty input, nil values, boundary values.
- Error paths: invalid configuration, missing files, malformed input.
- Regex patterns: verify they match intended targets and reject non-targets.

### Test Doubles

Use the protocol-based dependency injection in the codebase to inject test doubles. Every external dependency (filesystem, network, notifications) has an injectable protocol. Do not mock Foundation types directly.

### No Flaky Tests

Tests must be deterministic. Do not use `Thread.sleep` or real timers. Use test doubles that emit events synchronously.

### Coverage Targets

| Module | Minimum |
|--------|---------|
| Agent Detection | 85% |
| Config + Theme | 80% |
| Session Management | 80% |
| Tab + Split Management | 80% |
| CLI + Socket | 75% |

## Documentation

### Inline Documentation

All public types, functions, and properties must have documentation comments:

```swift
/// Loads and validates the agent detection configuration.
///
/// Reads `~/.config/cocxy/agents.toml`, compiles regex patterns, and caches
/// the results. Falls back to built-in defaults if the file is missing or
/// contains errors.
///
/// - Parameter fileProvider: Source of the agents.toml content.
final class AgentConfigService {
```

For complex logic, add a comment explaining *why*, not *what*:

```swift
// NSRegularExpression compilation is expensive. Compile once at load time
// and cache the results to avoid per-line allocation during high-frequency
// output parsing.
let compiled = patterns.map { try NSRegularExpression(pattern: $0) }
```

### User Documentation

Changes that affect user-visible behavior need a corresponding update in `docs/user/`. New configuration keys need a row in the relevant table.

## Security Issues

**Do not open a public GitHub issue for security vulnerabilities.** Follow the responsible disclosure process described in [SECURITY.md](SECURITY.md).

## Dependency Policy

Cocxy Terminal has a strict zero-external-dependencies policy for Swift packages:

- **No Swift Package Manager dependencies.** The project uses only Apple frameworks and the Swift standard library.
- **No Node, npm, or web tooling.** This is a native macOS app.
- **libghostty is the sole external dependency.** It is compiled as an xcframework and vendored in `libs/`. Its version is pinned in `scripts/build-libghostty.sh`.

**Rationale:** External dependencies increase attack surface, complicate reproducible builds, and add maintenance burden. Every dependency is a potential supply chain vector.

If you believe an exception is justified, open an issue explaining the use case and the alternatives you have considered.
