#!/usr/bin/env bash
# Installs a local pre-commit guard that rejects accidental staging of
# secret-shaped files (`.env`, `*.pem`, `id_rsa*`, etc.).
#
# The hook lives only in `.git/hooks/pre-commit` of your clone — it is
# not part of the repository and is not shared between contributors.
# Re-run this script after any `git clone` to install (or refresh) the
# hook for that worktree.
#
# Optional environment variables:
#   COCXY_HOOKS_FORCE=1   Overwrite an existing hook without prompting.
#   COCXY_HOOKS_SKIP_SELFTEST=1
#                         Skip the disposable repo self-test (useful in
#                         CI smoke runs where /tmp may be read-only).

set -euo pipefail

# Resolve repo and template paths relative to this script so it works
# from any CWD inside the worktree.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_PATH="$SCRIPT_DIR/templates/local-pre-commit.sh.template"
HOOK_DIR="$REPO_ROOT/.git/hooks"
HOOK_PATH="$HOOK_DIR/pre-commit"

if [ ! -d "$REPO_ROOT/.git" ]; then
    echo "error: $REPO_ROOT does not look like a git working tree (missing .git)" >&2
    exit 1
fi

if [ ! -f "$TEMPLATE_PATH" ]; then
    echo "error: hook template not found at $TEMPLATE_PATH" >&2
    exit 1
fi

mkdir -p "$HOOK_DIR"

# Only overwrite an existing hook with explicit consent so a contributor
# who has hand-tuned their local hook never loses the work silently.
if [ -f "$HOOK_PATH" ] && [ "${COCXY_HOOKS_FORCE:-0}" != "1" ]; then
    if ! cmp -s "$TEMPLATE_PATH" "$HOOK_PATH"; then
        cat <<EOF >&2
A pre-commit hook already exists at:
    $HOOK_PATH

It differs from the bundled template. Re-run with COCXY_HOOKS_FORCE=1
to overwrite (your customisations will be lost), or remove the file
manually before re-running this script.
EOF
        exit 1
    fi
fi

cp "$TEMPLATE_PATH" "$HOOK_PATH"
chmod +x "$HOOK_PATH"
echo "Installed pre-commit hook: $HOOK_PATH"

if [ "${COCXY_HOOKS_SKIP_SELFTEST:-0}" = "1" ]; then
    echo "Self-test skipped via COCXY_HOOKS_SKIP_SELFTEST=1."
    exit 0
fi

# Run the hook against a disposable repository so the verification never
# touches the user's worktree. The temp directory is cleaned up via trap
# regardless of whether the test passes or fails.
SELFTEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cocxy-hook-selftest.XXXXXX")"
cleanup() { rm -rf "$SELFTEST_DIR"; }
trap cleanup EXIT

(
    cd "$SELFTEST_DIR"
    git init -q
    git config user.email "selftest@cocxy.dev"
    git config user.name "selftest"

    mkdir -p .git/hooks
    cp "$HOOK_PATH" .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit

    # Stage a file the hook MUST reject. `.env` is a documented match
    # so this is the canonical positive control.
    printf 'TOKEN=should-not-be-committed\n' > .env
    git add .env

    if git commit -q -m "selftest: should be rejected" 2>/dev/null; then
        echo "self-test FAILED: commit went through with a staged .env" >&2
        exit 1
    fi

    # Now stage a file that the hook MUST allow so we know it does not
    # over-block. README.md is documented as a normal repo file.
    git rm --cached .env >/dev/null
    rm .env
    printf '# selftest\n' > README.md
    git add README.md
    if ! git commit -q -m "selftest: should pass"; then
        echo "self-test FAILED: hook over-blocked a benign README.md" >&2
        exit 1
    fi
)

echo "Self-test passed: hook rejects secret-shaped paths and admits regular files."
