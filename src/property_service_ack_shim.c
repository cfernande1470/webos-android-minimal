#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/poll.h>
#include <signal.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>

static void die(const char *m) {
    perror(m);
    exit(1);
}

int main(int argc, char **argv) {
    const char *path = argc > 1 ? argv[1] : "/dev/socket/property_service";
    signal(SIGPIPE, SIG_IGN);

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) die("socket");

    unlink(path);

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", path);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) die("bind");
    chmod(path, 0666);

    if (listen(fd, 16) < 0) die("listen");

    for (;;) {
        int c = accept(fd, NULL, NULL);
        if (c < 0) {
            if (errno == EINTR) continue;
            continue;
        }

        char buf[4096];
        struct pollfd pfd = { .fd = c, .events = POLLIN };

        while (poll(&pfd, 1, 100) > 0) {
            ssize_t n = read(c, buf, sizeof(buf));
            if (n <= 0) break;
            if (n < (ssize_t)sizeof(buf)) break;
        }

        int32_t ok = 0;
        ssize_t ignored = write(c, &ok, sizeof(ok));
        (void)ignored;
        close(c);
    }
}
