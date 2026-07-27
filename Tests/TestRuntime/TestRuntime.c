// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TestRuntime.c - Process-wide test runner guards.

#define _DARWIN_C_SOURCE 1

#include <crt_externs.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <libproc.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

typedef int (*cocxy_set_disclaim_fn)(posix_spawnattr_t *, int);
typedef pid_t (*cocxy_get_responsible_fn)(pid_t);

static const char *cocxy_escape_evidence_environment =
    "COCXY_TEST_RESPONSIBILITY_ESCAPE_EVIDENCE";
static const char *cocxy_escape_child_environment =
    "COCXY_TEST_RESPONSIBILITY_ESCAPE_CHILD";
static const char *cocxy_escape_ready_fd_environment =
    "COCXY_TEST_RESPONSIBILITY_ESCAPE_READY_FD";
static const char *cocxy_zombie_peer_environment =
    "COCXY_TEST_ZOMBIE_PEER";
static const char *cocxy_process_root_environment =
    "COCXY_TEST_BOUNDED_PROCESS_ROOT";
static const char *cocxy_process_label_environment =
    "COCXY_TEST_BOUNDED_PROCESS_LABEL_PREFIX";
static const char *cocxy_process_gate_state = "execution-gate.plist";
static const unsigned int cocxy_fixture_lifetime_seconds = 30;
static const int cocxy_reap_timeout_milliseconds = 2000;
static char cocxy_owned_process_root[PATH_MAX] = {0};

static void cocxy_remove_owned_process_root(void) {
    if (cocxy_owned_process_root[0] == '\0') return;

    int root_descriptor = open(
        cocxy_owned_process_root,
        O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
    );
    if (root_descriptor >= 0) {
        struct stat root_status = {0};
        struct stat state_status = {0};
        if (fstat(root_descriptor, &root_status) == 0
            && root_status.st_uid == geteuid()
            && S_ISDIR(root_status.st_mode)
            && (root_status.st_mode & 0777) == 0700
            && fstatat(
                root_descriptor,
                cocxy_process_gate_state,
                &state_status,
                AT_SYMLINK_NOFOLLOW
            ) == 0
            && state_status.st_uid == geteuid()
            && S_ISREG(state_status.st_mode)
            && (state_status.st_mode & 0777) == 0600
            && state_status.st_nlink == 1) {
            unlinkat(root_descriptor, cocxy_process_gate_state, 0);
        }
        close(root_descriptor);
    }
    rmdir(cocxy_owned_process_root);
}

static int cocxy_install_process_test_namespace(void) {
    const char *existing_root = getenv(cocxy_process_root_environment);
    const char *existing_label = getenv(cocxy_process_label_environment);
    if (existing_root != NULL || existing_label != NULL) {
        return existing_root != NULL && existing_label != NULL ? 0 : EINVAL;
    }

    unsigned int nonce = arc4random();
    int root_count = snprintf(
        cocxy_owned_process_root,
        sizeof(cocxy_owned_process_root),
        "/private/tmp/cxbpt.%u.%08x",
        (unsigned int)getuid(),
        nonce
    );
    char label[192] = {0};
    int label_count = snprintf(
        label,
        sizeof(label),
        "dev.cocxy.bounded-process.test.%u.%08x",
        (unsigned int)getuid(),
        nonce
    );
    if (root_count <= 0 || root_count >= (int)sizeof(cocxy_owned_process_root)
        || label_count <= 0 || label_count >= (int)sizeof(label)) {
        cocxy_owned_process_root[0] = '\0';
        return EOVERFLOW;
    }
    if (setenv(cocxy_process_root_environment, cocxy_owned_process_root, 1) != 0
        || setenv(cocxy_process_label_environment, label, 1) != 0) {
        int code = errno != 0 ? errno : EIO;
        unsetenv(cocxy_process_root_environment);
        unsetenv(cocxy_process_label_environment);
        cocxy_owned_process_root[0] = '\0';
        return code;
    }
    if (atexit(cocxy_remove_owned_process_root) != 0) {
        return EIO;
    }
    return 0;
}

static long long cocxy_monotonic_milliseconds(void) {
    struct timespec value = {0};
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) return -1;
    return (long long)value.tv_sec * 1000LL + value.tv_nsec / 1000000LL;
}

static int cocxy_reap_child(pid_t child, int timeout_milliseconds) {
    long long now = cocxy_monotonic_milliseconds();
    if (now < 0) return errno != 0 ? errno : EIO;
    long long deadline = now + timeout_milliseconds;
    int status = 0;
    for (;;) {
        pid_t result = waitpid(child, &status, WNOHANG);
        if (result == child || (result < 0 && errno == ECHILD)) return 0;
        if (result < 0 && errno != EINTR) return errno != 0 ? errno : EIO;
        now = cocxy_monotonic_milliseconds();
        if (now < 0) return errno != 0 ? errno : EIO;
        if (now >= deadline) return ETIMEDOUT;
        usleep(10000);
    }
}

