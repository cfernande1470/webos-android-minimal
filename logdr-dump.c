#define _GNU_SOURCE
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

struct logger_entry_v4 {
    uint16_t len;
    uint16_t hdr_size;
    int32_t  pid;
    uint32_t tid;
    uint32_t sec;
    uint32_t nsec;
    uint32_t lid;
    uint32_t uid;
};

static int connect_logdr(void) {
    int fd = socket(AF_UNIX, SOCK_SEQPACKET, 0);
    if (fd < 0) {
        perror("socket");
        exit(2);
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    snprintf(addr.sun_path, sizeof(addr.sun_path), "/dev/socket/logdr");

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("connect /dev/socket/logdr");
        exit(3);
    }

    return fd;
}

static int printable_enough(const char *p, int n) {
    int ok = 0;
    for (int i = 0; i < n; i++) {
        unsigned char c = p[i];
        if ((c >= 32 && c <= 126) || c == '\n' || c == '\t') ok++;
    }
    return ok > n / 2;
}

static void dump_packet(unsigned char *buf, ssize_t n) {
    if (n < (ssize_t)sizeof(struct logger_entry_v4)) {
        fwrite(buf, 1, n, stdout);
        putchar('\n');
        return;
    }

    struct logger_entry_v4 *e = (struct logger_entry_v4 *)buf;

    if (e->hdr_size < 20 || e->hdr_size > 64 || e->hdr_size > n || e->len > n) {
        fwrite(buf, 1, n, stdout);
        putchar('\n');
        return;
    }

    unsigned char *msg = buf + e->hdr_size;
    int msglen = n - e->hdr_size;
    if (msglen <= 0) return;

    int prio = msg[0];
    char *tag = (char *)(msg + 1);
    int tagmax = msglen - 1;
    int taglen = strnlen(tag, tagmax);
    char *txt = tag + taglen + 1;
    int txtlen = tagmax - taglen - 1;

    if (taglen <= 0 || txtlen <= 0 || !printable_enough(txt, txtlen)) {
        printf("[%u.%09u pid=%d tid=%u lid=%u uid=%u prio=%d] ",
               e->sec, e->nsec, e->pid, e->tid, e->lid, e->uid, prio);
        for (int i = 0; i < msglen; i++) {
            unsigned char c = msg[i];
            putchar((c >= 32 && c <= 126) ? c : '.');
        }
        putchar('\n');
        return;
    }

    printf("[%u.%09u pid=%d tid=%u lid=%u uid=%u prio=%d] %s: %.*s\n",
           e->sec, e->nsec, e->pid, e->tid, e->lid, e->uid, prio,
           tag, txtlen, txt);
}

int main(int argc, char **argv) {
    const char *cmd = "dumpAndClose lids=0,1,2,3,4,5 tail=3000";
    if (argc > 1) cmd = argv[1];

    int fd = connect_logdr();

    if (send(fd, cmd, strlen(cmd) + 1, 0) < 0) {
        perror("send command");
        return 4;
    }

    unsigned char buf[65536];
    for (;;) {
        ssize_t n = recv(fd, buf, sizeof(buf), 0);
        if (n == 0) break;
        if (n < 0) {
            perror("recv");
            return 5;
        }
        dump_packet(buf, n);
    }

    close(fd);
    return 0;
}
