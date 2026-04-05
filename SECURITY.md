# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.1.x (current) | Yes |
| Pre-release | No |

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Send your report by email to:

```
security@cocxy.dev
```

Include `[SECURITY]` in the subject line.

### What to Include

A useful report contains:

- A description of the vulnerability and its potential impact.
- The component or file affected (e.g., socket server, config parser, detection engine).
- Steps to reproduce the issue.
- A proof of concept if available (code, command, or configuration).
- Your recommended fix, if you have one.

You do not need a full exploit. A clear description and reproduction steps are sufficient.

## Response Timeline

| Milestone | Timeframe |
|-----------|-----------|
| Acknowledge receipt | 48 hours |
| Initial assessment and severity classification | 7 days |
| Fix for critical and high severity issues | 30 days |
| Fix for medium severity issues | 90 days |
| Public disclosure | After fix is released, or 90 days from acknowledgment |

If you need to coordinate disclosure timing (e.g., conference presentation), mention it in your report and we will work with you on a timeline.

## Scope

### What Qualifies as a Security Issue

- **Privilege escalation:** Any way for a process to gain access to files, sockets, or capabilities beyond what the current user should have.
- **Socket authentication bypass:** Connecting to the Cocxy socket from a process running under a different UID than the app owner.
- **Code execution via configuration:** A malformed `.toml` configuration file that causes arbitrary code execution.
- **Regex denial of service:** A pattern in `agents.toml` that causes catastrophic backtracking and hangs the application.
- **Data leakage:** Any transmission of user data to external servers (this would violate a core design principle).
- **Information disclosure:** Reading terminal output from another user's session on a shared system.
- **Dependency supply chain issues:** Vulnerabilities in CocxyCoreKit, Sparkle, or other shipped binary dependencies that affect Cocxy.

### What Does NOT Qualify

- **Physical access attacks.** If an attacker has physical access and can modify `~/.config/cocxy/`, they already have access to your home directory.
- **Denial of service via terminal output.** Rendering very long lines or high-frequency output consuming CPU is expected terminal emulator behavior.
- **Social engineering.** Convincing a user to paste a malicious command is not a Cocxy vulnerability.
- **Missing security features.** The absence of a feature is a feature request, not a vulnerability.
- **Bugs in third-party tools.** Cocxy is not responsible for the behavior of programs running inside terminal sessions.
- **macOS system vulnerabilities.** Report those to Apple via [security-advisories.apple.com](https://security-advisories.apple.com).

## Security Design Principles

Understanding the design helps evaluate what is in scope.

**Zero telemetry.** Cocxy never opens an outbound network connection. No analytics, no crash reporting, no usage tracking. Verify with any network monitoring tool.

**Authenticated Unix socket.** The CLI communicates via a Unix Domain Socket with `0600` permissions. The server verifies the connecting process runs under the same UID as the app. Connections from different UIDs are rejected before any command is processed.

**No eval, no dynamic code.** Configuration files are parsed as data. No configuration value is ever evaluated as code. Regex patterns from `agents.toml` are compiled via `NSRegularExpression` with safety limits.

**Minimal entitlements.** The app requests only the permissions it needs. No network entitlement, no access to Contacts, Photos, Camera, Microphone, or Location.

## Acknowledgments

Researchers who report valid vulnerabilities will be credited in release notes and in this file, unless they prefer to remain anonymous.

| Researcher | Date | Issue | Severity |
|-----------|------|-------|----------|
| -- | -- | -- | -- |
