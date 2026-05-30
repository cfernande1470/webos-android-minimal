#define _GNU_SOURCE
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int make_socket_fd(const char *host_path, mode_t mode) {
    int fd;
    struct sockaddr_un addr;

    unlink(host_path);

    fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        perror("socket");
        exit(11);
    }

    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;

    if (strlen(host_path) >= sizeof(addr.sun_path)) {
        fprintf(stderr, "socket path too long: %s\n", host_path);
        exit(12);
    }

    strcpy(addr.sun_path, host_path);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("bind");
        exit(13);
    }

    chmod(host_path, mode);

    if (listen(fd, 50) < 0) {
        perror("listen");
        exit(14);
    }

    return fd;
}

int main(int argc, char **argv) {
    const char *rootfs;
    const char *zygote_host_socket;
    const char *usap_host_socket;
    int zfd, ufd;

    if (argc < 5) {
        fprintf(stderr,
            "usage: %s ROOTFS HOST_ZYGOTE_SOCKET HOST_USAP_SOCKET PROGRAM [ARGS...]\n",
            argv[0]);
        return 2;
    }

    rootfs = argv[1];
    zygote_host_socket = argv[2];
    usap_host_socket = argv[3];

    zfd = make_socket_fd(zygote_host_socket, 0666);
    ufd = make_socket_fd(usap_host_socket, 0666);

    if (dup2(zfd, 3) < 0) {
        perror("dup2 zygote");
        return 21;
    }

    if (dup2(ufd, 4) < 0) {
        perror("dup2 usap");
        return 22;
    }

    if (zfd != 3) close(zfd);
    if (ufd != 4) close(ufd);

    setenv("ANDROID_SOCKET_zygote", "3", 1);
    setenv("ANDROID_SOCKET_usap_pool_primary", "4", 1);

    if (chroot(rootfs) < 0) {
        perror("chroot");
        return 31;
    }

    if (chdir("/") < 0) {
        perror("chdir");
        return 32;
    }

    execv(argv[4], &argv[4]);

    perror("execv");
    return 40;
}