static int cocxy_run_zombie_peer(void) {
    signal(SIGALRM, SIG_DFL);
    alarm(cocxy_fixture_lifetime_seconds);
    unsigned char ready = 1;
    ssize_t written;
    do {
        written = write(STDOUT_FILENO, &ready, sizeof(ready));
    } while (written < 0 && errno == EINTR);
    if (written != sizeof(ready)) return errno != 0 ? errno : EIO;

    unsigned char release = 0;
    ssize_t count;
    do {
        count = read(STDIN_FILENO, &release, sizeof(release));
    } while (count < 0 && errno == EINTR);
    return count < 0 ? (errno != 0 ? errno : EIO) : 0;
}

static int cocxy_run_escape_child(void) {
    signal(SIGHUP, SIG_IGN);
    signal(SIGTERM, SIG_IGN);
    signal(SIGALRM, SIG_DFL);
    alarm(cocxy_fixture_lifetime_seconds);

    const char *ready_value = getenv(cocxy_escape_ready_fd_environment);
    if (ready_value == NULL || ready_value[0] == '\0') return EINVAL;
    char *end = NULL;
    errno = 0;
    long raw_descriptor = strtol(ready_value, &end, 10);
    if (errno != 0 || end == ready_value || *end != '\0'
        || raw_descriptor < 0 || raw_descriptor > INT_MAX) {
        return EINVAL;
    }
    int ready_descriptor = (int)raw_descriptor;
    unsigned char ready = 1;
    ssize_t written;
    do {
        written = write(ready_descriptor, &ready, sizeof(ready));
    } while (written < 0 && errno == EINTR);
    int ready_code = written == sizeof(ready) ? 0 : (errno != 0 ? errno : EIO);
    close(ready_descriptor);
    if (ready_code != 0) return ready_code;

    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);
    for (;;) {
        pause();
    }
}

static int cocxy_write_escape_evidence(
    const char *path,
    pid_t pid,
    pid_t responsible,
    pid_t session,
    unsigned long long start_seconds,
    unsigned long long start_microseconds
) {
    size_t path_length = strlen(path);
    char *temporary_path = malloc(path_length + 5);
    if (temporary_path == NULL) return ENOMEM;
    memcpy(temporary_path, path, path_length);
    memcpy(temporary_path + path_length, ".tmp", 5);

    int descriptor = open(
        temporary_path,
        O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
        0600
    );
    if (descriptor < 0) {
        int code = errno;
        free(temporary_path);
        return code;
    }

    char buffer[192];
    int count = snprintf(
        buffer,
        sizeof(buffer),
        "%d %d %d %llu %llu\n",
        pid,
        responsible,
        session,
        start_seconds,
        start_microseconds
    );
    int code = 0;
    if (count < 0 || write(descriptor, buffer, (size_t)count) != count) {
        code = errno != 0 ? errno : EIO;
    } else if (fsync(descriptor) != 0) {
        code = errno;
    }
    close(descriptor);

    if (code == 0 && rename(temporary_path, path) != 0) {
        code = errno;
    }
    if (code != 0) unlink(temporary_path);
    free(temporary_path);
    return code;
}

static int cocxy_set_close_on_exec(int descriptor) {
    int flags = fcntl(descriptor, F_GETFD);
    if (flags < 0 || fcntl(descriptor, F_SETFD, flags | FD_CLOEXEC) != 0) {
        return errno;
    }
    return 0;
}

static int cocxy_wait_for_escape_child(int descriptor) {
    long long now = cocxy_monotonic_milliseconds();
    if (now < 0) return errno != 0 ? errno : EIO;
    long long deadline = now + 5000;
    struct pollfd poll_descriptor = {
        .fd = descriptor,
        .events = POLLIN,
        .revents = 0,
    };
    for (;;) {
        now = cocxy_monotonic_milliseconds();
        if (now < 0) return errno != 0 ? errno : EIO;
        if (now >= deadline) return ETIMEDOUT;
        long long remaining = deadline - now;
        int poll_timeout = remaining > INT_MAX ? INT_MAX : (int)remaining;
        int poll_result = poll(&poll_descriptor, 1, poll_timeout);
        if (poll_result > 0) break;
        if (poll_result == 0) return ETIMEDOUT;
        if (errno != EINTR) return errno != 0 ? errno : EIO;
    }

    unsigned char ready = 0;
    ssize_t count;
    do {
        count = read(descriptor, &ready, sizeof(ready));
    } while (count < 0 && errno == EINTR);
    if (count != sizeof(ready) || ready != 1) {
        return count < 0 && errno != 0 ? errno : EPIPE;
    }
    return 0;
}

