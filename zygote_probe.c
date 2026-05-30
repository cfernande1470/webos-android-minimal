#include <sys/socket.h>
#include <sys/un.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <stdlib.h>

static void die(const char *m) {
    perror(m);
    exit(1);
}

int main(int argc, char **argv) {
    const char *path;
    int fd;
    struct sockaddr_un addr;
    struct timeval tv;
    const char *req = "1\n--query-abi-list\n";
    unsigned char lenbuf[4];
    unsigned int n;
    char *buf;

    if (argc != 2) {
        fprintf(stderr, "usage: %s /path/to/zygote/socket\n", argv[0]);
        return 2;
    }

    path = argv[1];

    fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) die("socket");

    tv.tv_sec = 5;
    tv.tv_usec = 0;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;

    if (strlen(path) >= sizeof(addr.sun_path)) {
        fprintf(stderr, "path too long\n");
        return 3;
    }

    strcpy(addr.sun_path, path);

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) die("connect");

    if (write(fd, req, strlen(req)) != (ssize_t)strlen(req)) die("write");

    if (read(fd, lenbuf, 4) != 4) die("read length");

    n = ((unsigned int)lenbuf[0] << 24) |
        ((unsigned int)lenbuf[1] << 16) |
        ((unsigned int)lenbuf[2] << 8) |
        ((unsigned int)lenbuf[3]);

    if (n == 0 || n > 4096) {
        fprintf(stderr, "bad length: %u\n", n);
        return 4;
    }

    buf = calloc(1, n + 1);
    if (!buf) die("calloc");

    if (read(fd, buf, n) != (ssize_t)n) die("read payload");

    printf("ABI_LIST=%s\n", buf);

    close(fd);
    return 0;
}
