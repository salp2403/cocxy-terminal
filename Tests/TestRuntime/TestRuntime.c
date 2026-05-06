// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TestRuntime.c - Process-wide test runner guards.

#include <signal.h>

__attribute__((constructor))
static void cocxy_test_runtime_install_signal_guards(void) {
    signal(SIGPIPE, SIG_IGN);
}
