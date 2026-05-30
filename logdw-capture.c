#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

static int printable(int c) {
    return (c >= 32 && c <= 126) || c == '\n' || c == '\t' || c == '\r';
}

static void dump_strings(unsigned char *buf, ssize_t n) {
    char out[8192];
    int oi = 0;
    int run = 0;

    for (ssize_t i = 0; i < n && oi < (int)sizeof(out) - 4; i++) {
        unsigned char c = buf[i];
        if (printable(c)) {
            out[oi++] = c;
            run++;
        } else {
            if (run >= 4) {
                out[oi++] = ' ';
            }
            run = 0;
        }
    }
    out[oi] = 0;

    if (oi > 0) {
        printf("%s\n", out);
        fflush(stdout);
    }
}

int main(int argc, char **argv) {
    const char *path = "/dev/socket/logdw";

    mkdir("/dev/socket", 0777);
    unlink(path);

    int fd = socket(AF_UNIX, SOCK_DGRAM, 0);
    if (fd < 0) {
        perror("socket");
        return 2;
    }

    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_PASSCRED, &one, sizeof(one));

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", path);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("bind logdw");
        return 3;
    }

    chmod(path, 0666);

    fprintf(stderr, "LOGDW_CAPTURE_READY path=%s fd=%d\n", path, fd);
    fflush(stderr);

    unsigned char buf[65536];

    for (;;) {
        ssize_t n = recv(fd, buf, sizeof(buf), 0);
        if (n < 0) {
            if (errno == EINTR) continue;
            perror("recv");
            return 4;
        }

        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        printf("\n--- packet bytes=%zd time=%ld.%09ld ---\n", n, ts.tv_sec, ts.tv_nsec);
        dump_strings(buf, n);
    }
}
