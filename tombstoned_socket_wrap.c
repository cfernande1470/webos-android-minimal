#define _GNU_SOURCE
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int make_android_socket(const char *rootfs, const char *name) {
    char path[512];
    snprintf(path, sizeof(path), "%s/dev/socket/%s", rootfs, name);

    unlink(path);

    int fd = socket(AF_UNIX, SOCK_SEQPACKET, 0);
    if (fd < 0) {
        perror("socket SOCK_SEQPACKET");
        fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (fd < 0) {
            perror("socket SOCK_STREAM");
            exit(2);
        }
    }

    int flags = fcntl(fd, F_GETFD);
    if (flags >= 0) fcntl(fd, F_SETFD, flags & ~FD_CLOEXEC);

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;

    if (strlen(path) >= sizeof(addr.sun_path)) {
        fprintf(stderr, "socket path too long: %s\n", path);
        exit(2);
    }

    strcpy(addr.sun_path, path);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        fprintf(stderr, "bind %s failed: %s\n", path, strerror(errno));
        exit(2);
    }

    chmod(path, 0666);

    if (listen(fd, 128) != 0) {
        fprintf(stderr, "listen %s failed: %s\n", path, strerror(errno));
        exit(2);
    }

    return fd;
}

static void set_socket_env(const char *envname, int fd) {
    char val[32];
    snprintf(val, sizeof(val), "%d", fd);
    setenv(envname, val, 1);
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s ROOTFS /system/bin/tombstoned [args...]\n", argv[0]);
        return 2;
    }

    const char *rootfs = argv[1];

    char sockdir[512];
    snprintf(sockdir, sizeof(sockdir), "%s/dev/socket", rootfs);
    mkdir(sockdir, 0777);

    int crash = make_android_socket(rootfs, "tombstoned_crash");
    int intercept = make_android_socket(rootfs, "tombstoned_intercept");
    int java_trace = make_android_socket(rootfs, "tombstoned_java_trace");

    set_socket_env("ANDROID_SOCKET_tombstoned_crash", crash);
    set_socket_env("ANDROID_SOCKET_tombstoned_intercept", intercept);
    set_socket_env("ANDROID_SOCKET_tombstoned_java_trace", java_trace);

    if (chroot(rootfs) != 0) {
        perror("chroot");
        return 2;
    }

    chdir("/");

    execv(argv[2], &argv[2]);
    perror("execv tombstoned");
    return 127;
}
