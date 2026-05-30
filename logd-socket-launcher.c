#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

static int clear_cloexec(int fd) {
    int flags = fcntl(fd, F_GETFD);
    if (flags < 0) return -1;
    return fcntl(fd, F_SETFD, flags & ~FD_CLOEXEC);
}

static int make_socket_fd(const char *name, int type, mode_t mode, int do_listen) {
    char path[256];
    snprintf(path, sizeof(path), "/dev/socket/%s", name);

    unlink(path);

    int fd = socket(AF_UNIX, type, 0);
    if (fd < 0) {
        fprintf(stderr, "socket %s failed: %s\n", name, strerror(errno));
        exit(10);
    }

    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_PASSCRED, &one, sizeof(one));

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", path);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        fprintf(stderr, "bind %s failed: %s\n", path, strerror(errno));
        exit(11);
    }

    chmod(path, mode);

    if (do_listen && listen(fd, 64) < 0) {
        fprintf(stderr, "listen %s failed: %s\n", path, strerror(errno));
        exit(12);
    }

    clear_cloexec(fd);

    char envname[128];
    char envval[32];
    snprintf(envname, sizeof(envname), "ANDROID_SOCKET_%s", name);
    snprintf(envval, sizeof(envval), "%d", fd);
    setenv(envname, envval, 1);

    fprintf(stderr, "%s fd=%d path=%s\n", envname, fd, path);
    return fd;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: logd-socket-launcher /system/bin/logd [args...]\n");
        return 2;
    }

    mkdir("/dev/socket", 0777);
    chmod("/dev/socket", 0777);

    make_socket_fd("logd",  SOCK_STREAM,    0666, 1);
    make_socket_fd("logdr", SOCK_SEQPACKET, 0666, 1);
    make_socket_fd("logdw", SOCK_DGRAM,     0222, 0);

    execv(argv[1], &argv[1]);
    fprintf(stderr, "execv %s failed: %s\n", argv[1], strerror(errno));
    return 127;
}
