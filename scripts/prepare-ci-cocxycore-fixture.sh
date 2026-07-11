#!/bin/bash
# prepare-ci-cocxycore-fixture.sh - Create inert remote-daemon build inputs for unprivileged CI.

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <absolute-empty-fixture-directory>" >&2
    exit 64
fi

FIXTURE_ROOT="$1"
case "${FIXTURE_ROOT}" in
    /*) ;;
    *)
        echo "ERROR: CI fixture directory must be absolute: ${FIXTURE_ROOT}" >&2
        exit 64
        ;;
esac
if [ -e "${FIXTURE_ROOT}" ] || [ -L "${FIXTURE_ROOT}" ]; then
    echo "ERROR: Refusing to replace an existing CI fixture path: ${FIXTURE_ROOT}" >&2
    exit 73
fi

umask 077
mkdir -p "${FIXTURE_ROOT}/scripts"
printf '%s\n' "CI-only inert CocxyCore fixture; never ship these binaries." \
    > "${FIXTURE_ROOT}/.cocxy-ci-fixture"

cat > "${FIXTURE_ROOT}/daemon.c" <<'SOURCE'
int main(void) {
    return 78;
}
SOURCE

cat > "${FIXTURE_ROOT}/daemon.zig" <<'SOURCE'
const std = @import("std");

pub fn main() void {
    std.process.exit(78);
}
SOURCE

cat > "${FIXTURE_ROOT}/scripts/build.sh" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ "$#" -ne 1 ] || [ "$1" != "build" ]; then
    echo "ERROR: CI fixture accepts only the 'build' command." >&2
    exit 64
fi
if [ "${COCXY_CI_REMOTE_DAEMON_FIXTURE:-}" != "1" ] \
    || [ ! -f "${ROOT}/.cocxy-ci-fixture" ]; then
    echo "ERROR: CI remote-daemon fixture requires explicit opt-in." >&2
    exit 77
fi
if ! command -v zig >/dev/null 2>&1; then
    echo "ERROR: Zig 0.15.2 is required for the CI remote-daemon fixture." >&2
    exit 69
fi

mkdir -p "${ROOT}/zig-out/bin"
xcrun clang -arch arm64 -Os "${ROOT}/daemon.c" \
    -o "${ROOT}/zig-out/bin/cocxyd-remote-macos-arm64"
zig build-exe "${ROOT}/daemon.zig" \
    -O ReleaseSmall -target x86_64-linux-musl -fstrip \
    -femit-bin="${ROOT}/zig-out/bin/cocxyd-remote-linux-x86_64"
zig build-exe "${ROOT}/daemon.zig" \
    -O ReleaseSmall -target aarch64-linux-musl -fstrip \
    -femit-bin="${ROOT}/zig-out/bin/cocxyd-remote-linux-arm64"
chmod 755 "${ROOT}/zig-out/bin/"cocxyd-remote-*
SCRIPT

chmod 755 "${FIXTURE_ROOT}/scripts/build.sh"
printf '%s\n' "${FIXTURE_ROOT}"