static int cocxy_terminate_escape_child(pid_t child) {
    if (child <= 0) return 0;
    if (kill(child, SIGKILL) != 0 && errno != ESRCH) return errno;
    return cocxy_reap_child(child, cocxy_reap_timeout_milliseconds);
}

static int cocxy_run_escape_parent(
    char **arguments,
    const char *evidence_path
) {
    const char *executable = arguments[0];
    void *handle = dlopen(
        "/usr/lib/system/libquarantine.dylib",
        RTLD_NOW | RTLD_LOCAL
    );
    if (handle == NULL) return ENOTSUP;

    cocxy_set_disclaim_fn set_disclaim = (cocxy_set_disclaim_fn)dlsym(
        handle,
        "responsibility_spawnattrs_setdisclaim"
    );
    cocxy_get_responsible_fn get_responsible = (cocxy_get_responsible_fn)dlsym(
        handle,
        "responsibility_get_pid_responsible_for_pid"
    );
    if (set_disclaim == NULL || get_responsible == NULL) {
        dlclose(handle);
        return ENOTSUP;
    }

    posix_spawnattr_t attributes;
    int code = posix_spawnattr_init(&attributes);
    if (code != 0) {
        dlclose(handle);
        return code;
    }
    code = set_disclaim(&attributes, 1);
    if (code == 0) {
        short flags = POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT;
        code = posix_spawnattr_setflags(&attributes, flags);
    }

    int ready_pipe[2] = {-1, -1};
    posix_spawn_file_actions_t file_actions;
    int file_actions_initialized = 0;
    if (code == 0 && pipe(ready_pipe) != 0) code = errno;
    if (code == 0) code = cocxy_set_close_on_exec(ready_pipe[0]);
    if (code == 0) code = cocxy_set_close_on_exec(ready_pipe[1]);
    if (code == 0) {
        code = posix_spawn_file_actions_init(&file_actions);
        if (code == 0) file_actions_initialized = 1;
    }
    if (code == 0) {
        code = posix_spawn_file_actions_addinherit_np(&file_actions, ready_pipe[1]);
    }

    char ready_descriptor[32];
    int ready_count = snprintf(
        ready_descriptor,
        sizeof(ready_descriptor),
        "%d",
        ready_pipe[1]
    );
    if (code == 0 && (ready_count <= 0 || ready_count >= (int)sizeof(ready_descriptor))) {
        code = EOVERFLOW;
    }

    pid_t child = 0;
    if (code == 0 && (unsetenv(cocxy_escape_evidence_environment) != 0
        || setenv(cocxy_escape_child_environment, "1", 1) != 0
        || setenv(cocxy_escape_ready_fd_environment, ready_descriptor, 1) != 0)) {
        code = errno;
    }
    if (code == 0) {
        code = posix_spawn(
            &child,
            executable,
            &file_actions,
            &attributes,
            arguments,
            environ
        );
    }
    unsetenv(cocxy_escape_child_environment);
    unsetenv(cocxy_escape_ready_fd_environment);
    if (file_actions_initialized) posix_spawn_file_actions_destroy(&file_actions);
    posix_spawnattr_destroy(&attributes);
    if (ready_pipe[1] >= 0) close(ready_pipe[1]);

    if (code == 0) code = cocxy_wait_for_escape_child(ready_pipe[0]);
    if (ready_pipe[0] >= 0) close(ready_pipe[0]);

    if (code == 0) {
        struct proc_bsdinfo info = {0};
        int info_size = proc_pidinfo(
            child,
            PROC_PIDTBSDINFO,
            0,
            &info,
            (int)sizeof(info)
        );
        if (info_size != (int)sizeof(info)) {
            code = errno != 0 ? errno : ESRCH;
        }
        if (code == 0) {
            code = cocxy_write_escape_evidence(
                evidence_path,
                child,
                get_responsible(child),
                getsid(child),
                (unsigned long long)info.pbi_start_tvsec,
                (unsigned long long)info.pbi_start_tvusec
            );
        }
    }
    if (code != 0) {
        int cleanup_code = cocxy_terminate_escape_child(child);
        if (cleanup_code != 0) code = cleanup_code;
    }
    dlclose(handle);
    return code;
}

__attribute__((constructor))
static void cocxy_test_runtime_install_signal_guards(void) {
    signal(SIGPIPE, SIG_IGN);

    int namespace_code = cocxy_install_process_test_namespace();
    if (namespace_code != 0) _exit(namespace_code);

    char **arguments = *_NSGetArgv();
    if (getenv(cocxy_zombie_peer_environment) != NULL) {
        _exit(cocxy_run_zombie_peer());
    }
    if (getenv(cocxy_escape_child_environment) != NULL) {
        _exit(cocxy_run_escape_child());
    }
    const char *evidence_path = getenv(cocxy_escape_evidence_environment);
    if (evidence_path != NULL && evidence_path[0] != '\0') {
        _exit(cocxy_run_escape_parent(arguments, evidence_path));
    }
}
